import Metal
import simd

/// Hold uniforms for the shadow depth pass.
struct ShadowUniforms {
    var modelMatrix: float4x4
    var lightSpaceMatrix: float4x4
}

/// Hold uniforms passed to the fragment shader for shadow mapping.
struct ShadowFragmentUniforms {
    var lightSpaceMatrix: float4x4
    var shadowBias: Float
    var shadowEnabled: Float  // 0 or 1
    var _pad: SIMD2<Float> = .zero
}

/// Record a draw call for Canvas3D shadow rendering.
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

/// Manage a directional light shadow map.
///
/// Render the scene from the light's perspective into a depth texture,
/// then sample it during the main pass to produce soft shadows.
@MainActor
public final class ShadowMap {

    // MARK: - Properties

    /// Shadow depth texture.
    public let shadowTexture: MTLTexture

    /// Shadow map resolution in pixels.
    public let resolution: Int

    /// Shadow bias for acne prevention.
    public var shadowBias: Float = 0.005

    /// PCF sampling radius.
    public var pcfRadius: Int = 2

    /// Light-space transformation matrix.
    public private(set) var lightSpaceMatrix: float4x4 = .identity

    private let device: MTLDevice
    private let renderPassDescriptor: MTLRenderPassDescriptor
    private let depthPipelineUntextured: MTLRenderPipelineState
    private let depthPipelineTextured: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState?

    // MARK: - Initialization

    /// - Parameters:
    ///   - device: The Metal device.
    ///   - shaderLibrary: The shader library for compiling shadow depth shaders.
    ///   - resolution: The shadow map resolution in pixels.
    /// - Throws: `MetaphorError` if texture creation or shader compilation fails.
    init(device: MTLDevice, shaderLibrary: ShaderLibrary, resolution: Int = 2048) throws {
        self.device = device
        self.resolution = resolution

        // Create shadow depth texture
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

        // Render pass descriptor (depth only, no color attachment)
        let rpd = MTLRenderPassDescriptor()
        rpd.depthAttachment.texture = shadowTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0
        self.renderPassDescriptor = rpd

        // Compile shadow depth shaders
        let shadowKey = "metaphor.shadowDepth"
        if !shaderLibrary.hasLibrary(for: shadowKey) {
            try shaderLibrary.register(source: ShadowShaders.depthSource, as: shadowKey)
        }
        guard let vertexFn = shaderLibrary.function(named: "metaphor_shadowDepthVertex", from: shadowKey) else {
            throw MetaphorError.shaderCompilationFailed(name: "metaphor_shadowDepthVertex", underlying: NSError(domain: "ShadowMap", code: -1))
        }

        // Pipeline for untextured geometry (positionNormalColor stride=40)
        let untexDesc = MTLRenderPipelineDescriptor()
        untexDesc.vertexFunction = vertexFn
        untexDesc.fragmentFunction = nil
        untexDesc.depthAttachmentPixelFormat = .depth32Float
        untexDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride)
        untexDesc.rasterSampleCount = 1
        self.depthPipelineUntextured = try device.makeRenderPipelineState(descriptor: untexDesc)

        // Pipeline for textured geometry (positionNormalUV stride=48)
        let texPipeDesc = MTLRenderPipelineDescriptor()
        texPipeDesc.vertexFunction = vertexFn
        texPipeDesc.fragmentFunction = nil
        texPipeDesc.depthAttachmentPixelFormat = .depth32Float
        texPipeDesc.vertexDescriptor = Self.makeShadowVertexDescriptor(stride: MemoryLayout<SIMD3<Float>>.stride * 3)
        texPipeDesc.rasterSampleCount = 1
        self.depthPipelineTextured = try device.makeRenderPipelineState(descriptor: texPipeDesc)

        // Depth stencil state
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: dsDesc)
    }

    // MARK: - Light Space Matrix

    /// Compute the light-space matrix from a directional light.
    ///
    /// - Parameters:
    ///   - lightDirection: The direction vector of the light.
    ///   - sceneCenter: The center of the scene to shadow.
    ///   - sceneRadius: The radius of the scene bounding sphere.
    func updateLightSpaceMatrix(lightDirection: SIMD3<Float>, sceneCenter: SIMD3<Float> = .zero, sceneRadius: Float = 500) {
        let dir = normalize(lightDirection)
        let lightPos = sceneCenter - dir * sceneRadius

        // Adjust up vector to avoid being parallel to the light direction
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

    /// Render recorded draw calls from the light's perspective into the depth texture.
    ///
    /// - Parameters:
    ///   - drawCalls: The array of recorded 3D draw calls.
    ///   - commandBuffer: The command buffer to encode into.
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
