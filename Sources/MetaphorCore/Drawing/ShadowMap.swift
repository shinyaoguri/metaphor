import Metal
import simd

/// シャドウデプスパスのユニフォームを保持します。
struct ShadowUniforms {
    var modelMatrix: float4x4
    var lightSpaceMatrix: float4x4
}

/// シャドウマッピング用にフラグメントシェーダーに渡されるユニフォームを保持します。
struct ShadowFragmentUniforms {
    var lightSpaceMatrix: float4x4
    var shadowBias: Float
    var shadowEnabled: Float  // 0 or 1
    var _pad: SIMD2<Float> = .zero
}

/// Canvas3D シャドウレンダリング用の描画呼び出しを記録します。
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

/// ディレクショナルライトのシャドウマップを管理します。
///
/// ライトの視点からシーンをデプステクスチャにレンダリングし、
/// メインパスでサンプリングしてソフトシャドウを生成します。
@MainActor
public final class ShadowMap {

    // MARK: - Properties

    /// シャドウデプステクスチャ。
    public let shadowTexture: MTLTexture

    /// シャドウマップの解像度（ピクセル単位）。
    public let resolution: Int

    /// シャドウアクネ防止用のバイアス。
    public var shadowBias: Float = 0.005

    /// PCF サンプリング半径。
    public var pcfRadius: Int = 2

    /// ライト空間の変換行列。
    public private(set) var lightSpaceMatrix: float4x4 = .identity

    private let device: MTLDevice
    private let renderPassDescriptor: MTLRenderPassDescriptor
    private let depthPipelineUntextured: MTLRenderPipelineState
    private let depthPipelineTextured: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState?

    // MARK: - Initialization

    /// - Parameters:
    ///   - device: Metal デバイス。
    ///   - shaderLibrary: シャドウデプスシェーダーのコンパイル用シェーダーライブラリ。
    ///   - resolution: シャドウマップの解像度（ピクセル単位）。
    /// - Throws: テクスチャ作成またはシェーダーコンパイルに失敗した場合に `MetaphorError` をスロー。
    init(device: MTLDevice, shaderLibrary: ShaderLibrary, resolution: Int = 2048) throws {
        self.device = device
        self.resolution = resolution

        // シャドウデプステクスチャを作成
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

        // レンダーパスデスクリプタ（デプスのみ、カラーアタッチメントなし）
        let rpd = MTLRenderPassDescriptor()
        rpd.depthAttachment.texture = shadowTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0
        self.renderPassDescriptor = rpd

        // シャドウデプスシェーダーをコンパイル
        let shadowKey = "metaphor.shadowDepth"
        if !shaderLibrary.hasLibrary(for: shadowKey) {
            guard let shadowSource = ShaderLibrary.loadShaderSource("shadowDepth") else {
                throw MetaphorError.shaderNotFound("shadowDepth")
            }
            try shaderLibrary.register(source: shadowSource, as: shadowKey)
        }
        guard let vertexFn = shaderLibrary.function(named: "metaphor_shadowDepthVertex", from: shadowKey) else {
            throw MetaphorError.shaderNotFound("metaphor_shadowDepthVertex")
        }

        // テクスチャなしジオメトリ用パイプライン（positionNormalColor stride=40）
        let untexDesc = MTLRenderPipelineDescriptor()
        untexDesc.vertexFunction = vertexFn
        untexDesc.fragmentFunction = nil
        untexDesc.depthAttachmentPixelFormat = .depth32Float
        untexDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride)
        untexDesc.rasterSampleCount = 1
        self.depthPipelineUntextured = try device.makeRenderPipelineState(descriptor: untexDesc)

        // テクスチャ付きジオメトリ用パイプライン（positionNormalUV stride=48）
        let texPipeDesc = MTLRenderPipelineDescriptor()
        texPipeDesc.vertexFunction = vertexFn
        texPipeDesc.fragmentFunction = nil
        texPipeDesc.depthAttachmentPixelFormat = .depth32Float
        texPipeDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 3)
        texPipeDesc.rasterSampleCount = 1
        self.depthPipelineTextured = try device.makeRenderPipelineState(descriptor: texPipeDesc)

        // デプスステンシルステート
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: dsDesc)
    }

    // MARK: - Light Space Matrix

    /// ディレクショナルライトからライト空間行列を計算します。
    ///
    /// - Parameters:
    ///   - lightDirection: ライトの方向ベクトル。
    ///   - sceneCenter: シャドウを適用するシーンの中心。
    ///   - sceneRadius: シーンのバウンディング球の半径。
    func updateLightSpaceMatrix(lightDirection: SIMD3<Float>, sceneCenter: SIMD3<Float> = .zero, sceneRadius: Float = 500) {
        let dir = normalize(lightDirection)
        let lightPos = sceneCenter - dir * sceneRadius

        // ライト方向と平行にならないよう上方向ベクトルを調整
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

    /// 記録された描画呼び出しをライトの視点からデプステクスチャにレンダリングします。
    ///
    /// - Parameters:
    ///   - drawCalls: 記録された3D描画呼び出しの配列。
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    func render(drawCalls: [DrawCall3D], commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Shadow Depth Pass"

        if let ds = depthStencilState {
            encoder.setDepthStencilState(ds)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.front)  // Front-face culling (reduces Peter Panning)
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
