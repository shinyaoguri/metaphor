@preconcurrency import Metal
import MetalKit
import QuartzCore
import simd

/// metaphor の Metal レンダリングとオプショナルなランタイム操作を統括します。
@MainActor
public final class MetaphorRenderer: NSObject {
    // MARK: - パブリックプロパティ

    /// 全 GPU リソース作成に使用される Metal デバイス
    public let device: MTLDevice

    /// GPU へのワーク送信に使用されるコマンドキュー
    public let commandQueue: MTLCommandQueue

    /// オフスクリーンレンダーターゲットテクスチャの管理
    public private(set) var textureManager: TextureManager

    /// アプリケーション間映像共有用のオプショナルな Syphon 出力
    public private(set) var syphonOutput: SyphonOutput?

    /// Metal シェーダー関数のコンパイルとキャッシュに使用するシェーダーライブラリ
    public let shaderLibrary: ShaderLibrary

    /// 全レンダーパスで共有されるデプスステンシルステートキャッシュ
    public let depthStencilCache: DepthStencilCache

    /// 共有リソースで作成された場合に利用可能な共有 Metal リソース
    public private(set) var sharedResources: SharedMetalResources?

    /// キーボードとマウスイベント処理用の入力マネージャー
    public let input: InputManager

    /// 各フレームでユーザーレンダリングを実行するために呼び出されるコールバック
    ///
    /// - Parameters:
    ///   - encoder: 現在のオフスクリーンパス用のレンダーコマンドエンコーダー
    ///   - time: レンダラー開始からの経過時間（秒）
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    /// 描画前にコンピュートワークを実行するために呼び出されるコールバック
    ///
    /// - Parameters:
    ///   - commandBuffer: コンピュートエンコーダー作成に使用するコマンドバッファ
    ///   - time: レンダラー開始からの経過時間（秒）
    public var onCompute: ((MTLCommandBuffer, Double) -> Void)?

    /// メイン描画パスの後にシャドウパスなどの追加レンダリングを行うコールバック
    ///
    /// - Parameter commandBuffer: 追加パスのエンコード用コマンドバッファ
    public var onAfterDraw: ((MTLCommandBuffer) -> Void)?

    /// 初期化時に記録されるモノトニック開始時刻
    private let startTime: Double

    // MARK: - ブリットパイプライン

    private var blitPipelineState: MTLRenderPipelineState?

    /// 外部レンダーループがフレームレンダリングを駆動するかどうかを示します。
    ///
    /// `true` の場合、`draw(in:)` は `renderFrame()` を呼ばずにオフスクリーンテクスチャを画面にブリットするのみです。
    public var useExternalRenderLoop: Bool = false

    /// 少なくとも1フレームが画面にブリットされたかどうか。
    /// noLoop() スケッチがウィンドウのオクルージョン状態更新前に
    /// コンテンツを表示できるよう、最初のブリットではオクルージョンチェックをスキップするために使用します。
    private var hasBlittedOnce: Bool = false

    // MARK: - オフラインレンダリング

    /// 決定論的フレームタイミングのオフラインレンダリングモードを有効化
    public var isOfflineRendering: Bool = false

    /// オフラインレンダリングモードでの時間計算に使用するフレームレート
    public var offlineFrameRate: Double = 60.0

    /// オフラインレンダリングモードでの現在のフレームインデックス
    private var offlineFrameIndex: Int = 0

    // MARK: - トリプルバッファリング

    /// インフライトフレーム数を3に制限するセマフォ
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    /// 現在のフレームのトリプルバッファリングリソース用バッファインデックス (0-2)
    public private(set) var frameBufferIndex: Int = 0

    /// 次に使用するバッファインデックス
    private var nextBufferIndex: Int = 0

    // MARK: - コンピュート/レンダー同期

    /// コンピュート→レンダー明示的同期用の MTLEvent
    private var computeEvent: MTLEvent?

    /// 現在のイベントカウンター値
    private var computeEventValue: UInt64 = 0

    /// 現在のフレームでコンピュートワークがエンコードされたかどうか
    var didEncodeComputeWork: Bool = false

    // MARK: - ポストプロセス

