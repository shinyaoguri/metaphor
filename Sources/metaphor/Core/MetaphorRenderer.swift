@preconcurrency import Metal
import MetalKit
import simd

/// metaphorのメインレンダラー
/// Metalレンダリングとオプションのランタイム操作を提供する
@MainActor
public final class MetaphorRenderer: NSObject {
    // MARK: - Public Properties

    /// MTLDevice
    public let device: MTLDevice

    /// コマンドキュー
    public let commandQueue: MTLCommandQueue

    /// オフスクリーンテクスチャマネージャ
    public private(set) var textureManager: TextureManager

    /// Syphon出力（オプション）
    public private(set) var syphonOutput: SyphonOutput?

    /// シェーダーライブラリ
    public let shaderLibrary: ShaderLibrary

    /// 深度ステンシルキャッシュ
    public let depthStencilCache: DepthStencilCache

    /// 入力マネージャ
    public let input: InputManager

    /// 描画コールバック
    /// - Parameters:
    ///   - encoder: レンダーコマンドエンコーダ
    ///   - time: 開始からの経過時間（秒）
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    /// コンピュートコールバック（描画前に呼ばれる）
    /// - Parameters:
    ///   - commandBuffer: MTLCommandBuffer（コンピュートエンコーダ作成用）
    ///   - time: 開始からの経過時間（秒）
    public var onCompute: ((MTLCommandBuffer, Double) -> Void)?

    /// 開始時刻
    private let startTime: CFAbsoluteTime

    // MARK: - Blit Pipeline

    private var blitPipelineState: MTLRenderPipelineState?

    /// 外部レンダーループ使用フラグ（trueの場合、draw(in:)はブリットのみ行う）
    public var useExternalRenderLoop: Bool = false

    // MARK: - Triple Buffering

    /// in-flight フレーム数を制御するセマフォ
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    /// 現在のフレームで使用するバッファインデックス (0-2)
    public private(set) var frameBufferIndex: Int = 0

    /// 次に使うバッファインデックス
    private var nextBufferIndex: Int = 0

    // MARK: - Post Processing

    /// ポストプロセスパイプライン
    public private(set) var postProcessPipeline: PostProcessPipeline?

    /// ポストプロセス後の最終出力テクスチャ（blitToScreenで使用）
    private var lastOutputTexture: MTLTexture?

    /// GPU画像フィルタエンジン
    public private(set) lazy var imageFilterGPU: ImageFilterGPU = {
        ImageFilterGPU(device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary)
    }()

    // MARK: - Screenshot

    private var pendingSavePath: String?
    private var stagingTexture: MTLTexture?

    // MARK: - Frame Export

    /// フレームエクスポーター
    public let frameExporter: FrameExporter = FrameExporter()
    private var exportStagingTexture: MTLTexture?

    // MARK: - Initialization

    /// 初期化
    /// - Parameters:
    ///   - device: MTLDevice（nilの場合はシステムデフォルト）
    ///   - width: オフスクリーンテクスチャの幅
    ///   - height: オフスクリーンテクスチャの高さ
    ///   - clearColor: クリアカラー
    public init?(
        device: MTLDevice? = nil,
        width: Int = 1920,
        height: Int = 1080,
        clearColor: MTLClearColor = .black
    ) {
        guard let device = device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureManager = TextureManager(
            device: device,
            width: width,
            height: height,
            clearColor: clearColor
        )
        self.startTime = CFAbsoluteTimeGetCurrent()

        do {
            self.shaderLibrary = try ShaderLibrary(device: device)
        } catch {
            print("Failed to initialize ShaderLibrary: \(error)")
            return nil
        }
        self.depthStencilCache = DepthStencilCache(device: device)
        self.input = InputManager()

        super.init()

        buildBlitPipeline()

        do {
            self.postProcessPipeline = try PostProcessPipeline(
                device: device, shaderLibrary: shaderLibrary
            )
        } catch {
            print("[metaphor] Failed to create PostProcessPipeline: \(error)")
        }
    }

    // MARK: - Syphon

    /// Syphonサーバーを開始
    /// - Parameter name: サーバー名
    public func startSyphonServer(name: String) {
        syphonOutput = SyphonOutput(device: device, name: name)
    }

    /// Syphonサーバーを停止
    public func stopSyphonServer() {
        syphonOutput?.stop()
        syphonOutput = nil
    }

    // MARK: - Canvas Resize

    /// キャンバスサイズを変更（テクスチャ再作成）
    public func resizeCanvas(width: Int, height: Int) {
        textureManager = TextureManager(
            device: device,
            width: width,
            height: height
        )
        stagingTexture = nil
        exportStagingTexture = nil
        postProcessPipeline?.invalidateTextures()
    }

    // MARK: - Post Process API

    /// ポストプロセスエフェクトを追加
    public func addPostEffect(_ effect: PostEffect) {
        postProcessPipeline?.add(effect)
    }

    /// ポストプロセスエフェクトを削除
    public func removePostEffect(at index: Int) {
        postProcessPipeline?.remove(at: index)
    }

