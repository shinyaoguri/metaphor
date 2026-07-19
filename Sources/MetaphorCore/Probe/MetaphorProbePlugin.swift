import Foundation
import Metal
import QuartzCore

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
///
/// ## 性能契約（ランタイム非侵害・Issue #118）
///
/// - **OFF（未登録＝通常実行 / 人間のライブビューア単体）**: プラグインが `plugins` に
///   居ないため、フレームループのプラグイン呼び出しはゼロ回。`Sketch/probe(_:_:)` も
///   `MetaphorRenderer/probePlugin` が `nil` に解決され**完全 no-op**。ホットパスに
///   `probe(...)` を残して安全。
/// - **ON（登録済み）**: `pre()` は毎フレーム `stateBuffer` リセット＋リクエストファイルの
///   `stat()` 1 回のみ（µs オーダー）。`post()` は保留リクエストが無い間は即 `return`。
///   重い処理（GPU readback → PNG/JSON 書き出し）は**リクエスト時のみ**、かつ
///   `deferReadback`/completion handler 経由で**GPU 完了後・描画スレッド外**に実行する。
///   `performance`（#271）の syscall（メモリ・CPU・thermal）も**リクエスト時のみ**。
///   実測 fps の元データは ``FrameRateTracker``（レンダラー側・プラグイン ON/OFF に
///   よらずリングバッファ書き込み 1 回/フレーム、ns オーダー）が常時蓄積する。
///
/// この契約は `Tests/metaphorTests/ObservabilityOverheadTests.swift` の回帰ガードで守る。
@MainActor
public final class MetaphorProbePlugin: MetaphorPlugin {
    public static let id = "org.metaphor.probe"

    public let pluginID: String

    /// プラグイン設定。
    public let config: MetaphorProbeConfig

    /// 解決済みのソース世代刻印（provenance）。`config.sourceStamp` を優先し、
    /// なければ環境変数 `METAPHOR_SOURCE_STAMP`（空文字は無視）をフォールバックに使う。
    /// 明示登録（`PluginFactory`）と env 自動登録の両経路で機能させるため、
    /// SketchRunner ではなくプラグイン側で解決する。
    let sourceStamp: String?

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

