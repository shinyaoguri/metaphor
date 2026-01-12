import Metal

/// Metalパイプライン状態のキャッシュ
/// 同じパイプラインを何度も生成することを避ける
public final class PipelineCache: @unchecked Sendable {
    private let device: MTLDevice
    private let library: MTLLibrary

    /// 2D形状描画用パイプライン（塗りつぶし）
    public let shapeFillPipeline: MTLRenderPipelineState

    /// 2D形状描画用パイプライン（線）
    public let shapeStrokePipeline: MTLRenderPipelineState

    /// 初期化
    /// - Parameters:
    ///   - device: Metalデバイス
    ///   - pixelFormat: 出力ピクセルフォーマット
    ///   - depthFormat: 深度フォーマット
    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float
    ) throws {
        self.device = device
        self.library = try compileShapeShaders(device: device)

        // 塗りつぶし用パイプライン
        self.shapeFillPipeline = try Self.createShapePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            depthFormat: depthFormat,
            blendEnabled: true
        )

        // 線描画用パイプライン（同じシェーダー、同じ設定）
        self.shapeStrokePipeline = try Self.createShapePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            depthFormat: depthFormat,
            blendEnabled: true
        )
    }

    /// 形状描画パイプラインを作成
    private static func createShapePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat,
        blendEnabled: Bool
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "shapeVertexShader") else {
            throw ShaderError.functionNotFound("shapeVertexShader")
        }
        guard let fragmentFunction = library.makeFunction(name: "shapeFragmentShader") else {
            throw ShaderError.functionNotFound("shapeFragmentShader")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.depthAttachmentPixelFormat = depthFormat

        // アルファブレンディング設定
        if blendEnabled {
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw ShaderError.pipelineCreationFailed(error.localizedDescription)
        }
    }
}