    /// ポストプロセスエフェクトが利用可能かどうかを示す
    public private(set) var isPostProcessAvailable: Bool = false

    /// ポストプロセスエフェクトパイプライン
    public private(set) var postProcessPipeline: PostProcessPipeline?

    /// ポストプロセス後の最終出力テクスチャ。`blitToScreen` で使用
    private var lastOutputTexture: MTLTexture?

    /// GPU 画像フィルターエンジン。初回アクセス時に遅延作成されます。
    public private(set) lazy var imageFilterGPU: ImageFilterGPU = {
        ImageFilterGPU(device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary)
    }()

    // MARK: - レンダーグラフ

    /// 設定時に最終テクスチャとなるレンダーグラフ
    public var renderGraph: (any RenderGraphExecutable)?

    // MARK: - FBO フィードバック

    /// 前フレームのカラーテクスチャへのアクセスを有効にするフレームバッファオブジェクトフィードバック
    public var feedbackEnabled: Bool = false

    /// 前フレームのカラーテクスチャ。``feedbackEnabled`` が `true` の場合のみ利用可能
    public private(set) var previousFrameTexture: MTLTexture?

    // MARK: - スクリーンショット

    private var pendingSavePath: String?
    private var stagingTexture: MTLTexture?

    // MARK: - GPU 時間

    /// 最後に完了したフレームの GPU 開始タイムスタンプ（秒）
    public private(set) var lastGPUStartTime: Double = 0

    /// 最後に完了したフレームの GPU 終了タイムスタンプ（秒）
    public private(set) var lastGPUEndTime: Double = 0

    // MARK: - フレームエクスポート

    /// 個別フレームを画像ファイルとしてキャプチャするフレームエクスポーター
    public let frameExporter: FrameExporter = FrameExporter()
    private var exportStagingTexture: MTLTexture?

    // MARK: - 動画エクスポート

    /// フレームを動画ファイルに録画する動画エクスポーター
    public let videoExporter: VideoExporter = VideoExporter()
    private var videoStagingTexture: MTLTexture?

    // MARK: - プラグイン

    /// ライフサイクルコールバックを受け取る登録済みプラグイン
    private var plugins: [MetaphorPlugin] = []

    // MARK: - 初期化

    /// 指定されたデバイスとオフスクリーンテクスチャサイズで新しいレンダラーを作成します。
    ///
    /// - Parameters:
    ///   - device: 使用する Metal デバイス。`nil` の場合はシステムデフォルトを使用
    ///   - width: オフスクリーンレンダーテクスチャの幅（ピクセル）
    ///   - height: オフスクリーンレンダーテクスチャの高さ（ピクセル）
    ///   - clearColor: オフスクリーンレンダーパスのクリアカラー
    /// - Throws: デバイスまたはコマンドキューの作成に失敗した場合 ``MetaphorError``
    public init(
        device: MTLDevice? = nil,
        width: Int = 1920,
        height: Int = 1080,
        clearColor: MTLClearColor = .black
    ) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureManager = try TextureManager(
            device: device,
            width: width,
            height: height,
            clearColor: clearColor
        )
        self.startTime = CACurrentMediaTime()
        self.shaderLibrary = try ShaderLibrary(device: device)
        self.depthStencilCache = DepthStencilCache(device: device)
        self.input = InputManager()

        super.init()

        self.computeEvent = device.makeEvent()

        try buildBlitPipeline()