    /// 全ポストプロセスエフェクトを削除
    public func clearPostEffects() {
        postProcessPipeline?.removeAll()
    }

    /// ポストプロセスエフェクトを一括設定
    public func setPostEffects(_ effects: [PostEffect]) {
        postProcessPipeline?.set(effects)
    }

    // MARK: - Rendering

    /// 現在の経過時間を取得
    public var elapsedTime: Double {
        CFAbsoluteTimeGetCurrent() - startTime
    }

    /// MTKViewをセットアップ
    /// - Parameter view: セットアップするMTKView
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

    // MARK: - Screenshot

    /// 次のフレームでスクリーンショットを保存
    public func saveScreenshot(to path: String) {
        pendingSavePath = path
    }

    // MARK: - Coordinate Conversion

    /// ビュー座標をテクスチャ座標に変換
    public func viewToTextureCoordinates(
        viewPoint: CGPoint,
        viewSize: CGSize,
        drawableSize: CGSize
    ) -> (Float, Float) {
        let viewWidth = Float(viewSize.width)
        let viewHeight = Float(viewSize.height)

        // NSView座標（左下原点）→ drawable座標（左上原点）
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

    private func buildBlitPipeline() {
        do {
            let vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.blitVertex,
                from: ShaderLibrary.BuiltinKey.blit
            )
            let fragmentFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.blitFragment,
                from: ShaderLibrary.BuiltinKey.blit
            )

            blitPipelineState = try PipelineFactory(device: device)
                .vertex(vertexFn)
                .fragment(fragmentFn)
                .noDepth()
                .build()
        } catch {
            print("Failed to create blit pipeline: \(error)")
        }
    }

    /// アスペクト比を維持したビューポートを計算
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

    /// ステージングテクスチャを取得または作成
    private func getOrCreateStagingTexture() -> MTLTexture {
        if let existing = stagingTexture,
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
        desc.storageMode = .managed
        let tex = device.makeTexture(descriptor: desc)!
        stagingTexture = tex
        return tex
    }

    /// フレームエクスポート用ステージングテクスチャを取得または作成
    private func getOrCreateExportStagingTexture() -> MTLTexture {
        if let existing = exportStagingTexture,
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
        desc.storageMode = .managed
        let tex = device.makeTexture(descriptor: desc)!
        exportStagingTexture = tex
        return tex
    }

    /// PNG書き出し（completionHandler内から呼ぶためnonisolated static）
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

        // BGRA → RGBA
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

    /// オフスクリーンテクスチャを画面にブリット
    private func blitToScreen(encoder: MTLRenderCommandEncoder, viewport: MTLViewport) {
        guard let pipeline = blitPipelineState else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(viewport)
        let tex = lastOutputTexture ?? textureManager.colorTexture
        encoder.setFragmentTexture(tex, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - Render Loop

    /// オフスクリーン描画 + Syphon送信（ウィンドウに依存しない）
    ///
    /// Compute → Offscreen Draw → Screenshot → Syphon の順に実行する。
    /// 画面へのブリットは含まない。
    public func renderFrame() {
        inflightSemaphore.wait()

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        // バッファインデックスを設定して進める
        frameBufferIndex = nextBufferIndex
        nextBufferIndex = (nextBufferIndex + 1) % 3

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        input.updateFrame()
        let time = elapsedTime

        // コンピュートフェーズ
        onCompute?(commandBuffer, time)

        // オフスクリーンテクスチャに描画
        if let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) {
            onDraw?(encoder, time)
            encoder.endEncoding()
        }

        // ポストプロセス適用
        let outputTexture: MTLTexture
        if let pipeline = postProcessPipeline, !pipeline.effects.isEmpty {
            outputTexture = pipeline.apply(
                source: textureManager.colorTexture,
                commandBuffer: commandBuffer
            )
        } else {
            outputTexture = textureManager.colorTexture
        }
        lastOutputTexture = outputTexture

        // スクリーンショット保存
        if let savePath = pendingSavePath {
            pendingSavePath = nil
            let staging = getOrCreateStagingTexture()
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
                blitEncoder.synchronize(resource: staging)
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

        // フレームエクスポート（録画中なら毎フレーム）
        if frameExporter.isRecording {
            let exportStaging = getOrCreateExportStagingTexture()
            frameExporter.captureFrame(
                sourceTexture: outputTexture,
                stagingTexture: exportStaging,
                commandBuffer: commandBuffer,
                width: textureManager.width,
                height: textureManager.height
            )
        }

        // Syphonに送信
        syphonOutput?.publish(
            texture: outputTexture,
            commandBuffer: commandBuffer,
            flipped: true
        )

        commandBuffer.commit()
    }
}

// MARK: - MTKViewDelegate

extension MetaphorRenderer: MTKViewDelegate {
    public nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            // 外部レンダーループでない場合は、ここでフレームを描画
            if !useExternalRenderLoop {
                renderFrame()
            }

            // ウィンドウが隠れている場合はブリットをスキップ
            // (currentDrawableがブロックしてレンダータイマーを止めるのを防ぐ)
            if let window = view.window,
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
        }
    }
}
