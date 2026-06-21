import Foundation
import Metal

/// AI エージェント向けの観測プラグイン。
///
/// 通常フレームではリクエストファイルの mtime を確認するだけで、
/// ファイルが更新されていない限り描画コストは増えません。
/// AI エージェントが `request.json` を書き込むと、次の `post(texture:)` で
/// 最終オフスクリーンテクスチャを PNG として `<outputDirectory>/frame.png` に
/// 原子的に書き出します。
///
/// 有効化は次の 2 通り。
/// - 環境変数 `METAPHOR_PROBE=1` を設定（自動登録）
/// - `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])` で明示登録
@MainActor
public final class MetaphorProbePlugin: MetaphorPlugin {
    public static let id = "org.metaphor.probe"

    public let pluginID: String

    /// プラグイン設定。
    public let config: MetaphorProbeConfig

    /// 接続中のスケッチへの弱参照。
    weak var sketch: (any Sketch)?

    /// 接続中のレンダラーへの弱参照。`frameBufferIndex` 取得に利用します。
    weak var renderer: MetaphorRenderer?

    /// `frameBufferIndex` でローテーションするステージングテクスチャ（トリプルバッファ）。
    private var stagingPool: [MTLTexture?] = [nil, nil, nil]

    /// 次の `post()` で処理するべきリクエスト。`nil` の間は描画コストゼロ。
    private var pendingRequest: ProbeRequest?

    /// 既に処理済みのリクエスト id。重複処理を防ぎます。
    private var lastHandledRequestId: String?

    /// 直前に観察したリクエストファイルの mtime。変更検出に利用します。
    private var lastRequestMTime: Date?

    /// `Sketch.probe(_:_:)` で蓄積されたユーザー定義値のバッファ。
    let stateBuffer = ProbeStateBuffer()

    /// 直近の `pre()` で受け取った時間。`post()` で frame.json に書き出すのに使います。
    private var lastFrameTime: Double = 0

    public init(config: MetaphorProbeConfig = MetaphorProbeConfig()) {
        self.pluginID = MetaphorProbePlugin.id
        self.config = config
    }

    // MARK: - User-facing API

    /// `Sketch.probe(_:_:)` から呼ばれ、ユーザー定義値を現フレームのバッファに記録します。
    func recordValue(name: String, value: ProbeValue) {
        stateBuffer.set(name, value)
    }

    // MARK: - Lifecycle

    public func onAttach(sketch: any Sketch) {
        self.sketch = sketch
    }

    public func onAttach(renderer: MetaphorRenderer) {
        self.renderer = renderer
    }

    public func onDetach() {
        self.sketch = nil
        self.renderer = nil
        self.stagingPool = [nil, nil, nil]
    }

    public func onStart() {}
    public func onStop() {}
    public func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {}
    public func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {}
    public func onResize(width: Int, height: Int) {}
    public func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}

    // MARK: - Frame hooks

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        // 各フレーム頭でユーザー probe バッファをリセット。
        // draw() の中で probe(...) が呼ばれたものだけがそのフレームの値となる。
        stateBuffer.reset()
        lastFrameTime = time
        pollRequestFile()
    }

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let request = pendingRequest else { return }

        let bufferIndex = renderer?.frameBufferIndex ?? 0
        let width = texture.width
        let height = texture.height

        guard let staging = getOrCreateStaging(
            device: texture.device,
            width: width,
            height: height,
            bufferIndex: bufferIndex
        ) else {
            pendingRequest = nil
            lastHandledRequestId = request.id
            return
        }

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: texture,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: staging,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
        }

        // schemaVersion 3: additive に `customTypes`（probe 値の型タグ）を追加。
        // v2 で `stats`（画像統計）を追加済み。
        // `stats` / `warnings` は ProbeWriter がピクセル読み出し後に enrich する。
        let custom = stateBuffer.snapshot()
        let customTypes = custom.mapValues { $0.typeTag }
        let metadata = ProbeFrameMetadata(
            schemaVersion: 3,
            id: request.id,
            label: request.label,
            frame: sketch?._context?.frameCount ?? 0,
            time: lastFrameTime,
            size: ProbeFrameMetadata.Size(width: width, height: height),
            custom: custom,
            customTypes: customTypes,
            warnings: [],
            stats: nil
        )

        let outputDirectory = config.outputDirectory
        let writeWork: @Sendable () -> Void = {
            ProbeWriter.writeSnapshot(
                staging: staging,
                width: width,
                height: height,
                directory: outputDirectory,
                metadata: metadata
            )
        }
        // 読み戻し（staging からの getBytes + PNG 書き出し）が完了するまで
        // インフライトスロットを解放させないことで、書き出し中に GPU が同じ
        // staging テクスチャを上書きするのを防ぐ。renderer 経由でなければ
        // 従来どおり完了ハンドラに直接登録（gate なし）。
        if let renderer {
            renderer.deferReadback(commandBuffer: commandBuffer, writeWork)
        } else {
            commandBuffer.addCompletedHandler { _ in writeWork() }
        }

        pendingRequest = nil
        lastHandledRequestId = request.id
    }

    // MARK: - Private

    /// リクエストファイルの mtime を確認し、変化があれば JSON を読んで `pendingRequest` をセット。
    private func pollRequestFile() {
        let path = config.requestFilePath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return
        }

        if let last = lastRequestMTime, last == mtime {
            return
        }
        lastRequestMTime = mtime

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return
        }
        guard let request = try? JSONDecoder().decode(ProbeRequest.self, from: data) else {
            return
        }

        if request.id == lastHandledRequestId {
            return
        }
        pendingRequest = request
    }

    /// `bufferIndex` スロットのステージングテクスチャを返すか作成します。
    private func getOrCreateStaging(
        device: MTLDevice, width: Int, height: Int, bufferIndex: Int
    ) -> MTLTexture? {
        let index = max(0, min(bufferIndex, stagingPool.count - 1))
        if let existing = stagingPool[index],
           existing.width == width,
           existing.height == height {
            return existing
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)
        stagingPool[index] = tex
        return tex
    }
}
