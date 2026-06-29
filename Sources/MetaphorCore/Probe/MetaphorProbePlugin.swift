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

    /// 連続キャプチャ（`frames >= 2`）の進行状態。`nil` の間は単一フレーム経路のまま、
    /// ホットパスのコストはゼロ。
    private var activeSequence: ActiveCapture?

    /// 連続キャプチャの上限フレーム数（ディスク使用量と readback backpressure の保護）。
    private static let maxSequenceFrames = 64

    /// 連続キャプチャの進行状態。`post()` をまたいで採取枚数・ストライド・manifest を蓄積。
    private struct ActiveCapture {
        let id: String
        let label: String?
        /// 実際に採取する枚数（クランプ・degrade 後）。
        let total: Int
        /// リクエストされた枚数（クランプ前。manifest に透明性のため記録）。
        let requested: Int
        /// 採取間隔（ストライド）。
        let every: Int
        /// シーケンス全体の警告（クランプ・degrade 等）。
        let warnings: [String]
        /// 採取済み枚数。
        var captured: Int = 0
        /// シーケンス開始からの `post()` 回数（ストライド判定用）。
        var tick: Int = 0
        /// 最初に採取したフレームのサイズ（contact sheet のセル基準）。
        var refWidth: Int = 0
        var refHeight: Int = 0
        /// フレームごとの manifest エントリ。
        var entries: [ProbeSequenceManifest.Entry] = []
    }

    /// 連続キャプチャの出力先（`outputDirectory/sequence`）。
    private var sequenceDirectory: String {
        (config.outputDirectory as NSString).appendingPathComponent("sequence")
    }

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
        // 連続キャプチャ進行中はそちらへ（単一フレーム経路には触れない）。
        if activeSequence != nil {
            handleSequenceFrame(texture: texture, commandBuffer: commandBuffer)
            return
        }

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

    /// 連続キャプチャの 1 フレームを処理します。ストライドで採取要否を判定し、採取フレームは
    /// 単一フレームと同じ blit→staging→`deferReadback`→`ProbeWriter` 経路で
    /// `sequence/frame.NNNN.{png,json}` に書き出します。最後のフレームでは（全 PNG が
    /// 出揃った状態で）contact sheet と manifest も書きます。
    private func handleSequenceFrame(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard var seq = activeSequence else { return }

        // ストライド: tick が every の倍数のときだけ採取（それ以外は実質ゼロコスト）。
        let shouldCapture = (seq.tick % seq.every == 0)
        seq.tick += 1
        if !shouldCapture {
            activeSequence = seq
            return
        }

        let index = seq.captured
        let width = texture.width
        let height = texture.height
        let bufferIndex = renderer?.frameBufferIndex ?? 0

        guard let staging = getOrCreateStaging(
            device: texture.device, width: width, height: height, bufferIndex: bufferIndex
        ) else {
            // ステージング確保失敗。ここまでの結果で manifest を書いて中断する。
            finishSequenceWithoutFrame(
                seq, commandBuffer: commandBuffer,
                extraWarning: "failed to allocate staging texture at frame \(index)"
            )
            activeSequence = nil
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

        if index == 0 {
            seq.refWidth = width
            seq.refHeight = height
        }

        let frameNo = sketch?._context?.frameCount ?? 0
        let custom = stateBuffer.snapshot()
        let customTypes = custom.mapValues { $0.typeTag }
        let metadata = ProbeFrameMetadata(
            schemaVersion: 3,
            id: seq.id,
            label: seq.label,
            frame: frameNo,
            time: lastFrameTime,
            size: ProbeFrameMetadata.Size(width: width, height: height),
            custom: custom,
            customTypes: customTypes,
            warnings: [],
            stats: nil
        )

        let base = ProbeWriter.sequenceBaseName(index)
        seq.entries.append(ProbeSequenceManifest.Entry(
            index: index,
            file: "\(base).png",
            metadata: "\(base).json",
            frame: frameNo,
            time: lastFrameTime
        ))
        seq.captured += 1

        let isLast = seq.captured >= seq.total
        let dir = sequenceDirectory

        // 最後のフレームでは contact sheet と manifest も書く。完了ハンドラはコミット順に
        // 直列実行されるため、この時点で先行フレームの PNG はすべて出揃っている。
        let manifestBase: ProbeSequenceManifest? = isLast ? ProbeSequenceManifest(
            schemaVersion: 1,
            id: seq.id,
            label: seq.label,
            frameCount: seq.captured,
            requestedFrames: seq.requested,
            every: seq.every,
            size: ProbeFrameMetadata.Size(width: seq.refWidth, height: seq.refHeight),
            contactSheet: nil,
            warnings: seq.warnings,
            frames: seq.entries
        ) : nil
        let frameFiles = isLast ? seq.entries.map { $0.file } : []
        let refW = seq.refWidth
        let refH = seq.refHeight

        let writeWork: @Sendable () -> Void = {
            ProbeWriter.writeSequenceFrame(
                staging: staging, width: width, height: height,
                directory: dir, index: index, metadata: metadata
            )
            guard let manifestBase else { return }
            let sheet = ProbeWriter.writeContactSheet(
                directory: dir, frameFiles: frameFiles, refWidth: refW, refHeight: refH
            )
            // contact sheet の有無を反映し、sequence.json を最後に原子書き出し（完了シグナル）。
            ProbeWriter.writeManifest(
                directory: dir,
                manifest: ProbeSequenceManifest(
                    schemaVersion: manifestBase.schemaVersion,
                    id: manifestBase.id,
                    label: manifestBase.label,
                    frameCount: manifestBase.frameCount,
                    requestedFrames: manifestBase.requestedFrames,
                    every: manifestBase.every,
                    size: manifestBase.size,
                    contactSheet: sheet,
                    warnings: manifestBase.warnings,
                    frames: manifestBase.frames
                )
            )
        }

        if let renderer {
            renderer.deferReadback(commandBuffer: commandBuffer, writeWork)
        } else {
            commandBuffer.addCompletedHandler { _ in writeWork() }
        }

        activeSequence = isLast ? nil : seq
    }

    /// フレームを採取できないままシーケンスを終了する場合に、ここまでの manifest を
    /// （先行フレームの書き出し後に）書きます。完了規約のため commandBuffer 完了に乗せます。
    private func finishSequenceWithoutFrame(
        _ seq: ActiveCapture, commandBuffer: MTLCommandBuffer, extraWarning: String
    ) {
        let dir = sequenceDirectory
        let manifest = ProbeSequenceManifest(
            schemaVersion: 1,
            id: seq.id,
            label: seq.label,
            frameCount: seq.captured,
            requestedFrames: seq.requested,
            every: seq.every,
            size: ProbeFrameMetadata.Size(width: seq.refWidth, height: seq.refHeight),
            contactSheet: nil,
            warnings: seq.warnings + [extraWarning],
            frames: seq.entries
        )
        let work: @Sendable () -> Void = {
            ProbeWriter.writeManifest(directory: dir, manifest: manifest)
        }
        if let renderer {
            renderer.deferReadback(commandBuffer: commandBuffer, work)
        } else {
            commandBuffer.addCompletedHandler { _ in work() }
        }
    }

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
            // mtime は進んだが読めない（部分書き込み等）。次フレームで再試行する。
            metaphorDiagnostic("probe: request.json を読めませんでした（次フレームで再試行）: \(path)")
            return
        }
        guard let request = try? JSONDecoder().decode(ProbeRequest.self, from: data) else {
            // 不正な request.json。consumer は .tmp→rename でアトミックに書く規約（CONTRACT.md 契約点 4）。
            metaphorDiagnostic("probe: request.json をデコードできませんでした（無視）")
            return
        }

        if request.id == lastHandledRequestId {
            return
        }

        // シーケンス進行中は新規リクエストを無視（現行シーケンスを優先）。
        if activeSequence != nil {
            return
        }

        if (request.frames ?? 1) >= 2 {
            beginSequence(request)
        } else {
            pendingRequest = request
        }
    }

    /// 連続キャプチャを開始します。フレーム数のクランプ、noLoop 時の degrade、
    /// 旧シーケンス出力の掃除を行い、`activeSequence` を立てます。
    private func beginSequence(_ request: ProbeRequest) {
        let requested = request.frames ?? 1
        let clamped = min(max(requested, 1), Self.maxSequenceFrames)
        let every = max(request.every ?? 1, 1)
        let looping = sketch?._context?.isLooping ?? true

        var warnings: [String] = []
        var total = clamped
        if !looping {
            // noLoop 中は後続フレームが来ず採取が止まるため、単一フレームに degrade。
            total = 1
            warnings.append(
                "sketch is paused (noLoop); captured a single frame instead of \(clamped)"
            )
        } else if clamped < requested {
            warnings.append(
                "frames clamped from \(requested) to \(clamped) (max \(Self.maxSequenceFrames))"
            )
        }

        // 旧シーケンス出力を掃除（前回の余分なフレームが残らないように）。
        try? FileManager.default.removeItem(atPath: sequenceDirectory)

        activeSequence = ActiveCapture(
            id: request.id,
            label: request.label,
            total: total,
            requested: requested,
            every: every,
            warnings: warnings
        )
        // 受理時に dedup を確定（mtime 不変でも二重起動しないよう）。
        lastHandledRequestId = request.id
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