        do {
            self.postProcessPipeline = try PostProcessPipeline(
                device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
            )
            self.isPostProcessAvailable = true
        } catch {
            metaphorWarning("PostProcessPipeline unavailable: \(error). Post-processing effects will be disabled.")
        }
    }

    /// 他のレンダラーと Metal リソースを共有するレンダラーを作成します。
    ///
    /// 複数のレンダラーが同じデバイス、コマンドキュー、シェーダーライブラリ、
    /// デプスステンシルキャッシュを共有するマルチウィンドウ構成で使用します。
    ///
    /// - Parameters:
    ///   - sharedResources: 再利用する共有 Metal リソース
    ///   - width: オフスクリーンレンダーテクスチャの幅（ピクセル）
    ///   - height: オフスクリーンレンダーテクスチャの高さ（ピクセル）
    ///   - clearColor: オフスクリーンレンダーパスのクリアカラー
    /// - Throws: テクスチャまたはパイプライン作成に失敗した場合 ``MetaphorError``
    public init(
        sharedResources: SharedMetalResources,
        width: Int = 1920,
        height: Int = 1080,
        clearColor: MTLClearColor = .black
    ) throws {
        self.device = sharedResources.device
        self.commandQueue = sharedResources.commandQueue
        self.shaderLibrary = sharedResources.shaderLibrary
        self.depthStencilCache = sharedResources.depthStencilCache
        self.sharedResources = sharedResources
        self.textureManager = try TextureManager(
            device: sharedResources.device,
            width: width,
            height: height,
            clearColor: clearColor
        )
        self.startTime = CACurrentMediaTime()
        self.input = InputManager()

        super.init()

        self.computeEvent = device.makeEvent()

        try buildBlitPipeline()

        do {
            self.postProcessPipeline = try PostProcessPipeline(
                device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
            )
            self.isPostProcessAvailable = true
        } catch {
            metaphorWarning("PostProcessPipeline unavailable: \(error). Post-processing effects will be disabled.")
        }
    }

    // MARK: - Syphon

    /// 指定した名前でアプリケーション間テクスチャ共有用の Syphon サーバーを開始します。
    ///
    /// - Parameter name: Syphon サーバーとして公開する名前
    public func startSyphonServer(name: String) {
        syphonOutput = SyphonOutput(device: device, name: name)
    }

    /// Syphon サーバーを停止し、リソースを解放します。
    public func stopSyphonServer() {
        syphonOutput?.stop()
        syphonOutput = nil
    }

    // MARK: - プラグイン管理

    /// プラグインをこのレンダラーとスケッチ参照に登録します。
    ///
    /// プラグインの ``MetaphorPlugin/onAttach(sketch:)`` メソッドが即座に呼ばれ、
    /// プラグインにフルスケッチ (レンダラー、入力、キャンバス等) へのアクセスを提供します。
    /// - Parameters:
    ///   - plugin: 登録するプラグイン
    ///   - sketch: このプラグインが接続されるスケッチ
    public func addPlugin(_ plugin: MetaphorPlugin, sketch: any Sketch) {
        plugins.append(plugin)
        plugin.onAttach(sketch: sketch)
        plugin.onAttach(renderer: self)
    }

    /// プラグインをこのレンダラーに登録します (レガシー)。
    ///
    /// 新しいコードでは ``addPlugin(_:sketch:)`` を推奨します。このメソッドは
    /// ``MetaphorPlugin/onAttach(renderer:)`` のみを呼びます。
    /// - Parameter plugin: 登録するプラグイン
    public func addPlugin(_ plugin: MetaphorPlugin) {
        plugins.append(plugin)
        plugin.onAttach(renderer: self)
    }

    /// 識別子でプラグインを削除します。
    ///
    /// 削除前にプラグインの ``MetaphorPlugin/onDetach()`` メソッドが呼ばれます。
    /// - Parameter id: 削除するプラグインの ``MetaphorPlugin/pluginID``
    public func removePlugin(id: String) {
        if let idx = plugins.firstIndex(where: { $0.pluginID == id }) {
            plugins[idx].onDetach()
            plugins.remove(at: idx)
        }
    }

    /// 指定された識別子の登録済みプラグインがあれば返します。
    /// - Parameter id: 検索する ``MetaphorPlugin/pluginID``
    /// - Returns: 一致するプラグイン。見つからない場合は `nil`
    public func plugin(id: String) -> MetaphorPlugin? {
        plugins.first(where: { $0.pluginID == id })
    }

    // MARK: - プラグイン入力転送

    /// 全登録済みプラグインにマウスイベントを転送します。
    internal func notifyPluginsMouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {
        for plugin in plugins {
            plugin.mouseEvent(x: x, y: y, button: button, type: type)
        }
    }

    /// 全登録済みプラグインにキーボードイベントを転送します。
    internal func notifyPluginsKeyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {
        for plugin in plugins {
            plugin.keyEvent(key: key, keyCode: keyCode, type: type)
        }
    }

    // MARK: - キャンバスリサイズ

    /// 全レンダーターゲットテクスチャを再作成してオフスクリーンキャンバスをリサイズします。
    ///
    /// - Parameters:
    ///   - width: 新しい幅（ピクセル）
    ///   - height: 新しい高さ（ピクセル）
    public func resizeCanvas(width: Int, height: Int) {
        // GPU が古いテクスチャを使用していないことを保証するため、全インフライトフレームをドレイン。
        // セマフォは値3（トリプルバッファリング）を持ち、全スロットを取得します。
        var acquired = 0
        for _ in 0..<3 {
            let result = inflightSemaphore.wait(timeout: .now() + .seconds(5))
            if result == .timedOut {
                metaphorWarning("Timed out waiting for in-flight frame during resize")
                break
            }
            acquired += 1
        }
        defer {
            for _ in 0..<acquired {
                inflightSemaphore.signal()
            }
        }

        let currentClearColor = textureManager.renderPassDescriptor.colorAttachments[0].clearColor
        do {
            textureManager = try TextureManager(
                device: device,
                width: width,
                height: height
            )
            textureManager.setClearColor(currentClearColor)
        } catch {
            print("[metaphor] Failed to resize canvas: \(error)")
            return
        }
        stagingTexture = nil
        exportStagingTexture = nil
        videoStagingTexture = nil
        postProcessPipeline?.invalidateTextures()

        for plugin in plugins {
            plugin.onResize(width: width, height: height)
        }
    }

    // MARK: - ポストプロセス API

    /// パイプラインにポストプロセスエフェクトを追加します。
    ///
    /// - Parameter effect: 追加するポストプロセスエフェクト
    public func addPostEffect(_ effect: any PostEffect) {
        postProcessPipeline?.add(effect)
    }

    /// 指定されたインデックスのポストプロセスエフェクトを削除します。
    ///
    /// - Parameter index: 削除するエフェクトのゼロベースインデックス
    public func removePostEffect(at index: Int) {
        postProcessPipeline?.remove(at: index)
    }

    /// パイプラインから全ポストプロセスエフェクトを削除します。
    public func clearPostEffects() {
        postProcessPipeline?.removeAll()
    }

    /// 全ポストプロセスエフェクトを指定された配列で置き換えます。
    ///
    /// - Parameter effects: 新しいポストプロセスエフェクトのセット
    public func setPostEffects(_ effects: [any PostEffect]) {
        postProcessPipeline?.set(effects)
    }

    // MARK: - クリアカラー

    /// オフスクリーンレンダーパスのクリアカラーを変更します。
    ///
    /// - Parameters:
    ///   - r: 赤コンポーネント (0.0〜1.0)
    ///   - g: 緑コンポーネント (0.0〜1.0)
    ///   - b: 青コンポーネント (0.0〜1.0)
    ///   - a: アルファコンポーネント (0.0〜1.0)
    public func setClearColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
        textureManager.setClearColor(MTLClearColor(red: r, green: g, blue: b, alpha: a))
    }

    // MARK: - レンダリング

    /// 現在の経過時間（秒）を返します。
    ///
    /// オフラインレンダリングモードでは、実時間の代わりにフレームインデックスと
    /// フレームレートから時間が導出されます。
    public var elapsedTime: Double {
        if isOfflineRendering {
            return Double(offlineFrameIndex) / offlineFrameRate
        }
        return CACurrentMediaTime() - startTime
    }

    /// オフラインレンダリングモードでの1フレームあたりの固定デルタ時間を返します。
    public var offlineDeltaTime: Double {
        1.0 / offlineFrameRate
    }

    /// このレンダラーで使用する MTKView を構成します。
    ///
    /// - Parameter view: レンダラーのデバイスとピクセルフォーマットで設定する MTKView
    public func configure(view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self

        if let mtkView = view as? MetaphorMTKView {
            mtkView.rendererRef = self
        }
    }

    // MARK: - スクリーンショット

    /// 次のフレーム終了時にスクリーンショットの保存をスケジュールします。
    ///
    /// - Parameter path: PNG 画像の書き込み先ファイルパス
    public func saveScreenshot(to path: String) {
        pendingSavePath = path
    }

    // MARK: - 座標変換

    /// ビュー座標からオフスクリーンテクスチャ座標に変換します。
    ///
    /// - Parameters:
    ///   - viewPoint: ビュー座標系のポイント（macOS では左下原点）
    ///   - viewSize: ビューのサイズ（ポイント単位）
    ///   - drawableSize: ドローアブルのサイズ（ピクセル単位）
    /// - Returns: オフスクリーンテクスチャのピクセル空間での `(x, y)` 座標のタプル
    public func viewToTextureCoordinates(
        viewPoint: CGPoint,
        viewSize: CGSize,
        drawableSize: CGSize
    ) -> (Float, Float) {
        let viewWidth = Float(viewSize.width)
        let viewHeight = Float(viewSize.height)

        // NSView 座標（左下原点）→ ドローアブル座標（左上原点）
        let scaleX = Float(drawableSize.width) / viewWidth
        let scaleY = Float(drawableSize.height) / viewHeight
        let drawX = Float(viewPoint.x) * scaleX
        let drawY = (viewHeight - Float(viewPoint.y)) * scaleY

        // ビューポート → テクスチャ座標
        let viewport = calculateViewport(
            drawableSize: drawableSize,
            targetAspect: textureManager.aspectRatio
        )

        let texX = (drawX - Float(viewport.originX)) / Float(viewport.width) * Float(textureManager.width)
        let texY = (drawY - Float(viewport.originY)) / Float(viewport.height) * Float(textureManager.height)

        return (texX, texY)
    }

    // MARK: - Private

    /// FBO フィードバック用に現在のフレームのカラーテクスチャをコピーします。
    private func capturePreviousFrame(commandBuffer: MTLCommandBuffer) {
        let src = textureManager.colorTexture
        let w = textureManager.width
        let h = textureManager.height

        // テクスチャが存在しないかサイズが変わった場合は再作成
        if let existing = previousFrameTexture, existing.width == w, existing.height == h {
            // 既存テクスチャを再利用
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .renderTarget]
            desc.storageMode = .private
            previousFrameTexture = device.makeTexture(descriptor: desc)
            previousFrameTexture?.label = "metaphor.previousFrame"
        }

        guard let dst = previousFrameTexture,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(
            from: src,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: dst,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
    }

    private func buildBlitPipeline() throws {
        guard let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw MetaphorError.shaderNotFound("blitVertex")
        }
        guard let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitFragment,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw MetaphorError.shaderNotFound("blitFragment")
        }

        blitPipelineState = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .sampleCount(1)
            .build()
    }

    /// 指定されたドローアブルサイズ内にアスペクト比を保持するビューポートを計算します。
    private func calculateViewport(drawableSize: CGSize, targetAspect: Float) -> MTLViewport {
        let drawableWidth = Float(drawableSize.width)
        let drawableHeight = Float(drawableSize.height)
        let drawableAspect = drawableWidth / drawableHeight

        let viewportWidth: Float
        let viewportHeight: Float
        let viewportX: Float
        let viewportY: Float

        if drawableAspect > targetAspect {
            // ピラーボックス（左右に黒帯）
            viewportHeight = drawableHeight
            viewportWidth = drawableHeight * targetAspect
            viewportX = (drawableWidth - viewportWidth) / 2
            viewportY = 0
        } else {
            // レターボックス（上下に黒帯）
            viewportWidth = drawableWidth
            viewportHeight = drawableWidth / targetAspect
            viewportX = 0
            viewportY = (drawableHeight - viewportHeight) / 2
        }

        return MTLViewport(
            originX: Double(viewportX),
            originY: Double(viewportY),
            width: Double(viewportWidth),
            height: Double(viewportHeight),
            znear: 0,
            zfar: 1
        )
    }

    /// GPU→CPU リードバック用のマネージドステージングテクスチャを返すか作成します。
    private func createOrReuseStagingTexture(cache: inout MTLTexture?) -> MTLTexture? {
        if let existing = cache,
           existing.width == textureManager.width,
           existing.height == textureManager.height {
            return existing
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: textureManager.width,
            height: textureManager.height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else {
            return nil
        }
        cache = tex
        return tex
    }

    /// スクリーンショットキャプチャ用のステージングテクスチャを返すか作成します。
    private func getOrCreateStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &stagingTexture)
    }

    /// フレームエクスポート用のステージングテクスチャを返すか作成します。
    private func getOrCreateExportStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &exportStagingTexture)
    }

    /// 動画エクスポート用のステージングテクスチャを返すか作成します。
    private func getOrCreateVideoStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &videoStagingTexture)
    }

    /// テクスチャの内容を指定パスの PNG ファイルに書き出します。
    ///
    /// このメソッドは `nonisolated static` であり、完了ハンドラーから安全に呼び出せます。
    ///
    /// - Parameters:
    ///   - texture: ピクセルデータを含むマネージドステージングテクスチャ
    ///   - width: 画像の幅（ピクセル）
    ///   - height: 画像の高さ（ピクセル）
    ///   - path: PNG を保存するファイルパス
    nonisolated static func writePNG(
        texture: MTLTexture, width: Int, height: Int, path: String
    ) {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // BGRA -> RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = ctx.makeImage() else {
            print("[metaphor] Failed to create CGImage for screenshot")
            return
        }

        // ディレクトリが存在しない場合は作成
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            print("[metaphor] Failed to create image destination: \(path)")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    /// オフスクリーンテクスチャを指定ビューポートで画面ドローアブルにブリットします。
    private func blitToScreen(encoder: MTLRenderCommandEncoder, viewport: MTLViewport) {
        guard let pipeline = blitPipelineState else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(viewport)
        let tex = lastOutputTexture ?? textureManager.colorTexture
        encoder.setFragmentTexture(tex, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - レンダーループ

    /// 画面プレゼンテーションなしでオフスクリーンレンダリングフレームを完全に実行します。
    ///
    /// コンピュート、オフスクリーン描画、スクリーンショット、ポストプロセス、
    /// フレーム/動画エクスポート、Syphon 出力の順でフルパイプラインを実行します。
    public func renderFrame() {
        let semaphoreResult = inflightSemaphore.wait(timeout: .now() + .seconds(3))
        if semaphoreResult == .timedOut {
            metaphorWarning("GPU frame timed out after 3s. Skipping frame.")
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        // 現在のバッファインデックスを設定し、次へ進める
        frameBufferIndex = nextBufferIndex
        nextBufferIndex = (nextBufferIndex + 1) % 3

        commandBuffer.addCompletedHandler { [weak self] cb in
            self?.inflightSemaphore.signal()
            let gpuStart = cb.gpuStartTime
            let gpuEnd = cb.gpuEndTime
            DispatchQueue.main.async {
                self?.lastGPUStartTime = gpuStart
                self?.lastGPUEndTime = gpuEnd
            }
        }

        input.updateFrame()
        let time = elapsedTime

        // プラグイン: レンダー前
        for plugin in plugins {
            plugin.pre(commandBuffer: commandBuffer, time: time)
            plugin.onBeforeRender(commandBuffer: commandBuffer, time: time)
        }

        // FBO フィードバック: 前フレームのカラーテクスチャをコピー
        if feedbackEnabled {
            capturePreviousFrame(commandBuffer: commandBuffer)
        }

        // コンピュートフェーズ
        didEncodeComputeWork = false
        onCompute?(commandBuffer, time)

        // コンピュートワークが実際にエンコードされた場合のみバリアを発行
        if didEncodeComputeWork, let event = computeEvent {
            computeEventValue += 1
            commandBuffer.encodeSignalEvent(event, value: computeEventValue)
            commandBuffer.encodeWaitForEvent(event, value: computeEventValue)
        }

        // オフスクリーンテクスチャに描画
        if let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) {
            onDraw?(encoder, time)
            encoder.endEncoding()
        }

        // シャドウパス（メイン描画後にシャドウマップを更新、次フレームで使用）
        onAfterDraw?(commandBuffer)

        // レンダーグラフを実行（構成時はグラフ出力をベーステクスチャとして使用）
        let baseTexture: MTLTexture
        if let graph = renderGraph,
           let graphOutput = graph.execute(
               commandBuffer: commandBuffer, time: time, renderer: self
           ) {
            baseTexture = graphOutput
        } else {
            baseTexture = textureManager.colorTexture
        }

        // ポストプロセスエフェクトを適用
        let outputTexture: MTLTexture
        if let pipeline = postProcessPipeline, !pipeline.effects.isEmpty {
            outputTexture = pipeline.apply(
                source: baseTexture,
                commandBuffer: commandBuffer
            )
        } else {
            outputTexture = baseTexture
        }
        lastOutputTexture = outputTexture

        // スクリーンショットを保存（失敗時はスキップ、フレーム処理は継続）
        if let savePath = pendingSavePath {
            pendingSavePath = nil
            if let staging = getOrCreateStagingTexture() {
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(
                        from: outputTexture,
                        sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(
                            width: textureManager.width,
                            height: textureManager.height,
                            depth: 1
                        ),
                        to: staging,
                        destinationSlice: 0, destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                    )
                    blitEncoder.endEncoding()
                }

                let width = textureManager.width
                let height = textureManager.height
                let path = savePath
                commandBuffer.addCompletedHandler { _ in
                    MetaphorRenderer.writePNG(
                        texture: staging, width: width, height: height, path: path
                    )
                }
            }
        }

        // フレームエクスポート（録画中は毎フレームキャプチャ）
        if frameExporter.isRecording, let exportStaging = getOrCreateExportStagingTexture() {
            frameExporter.captureFrame(
                sourceTexture: outputTexture,
                stagingTexture: exportStaging,
                commandBuffer: commandBuffer,
                width: textureManager.width,
                height: textureManager.height
            )
        }

        // 動画エクスポート（録画中は毎フレームキャプチャ）
        if videoExporter.isRecording, let videoStaging = getOrCreateVideoStagingTexture() {
            videoExporter.captureFrame(
                sourceTexture: outputTexture,
                stagingTexture: videoStaging,
                commandBuffer: commandBuffer,
                width: textureManager.width,
                height: textureManager.height
            )
        }

        // プラグイン: レンダー後（出力プラグインに最終テクスチャを提供）
        for plugin in plugins {
            plugin.post(texture: outputTexture, commandBuffer: commandBuffer)
            plugin.onAfterRender(texture: outputTexture, commandBuffer: commandBuffer)
        }

        // Syphon へ配信（レガシー、SyphonPlugin に置換予定）
        syphonOutput?.publish(
            texture: outputTexture,
            commandBuffer: commandBuffer,
            flipped: true
        )

        commandBuffer.commit()

        if isOfflineRendering {
            offlineFrameIndex += 1
        }
    }

    /// 決定論的タイミングでオフラインモードの単一フレームをレンダリングします。
    ///
    /// ``isOfflineRendering`` を自動的に `true` に設定し、``renderFrame()`` を呼び出して
    /// フレームインデックスを進めます。
    public func renderOfflineFrame() {
        isOfflineRendering = true
        renderFrame()
    }

    /// フレームインデックスをゼロに戻してオフラインレンダリングをリセットします。
    public func resetOfflineRendering() {
        offlineFrameIndex = 0
    }
}

// MARK: - MTKViewDelegate

extension MetaphorRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        // 外部レンダーループを使用していない場合、ここでフレームをレンダリング
        if !useExternalRenderLoop {
            renderFrame()
        }

        // ウィンドウがオクルージョン状態の場合、currentDrawable のブロックを防ぐためブリットをスキップ。
        // noLoop() スケッチがウィンドウのオクルージョン状態更新前にコンテンツを表示できるよう、
        // 最初のブリットは常に許可します。
        if hasBlittedOnce,
           let window = view.window,
           !window.occlusionState.contains(.visible) {
            return
        }

        // 画面にブリット（プレビュー表示）
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let viewport = calculateViewport(
            drawableSize: view.drawableSize,
            targetAspect: textureManager.aspectRatio
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            blitToScreen(encoder: encoder, viewport: viewport)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        hasBlittedOnce = true
    }
}
