import Metal
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

    /// 描画コールバック
    /// - Parameters:
    ///   - encoder: レンダーコマンドエンコーダ
    ///   - time: 開始からの経過時間（秒）
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    /// 開始時刻
    private let startTime: CFAbsoluteTime

    // MARK: - Blit Pipeline

    private var blitPipelineState: MTLRenderPipelineState?

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

        super.init()

        buildBlitPipeline()
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
    }

    // MARK: - Private

    private func buildBlitPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct BlitVertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex BlitVertexOut metaphor_blitVertex(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1, -1),
                float2( 1, -1),
                float2(-1,  1),
                float2( 1,  1)
            };

            float2 texCoords[4] = {
                float2(0, 1),
                float2(1, 1),
                float2(0, 0),
                float2(1, 0)
            };

            BlitVertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 metaphor_blitFragment(
            BlitVertexOut in [[stage_in]],
            texture2d<float> texture [[texture(0)]]
        ) {
            constexpr sampler s(filter::linear);
            return texture.sample(s, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "metaphor_blitVertex")
            let fragmentFunction = library.makeFunction(name: "metaphor_blitFragment")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            blitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
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

    /// オフスクリーンテクスチャを画面にブリット
    private func blitToScreen(encoder: MTLRenderCommandEncoder, viewport: MTLViewport) {
        guard let pipeline = blitPipelineState else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(viewport)
        encoder.setFragmentTexture(textureManager.colorTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

// MARK: - MTKViewDelegate

extension MetaphorRenderer: MTKViewDelegate {
    public nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let time = elapsedTime

            // 1. オフスクリーンテクスチャに描画
            if let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: textureManager.renderPassDescriptor
            ) {
                onDraw?(encoder, time)
                encoder.endEncoding()
            }

            // 2. Syphonに送信
            syphonOutput?.publish(
                texture: textureManager.colorTexture,
                commandBuffer: commandBuffer
            )

            // 3. 画面にブリット
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                commandBuffer.commit()
                return
            }

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
