import Metal
import simd

/// シャドウ深度パス用のユニフォーム
struct ShadowUniforms {
    var modelMatrix: float4x4
    var lightSpaceMatrix: float4x4
}

/// シャドウマッピング用のフラグメントシェーダーに渡すユニフォーム
struct ShadowFragmentUniforms {
    var lightSpaceMatrix: float4x4
    var shadowBias: Float
    var shadowEnabled: Float  // 0 or 1
    var _pad: SIMD2<Float> = .zero
}

/// Canvas3D 用 DrawCall 記録
struct DrawCall3D {
    var mesh: Mesh
    var transform: float4x4
    var fillColor: SIMD4<Float>
    var material: Material3D
    var customMaterial: CustomMaterial?
    var texture: MTLTexture?
    var isTextured: Bool
    var hasFill: Bool
    var hasStroke: Bool
    var strokeColor: SIMD4<Float>
}

/// ディレクショナルライト用シャドウマップ
///
/// 深度テクスチャにライト視点のシーンを描画し、
/// メインパスでサンプリングしてソフトシャドウを生成する。
@MainActor
public final class ShadowMap {

    // MARK: - Properties

    /// シャドウ深度テクスチャ
    public let shadowTexture: MTLTexture

    /// シャドウマップ解像度
    public let resolution: Int

    /// シャドウバイアス（アクネ防止）
    public var shadowBias: Float = 0.005

    /// PCF サンプリング半径
    public var pcfRadius: Int = 2

    /// ライト空間行列
    public private(set) var lightSpaceMatrix: float4x4 = .identity

    private let device: MTLDevice
    private let renderPassDescriptor: MTLRenderPassDescriptor
    private let depthPipelineUntextured: MTLRenderPipelineState
    private let depthPipelineTextured: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState?

    // MARK: - Initialization

    init(device: MTLDevice, shaderLibrary: ShaderLibrary, resolution: Int = 2048) throws {
        self.device = device
        self.resolution = resolution

        // シャドウ深度テクスチャ作成
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: resolution,
            height: resolution,
            mipmapped: false
        )
        texDesc.storageMode = .private
        texDesc.usage = [.renderTarget, .shaderRead]

        guard let tex = device.makeTexture(descriptor: texDesc) else {
            throw MetaphorError.textureCreationFailed(width: resolution, height: resolution, format: "shadow_depth")
        }
        tex.label = "ShadowMap Depth"
        self.shadowTexture = tex

        // レンダーパスディスクリプタ（depth only、カラーアタッチメントなし）
        let rpd = MTLRenderPassDescriptor()
        rpd.depthAttachment.texture = shadowTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0
        self.renderPassDescriptor = rpd

        // シャドウ深度シェーダーコンパイル
        let shadowKey = "metaphor.shadowDepth"
        if !shaderLibrary.hasLibrary(for: shadowKey) {
            try shaderLibrary.register(source: ShadowShaders.depthSource, as: shadowKey)
        }
        guard let vertexFn = shaderLibrary.function(named: "metaphor_shadowDepthVertex", from: shadowKey) else {
            throw MetaphorError.shaderCompilationFailed(name: "metaphor_shadowDepthVertex", underlying: NSError(domain: "ShadowMap", code: -1))
        }

        // Untextured (positionNormalColor stride=40) 用パイプライン
        let untexDesc = MTLRenderPipelineDescriptor()
        untexDesc.vertexFunction = vertexFn
        untexDesc.fragmentFunction = nil
        untexDesc.depthAttachmentPixelFormat = .depth32Float
        untexDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride)
        untexDesc.rasterSampleCount = 1
        self.depthPipelineUntextured = try device.makeRenderPipelineState(descriptor: untexDesc)

        // Textured (positionNormalUV stride=48) 用パイプライン
        let texPipeDesc = MTLRenderPipelineDescriptor()
        texPipeDesc.vertexFunction = vertexFn
        texPipeDesc.fragmentFunction = nil
        texPipeDesc.depthAttachmentPixelFormat = .depth32Float
        texPipeDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 3)
        texPipeDesc.rasterSampleCount = 1
        self.depthPipelineTextured = try device.makeRenderPipelineState(descriptor: texPipeDesc)

        // 深度ステンシル
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: dsDesc)
    }

    // MARK: - Light Space Matrix

    /// ディレクショナルライトからライト空間行列を計算
    func updateLightSpaceMatrix(lightDirection: SIMD3<Float>, sceneCenter: SIMD3<Float> = .zero, sceneRadius: Float = 500) {
        let dir = normalize(lightDirection)
        let lightPos = sceneCenter - dir * sceneRadius

        // up ベクトルがライト方向と平行にならないよう調整
        var up = SIMD3<Float>(0, 1, 0)
        if abs(dot(dir, up)) > 0.99 {
            up = SIMD3<Float>(1, 0, 0)
        }

        let view = float4x4(lookAt: lightPos, center: sceneCenter, up: up)
        let projection = float4x4(
            orthographic: -sceneRadius, right: sceneRadius,
            bottom: -sceneRadius, top: sceneRadius,
            near: 0.1, far: sceneRadius * 2
        )
        lightSpaceMatrix = projection * view
    }

    // MARK: - Shadow Pass Rendering

    /// 記録された DrawCall をライト視点で深度テクスチャに描画
    func render(drawCalls: [DrawCall3D], commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Shadow Depth Pass"

        if let ds = depthStencilState {
            encoder.setDepthStencilState(ds)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.front)  // フロントフェイスカリング（Peter Panning 軽減）
        encoder.setDepthBias(0.01, slopeScale: 1.5, clamp: 0.02)

        for call in drawCalls {
            guard call.hasFill else { continue }

            let pipeline = call.isTextured ? depthPipelineTextured : depthPipelineUntextured
            encoder.setRenderPipelineState(pipeline)

            if call.isTextured, let uvBuffer = call.mesh.uvVertexBuffer {
                encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
            } else {
                encoder.setVertexBuffer(call.mesh.vertexBuffer, offset: 0, index: 0)
            }

            var uniforms = ShadowUniforms(
                modelMatrix: call.transform,
                lightSpaceMatrix: lightSpaceMatrix
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShadowUniforms>.stride, index: 1)

            if let ib = call.mesh.indexBuffer, call.mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: call.mesh.indexCount,
                    indexType: call.mesh.indexType, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                let vertexCount = call.isTextured ? call.mesh.uvVertexCount : call.mesh.vertexCount
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        encoder.endEncoding()
    }

    // MARK: - Private Helpers

    private static func makeShadowVertexDescriptor(stride: Int) -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0
        desc.layouts[0].stride = stride
        return desc
    }
}