    /// メモリ・CPU の syscall サンプラー（Issue #271）。CPU 差分の起点を保持するため
    /// プラグイン生成時（≒スケッチ起動時）に作る。呼び出しはリクエスト処理時のみ。
    private let statsSampler: ProcessStatsSampler

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
        /// 出力画像のスケール（正規化済み。契約点 4）。
        let scale: Float
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
        self.sourceStamp = MetaphorProbePlugin.resolveSourceStamp(config: config)
        self.statsSampler = ProcessStatsSampler(now: CACurrentMediaTime())
    }

    /// `config.sourceStamp` → 環境変数 `METAPHOR_SOURCE_STAMP`（空文字は無視）の順で解決。
    private static func resolveSourceStamp(config: MetaphorProbeConfig) -> String? {
        if let stamp = config.sourceStamp, !stamp.isEmpty { return stamp }
        if let env = ProcessInfo.processInfo.environment["METAPHOR_SOURCE_STAMP"],
           !env.isEmpty {
            return env
        }
        return nil
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
            // 失敗を無応答にしない: warnings 付きの frame.json（PNG なし）で応答し、
            // consumer がタイムアウトではなく id 一致で失敗を検知できるようにする
            //（シーケンス経路の warning 付き manifest と対称）。
            ProbeWriter.writeFailureResponse(
                directory: config.outputDirectory,
                metadata: failureMetadata(
                    id: request.id, label: request.label,
                    width: width, height: height,
                    warning: "failed to allocate staging texture; frame.png was not written"
                )
            )
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

        // schemaVersion 4: additive に `sourceStamp`（provenance）と `performance`
        //（実測パフォーマンス #271）を追加。v3 で `customTypes`、v2 で `stats` を追加済み。
        // `stats` / `warnings` は ProbeWriter がピクセル読み出し後に enrich する。
        let custom = stateBuffer.snapshot()
        let customTypes = custom.mapValues { $0.typeTag }
        let metadata = ProbeFrameMetadata(
            schemaVersion: 4,
            id: request.id,
            label: request.label,
            sourceStamp: sourceStamp,
            frame: sketch?._context?.frameCount ?? 0,
            time: lastFrameTime,
            size: ProbeFrameMetadata.Size(width: width, height: height),
            custom: custom,
            customTypes: customTypes,
            warnings: [],
            stats: nil,
            performance: samplePerformance()
        )

        let outputDirectory = config.outputDirectory
        // 出力画像のスケール（契約点 4）。リクエスト優先、なければ defaultScale。
        let scale = ProbeWriter.normalizeScale(request.scale ?? config.defaultScale)
        let writeWork: @Sendable () -> Void = {
            ProbeWriter.writeSnapshot(
                staging: staging,
                width: width,
                height: height,
                scale: scale,
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
            // contact sheet / manifest の参照サイズは実際に書き出す PNG のサイズ
            //（scale 適用後）に合わせる
            let scaled = ProbeWriter.scaledSize(width: width, height: height, scale: seq.scale)
            seq.refWidth = scaled.width
            seq.refHeight = scaled.height
        }

        let frameNo = sketch?._context?.frameCount ?? 0
        let custom = stateBuffer.snapshot()
        let customTypes = custom.mapValues { $0.typeTag }
        // `performance` は単一フレーム経路のみ（#271）。per-frame で全フィールドは
        // 冗長で、フレームループ内の syscall も避ける。時系列の性能観測に需要が
        // 出たら「per-frame は fps のみ + manifest にサマリ」等を別途検討する。
        let metadata = ProbeFrameMetadata(
            schemaVersion: 4,
            id: seq.id,
            label: seq.label,
            sourceStamp: sourceStamp,
            frame: frameNo,
            time: lastFrameTime,
            size: ProbeFrameMetadata.Size(width: width, height: height),
            custom: custom,
            customTypes: customTypes,
            warnings: [],
            stats: nil,
            performance: nil
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

        let scale = seq.scale
        let writeWork: @Sendable () -> Void = {
            ProbeWriter.writeSequenceFrame(
                staging: staging, width: width, height: height, scale: scale,
                directory: dir, index: index, metadata: metadata,
                // 最初のフレームで前シーケンスの出力を（書き出しキュー上で）掃除する
                cleanDirectoryFirst: index == 0
            )
            guard let manifestBase else { return }
            // contact sheet 合成と sequence.json（完了シグナル）の書き出しは
            // ProbeWriter の直列キューに積まれ、全フレームの書き出し後に実行される。
            ProbeWriter.finalizeSequence(
                directory: dir, manifest: manifestBase,
                frameFiles: frameFiles, refWidth: refW, refHeight: refH
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
        // 1 フレームも書けずに終わる場合、前シーケンスの掃除がまだなので manifest
        // 書き出し時に行う（フレームを書いた後なら掃除はフレーム 0 で実施済み）。
        let cleanFirst = seq.captured == 0
        let work: @Sendable () -> Void = {
            ProbeWriter.writeManifest(
                directory: dir, manifest: manifest, cleanDirectoryFirst: cleanFirst
            )
        }
        if let renderer {
            renderer.deferReadback(commandBuffer: commandBuffer, work)
        } else {
            commandBuffer.addCompletedHandler { _ in work() }
        }
    }

    /// リクエストファイルの mtime を確認し、変化があれば JSON を読んで `pendingRequest` をセット。
    ///
    /// `lastRequestMTime` はリクエストを**消費できた経路でのみ**確定する。
    /// 読み取り失敗（部分書き込み等）やシーケンス進行中に mtime を先に確定すると、
    /// そのリクエストが永久に無視されるため。
    private func pollRequestFile() {
        let path = config.requestFilePath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return
        }

        if let last = lastRequestMTime, last == mtime {
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            // 読めない（部分書き込み等）。mtime を確定せず次フレームで再試行する。
            metaphorDiagnostic("probe: request.json を読めませんでした（次フレームで再試行）: \(path)")
            return
        }
        guard let request = try? JSONDecoder().decode(ProbeRequest.self, from: data) else {
            // 不正な request.json は再読しても直らないので mtime を確定して無視。
            // consumer は .tmp→rename でアトミックに書く規約（CONTRACT.md 契約点 4）。
            lastRequestMTime = mtime
            metaphorDiagnostic("probe: request.json をデコードできませんでした（無視）")
            return
        }

        if request.id == lastHandledRequestId {
            lastRequestMTime = mtime
            return
        }

        // シーケンス進行中は mtime を確定せず保留する。シーケンス完了後の pre() で
        // 同じファイルが再読され、届いていた新規リクエストが失われない。
        if activeSequence != nil {
            return
        }

        lastRequestMTime = mtime
        if (request.frames ?? 1) >= 2 {
            beginSequence(request)
        } else {
            pendingRequest = request
        }
    }

    /// 失敗応答用の frame.json メタデータを組み立てます。
    private func failureMetadata(
        id: String, label: String?, width: Int, height: Int, warning: String
    ) -> ProbeFrameMetadata {
        ProbeFrameMetadata(
            schemaVersion: 4,
            id: id,
            label: label,
            sourceStamp: sourceStamp,
            frame: sketch?._context?.frameCount ?? 0,
            time: lastFrameTime,
            size: ProbeFrameMetadata.Size(width: width, height: height),
            custom: [:],
            customTypes: [:],
            warnings: [warning],
            stats: nil,
            performance: nil
        )
    }

    /// `frame.json` の `performance` セクションを組み立てます（Issue #271）。
    ///
    /// syscall（メモリ・CPU）はこのリクエスト処理時のみ発行され、リクエストが
    /// 無いフレームのコストは fps トラッカーの常時更新だけです（性能契約 #118）。
    /// レンダラー未接続（テスト等）では全体を省略します。
    private func samplePerformance() -> ProbeFrameMetadata.Performance? {
        guard let renderer else { return nil }
        let now = CACurrentMediaTime()
        let window = renderer.frameRateTracker.windowStats(now: now)
        return ProbeFrameMetadata.Performance(
            fps: window.map { Self.round1($0.fps) },
            targetFPS: renderer.targetFPS,
            frameTimeMs: window.map {
                ProbeFrameMetadata.Performance.FrameTime(
                    mean: Self.round1($0.frameTimeMeanMs),
                    max: Self.round1($0.frameTimeMaxMs)
                )
            },
            memoryMB: ProcessStatsSampler.memoryFootprintMB().map(Self.round1),
            cpuPercent: statsSampler.cpuPercent(now: now).map(Self.round1),
            thermalState: ProcessStatsSampler.thermalStateName()
        )
    }

    /// JSON の可読性（と AI へのトークン効率）のため 0.1 単位へ丸めます。
    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
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

        // 旧シーケンス出力の掃除はここでは行わない。前シーケンスの書き出しは
        // ProbeWriter の直列キューに非同期で積まれる（GPU 完了待ちでまだ積まれて
        // すらいないこともある）ため、ここで同期削除すると削除後に旧ファイルが
        // 復活し得る。掃除は最初のフレーム書き出し時に同じキュー上で行う
        // （writeSequenceFrame / writeManifest の cleanDirectoryFirst）。

        activeSequence = ActiveCapture(
            id: request.id,
            label: request.label,
            total: total,
            requested: requested,
            every: every,
            scale: ProbeWriter.normalizeScale(request.scale ?? config.defaultScale),
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
