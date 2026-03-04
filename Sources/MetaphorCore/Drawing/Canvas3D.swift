import Metal
import simd

// MARK: - Canvas3D Uniforms

/// Represent uniform data for Canvas3D shaders, matching the MSL `Canvas3DUniforms` layout.
struct Canvas3DUniforms {
    var modelMatrix: float4x4
    var viewProjectionMatrix: float4x4
    var normalMatrix: float4x4
    var color: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var time: Float
    var lightCount: UInt32
    var hasTexture: UInt32
    var _pad: UInt32 = 0
}

// MARK: - Light3D

/// Represent GPU-compatible light data (64 bytes, 16-byte aligned).
struct Light3D {
    var positionAndType: SIMD4<Float>           // xyz=position, w=type(0=dir,1=point,2=spot)
    var directionAndCutoff: SIMD4<Float>        // xyz=direction, w=cos(innerCutoff)
    var colorAndIntensity: SIMD4<Float>         // xyz=color, w=intensity
    var attenuationAndOuterCutoff: SIMD4<Float> // xyz=(const,linear,quad), w=cos(outerCutoff)

    static let zero = Light3D(
        positionAndType: .zero,
        directionAndCutoff: .zero,
        colorAndIntensity: .zero,
        attenuationAndOuterCutoff: .zero
    )
}

// MARK: - Material3D

/// Represent GPU-compatible material data (64 bytes).
struct Material3D {
    var ambientColor: SIMD4<Float>         // xyz=ambient color
    var specularAndShininess: SIMD4<Float> // xyz=specular color, w=shininess
    var emissiveAndMetallic: SIMD4<Float>  // xyz=emissive color, w=metallic
    var pbrParams: SIMD4<Float>            // x=roughness, y=usePBR(0/1), z=ao, w=reserved

    static let `default` = Material3D(
        ambientColor: SIMD4(0.2, 0.2, 0.2, 0),
        specularAndShininess: SIMD4(0, 0, 0, 32),
        emissiveAndMetallic: SIMD4(0, 0, 0, 0),
        pbrParams: SIMD4(0.5, 0, 1, 0)    // roughness=0.5, usePBR=off, ao=1, reserved=0
    )
}

// MARK: - Canvas3D

/// Provide an immediate-mode 3D drawing context.
///
/// Draws 3D scenes with a p5.js WEBGL-style API.
/// Shares the same render command encoder as Canvas2D, executing 3D draw calls immediately.
@MainActor
public final class Canvas3D {
    // MARK: - Metal Resources

    private let device: MTLDevice
    private let shaderLibrary: ShaderLibrary
    private let sampleCount: Int
    private let pipelineState: MTLRenderPipelineState
    private let texturedPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState?
    private let dummyShadowTexture: MTLTexture?

    // Instanced rendering pipelines
    private let instancedPipelineState: MTLRenderPipelineState
    private let instancedTexturedPipelineState: MTLRenderPipelineState
    private let instanceBatcher: InstanceBatcher3D

    private static let maxLights = 8

    // MARK: - Custom Material State

    private var currentCustomMaterial: CustomMaterial?
    private var customPipelineCache: [String: MTLRenderPipelineState] = [:]

    // MARK: - Dimensions

    /// The width of the 3D canvas in points.
    public let width: Float

    /// The height of the 3D canvas in points.
    public let height: Float

    // MARK: - Per-frame State

    private var encoder: MTLRenderCommandEncoder?
    private var currentTime: Float = 0

    // MARK: - Camera State

    private var cameraEye: SIMD3<Float> = SIMD3(0, 0, 5)
    private var cameraCenter: SIMD3<Float> = .zero
    private var cameraUp: SIMD3<Float> = SIMD3(0, 1, 0)
    private static let defaultFov: Float = Float.pi / 3
    private var fov: Float = Canvas3D.defaultFov
    private var nearPlane: Float = 0.1
    private var farPlane: Float = 10000
    private var viewProjectionDirty: Bool = true
    private var cachedViewProjection: float4x4 = .identity
    private var useOrthographic: Bool = false
    private var orthoLeft: Float = 0
    private var orthoRight: Float = 0
    private var orthoBottom: Float = 0
    private var orthoTop: Float = 0

    // MARK: - Lighting State

    private var lightArray: [Light3D] = []
    private var ambientColor: SIMD3<Float> = SIMD3(0.2, 0.2, 0.2)

    // MARK: - Material State

    private var currentMaterial: Material3D = .default

    // MARK: - Texture State

    private var currentTexture: MTLTexture?

    // MARK: - Transform Stack

    private struct StyleState3D {
        var transform: float4x4
        var fillColor: SIMD4<Float>
        var hasFill: Bool
        var hasStroke3D: Bool
        var strokeColor3D: SIMD4<Float>
        var material: Material3D
        var customMaterial: CustomMaterial?
        var texture: MTLTexture?
        var colorModeConfig: ColorModeConfig
    }

    private var stateStack: [StyleState3D] = []
    private var matrixStack: [float4x4] = []
    private var currentTransform: float4x4 = .identity

    // MARK: - Style

    private var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var hasFill: Bool = true
    private var hasStroke3D: Bool = false
    private var strokeColor3D: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var colorModeConfig: ColorModeConfig = ColorModeConfig()

    // MARK: - Shape Building State (3D beginShape/endShape)

    private var isRecordingShape3D: Bool = false
    private var shapeMode3D: ShapeMode = .polygon
    private var shapeVertices3D: [Vertex3D] = []
    private var pendingNormal: SIMD3<Float>?

    // MARK: - Mesh Cache

    private var meshCache: [String: Mesh] = [:]

    // MARK: - Shadow Mapping State

    /// The shadow map used for shadow rendering, or `nil` when shadows are disabled.
    var shadowMap: ShadowMap?

    /// The draw calls recorded during the current frame for the shadow depth pass.
    private(set) var recordedDrawCalls: [DrawCall3D] = []

    // MARK: - Initialization

    /// Create a canvas from a renderer, inheriting its device, shader library, and texture dimensions.
    ///
    /// - Parameter renderer: The renderer to derive configuration from.
    /// - Throws: An error if pipeline state creation fails.
    public convenience init(renderer: MetaphorRenderer) throws {
        try self.init(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: Float(renderer.textureManager.width),
            height: Float(renderer.textureManager.height),
            sampleCount: renderer.textureManager.sampleCount
        )
    }

    /// Create a canvas with explicit Metal resources and dimensions.
    ///
    /// - Parameters:
    ///   - device: The Metal device used for resource allocation.
    ///   - shaderLibrary: The shader library containing built-in shader functions.
    ///   - depthStencilCache: The cache for depth-stencil states.
    ///   - width: The canvas width in points.
    ///   - height: The canvas height in points.
    ///   - sampleCount: The MSAA sample count (defaults to 1).
    /// - Throws: An error if pipeline state creation fails.
    public init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Float,
        height: Float,
        sampleCount: Int = 1
    ) throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.sampleCount = sampleCount
        self.width = width
        self.height = height

        // Untextured pipeline
        let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DFragment,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        self.pipelineState = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        // Textured pipeline
        let texVertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        let texFragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        self.texturedPipelineState = try PipelineFactory(device: device)
            .vertex(texVertexFn)
            .fragment(texFragmentFn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        self.depthState = depthStencilCache.state(for: .readWrite)

        // Instanced pipeline (untextured)
        let instVertexFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.vertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        let instFragmentFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.fragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        self.instancedPipelineState = try PipelineFactory(device: device)
            .vertex(instVertexFn)
            .fragment(instFragmentFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        // Instanced pipeline (textured)
        let instTexVertexFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.texturedVertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        let instTexFragmentFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.texturedFragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        self.instancedTexturedPipelineState = try PipelineFactory(device: device)
            .vertex(instTexVertexFn)
            .fragment(instTexFragmentFn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        self.instanceBatcher = try InstanceBatcher3D(device: device)

        // Dummy 1x1 shadow texture (bound when shadows are disabled)
        let dummyDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false
        )
        dummyDesc.usage = .shaderRead
        dummyDesc.storageMode = .private
        self.dummyShadowTexture = device.makeTexture(descriptor: dummyDesc)
    }

    // MARK: - Frame Lifecycle

    /// Begin a new frame, resetting per-frame state and configuring the render encoder.
    func begin(encoder: MTLRenderCommandEncoder, time: Float, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentTime = time
        // Reset per-frame state (transform, camera, lights, draw calls)
        self.currentTransform = .identity
        self.stateStack.removeAll(keepingCapacity: true)
        self.lightArray.removeAll(keepingCapacity: true)
        self.ambientColor = SIMD3(0.2, 0.2, 0.2)
        self.currentMaterial = .default
        self.currentTexture = nil
        self.currentCustomMaterial = nil
        self.recordedDrawCalls.removeAll(keepingCapacity: true)

        // Reset projection to Processing-like defaults each frame.
        // Users must call perspective()/ortho() every frame for custom projection.
        let defaultZ = (height / 2) / tan(Canvas3D.defaultFov / 2)
        self.fov = Canvas3D.defaultFov
        self.nearPlane = defaultZ / 10
        self.farPlane = defaultZ * 10
        self.cameraEye = SIMD3(width / 2, height / 2, defaultZ)
        self.cameraCenter = SIMD3(width / 2, height / 2, 0)
        self.cameraUp = SIMD3(0, 1, 0)
        self.viewProjectionDirty = true
        self.useOrthographic = false

        // Style state (fill, stroke) is preserved across frames
        // to match Processing behavior.
        instanceBatcher.beginFrame(bufferIndex: bufferIndex)
    }

    /// End the current frame, flushing any pending instance batches.
    func end() {
        flushInstanceBatch()
        self.encoder = nil
    }

    /// Execute the shadow depth pass after the main rendering pass completes.
    func performShadowPass(commandBuffer: MTLCommandBuffer) {
        guard let shadow = shadowMap, !recordedDrawCalls.isEmpty else { return }

        // Compute light-space matrix from the first directional light
        if let dirLight = lightArray.first(where: { UInt32($0.positionAndType.w) == 0 }) {
            let lightDir = SIMD3(dirLight.directionAndCutoff.x, dirLight.directionAndCutoff.y, dirLight.directionAndCutoff.z)
            shadow.updateLightSpaceMatrix(lightDirection: lightDir, sceneCenter: cameraCenter)
        }

        shadow.render(drawCalls: recordedDrawCalls, commandBuffer: commandBuffer)
    }

    // MARK: - Public Camera Accessors

    /// Return the current view-projection matrix.
    public var currentViewProjection: float4x4 {
        computeViewProjection()
    }

    /// Return the camera's right direction vector, useful for billboarding.
    public var currentCameraRight: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        return normalize(cross(cameraUp, z))
    }

    /// Return the camera's up direction vector, useful for billboarding.
    public var currentCameraUp: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        let x = normalize(cross(cameraUp, z))
        return cross(z, x)
    }

    // MARK: - Camera

    /// Set the camera position and orientation.
    ///
    /// - Parameters:
    ///   - eye: The camera position in world space.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector.
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        self.cameraEye = eye
        self.cameraCenter = center
        self.cameraUp = up
        self.viewProjectionDirty = true
    }

    /// Configure perspective projection parameters.
    ///
    /// - Parameters:
    ///   - fov: The vertical field of view in radians.
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func perspective(
        fov: Float = Float.pi / 3,
        near: Float = 0.1,
        far: Float = 10000
    ) {
        self.fov = fov
        self.nearPlane = near
        self.farPlane = far
        self.useOrthographic = false
        self.viewProjectionDirty = true
    }

    /// Switch to orthographic projection.
    ///
    /// - Parameters:
    ///   - left: The left edge of the view volume (`nil` defaults to 0).
    ///   - right: The right edge of the view volume (`nil` defaults to canvas width).
    ///   - bottom: The bottom edge of the view volume (`nil` defaults to canvas height).
    ///   - top: The top edge of the view volume (`nil` defaults to 0).
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        self.useOrthographic = true
        self.orthoLeft = left ?? 0
        self.orthoRight = right ?? width
        self.orthoBottom = bottom ?? height
        self.orthoTop = top ?? 0
        self.nearPlane = near
        self.farPlane = far
        self.viewProjectionDirty = true
    }

    // MARK: - Lighting

    /// Enable default lighting with a single directional light for backward compatibility.
    public func lights() {
        lightArray.removeAll(keepingCapacity: true)
        ambientColor = SIMD3(0.3, 0.3, 0.3)
        currentMaterial.ambientColor = SIMD4(0.3, 0.3, 0.3, 0)

        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(-0.5, -1.0, -0.8, 0)
        light.colorAndIntensity = SIMD4(1, 1, 1, 0.7)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// Remove all lights from the scene.
    public func noLights() {
        lightArray.removeAll(keepingCapacity: true)
    }

    /// Add a white directional light with the given direction.
    ///
    /// - Parameters:
    ///   - x: The x component of the light direction.
    ///   - y: The y component of the light direction.
    ///   - z: The z component of the light direction.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        directionalLight(x, y, z, color: Color.white)
    }

    /// Add a directional light with the given direction and color.
    ///
    /// - Parameters:
    ///   - x: The x component of the light direction.
    ///   - y: The y component of the light direction.
    ///   - z: The z component of the light direction.
    ///   - color: The light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // Transform local-space direction to world space (w=0 excludes translation)
        let td = currentTransform * SIMD4(x, y, z, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, 0)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// Add a point light at the given position.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the light position.
    ///   - y: The y coordinate of the light position.
    ///   - z: The z coordinate of the light position.
    ///   - color: The light color.
    ///   - falloff: The attenuation falloff factor.
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // Transform local-space position to world space
        let tp = currentTransform * SIMD4(x, y, z, 1)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 1)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, 0)
        lightArray.append(light)
    }

    /// Add a spot light at the given position with a specified direction.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the light position.
    ///   - y: The y coordinate of the light position.
    ///   - z: The z coordinate of the light position.
    ///   - dirX: The x component of the spotlight direction.
    ///   - dirY: The y component of the spotlight direction.
    ///   - dirZ: The z component of the spotlight direction.
    ///   - angle: The outer cone angle in radians.
    ///   - falloff: The attenuation falloff factor.
    ///   - color: The light color.
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        let innerAngle = angle * 0.8
        // Transform local-space position and direction to world space
        let tp = currentTransform * SIMD4(x, y, z, 1)
        let td = currentTransform * SIMD4(dirX, dirY, dirZ, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 2)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, cos(innerAngle))
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, cos(angle))
        lightArray.append(light)
    }

    /// Set the ambient light intensity uniformly across all channels.
    ///
    /// - Parameter strength: The ambient light intensity value applied to R, G, and B.
    public func ambientLight(_ strength: Float) {
        ambientColor = SIMD3(strength, strength, strength)
        currentMaterial.ambientColor = SIMD4(strength, strength, strength, 0)
    }

    /// Set the ambient light color using individual RGB components.
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        ambientColor = SIMD3(r, g, b)
        currentMaterial.ambientColor = SIMD4(r, g, b, 0)
    }

    // MARK: - Material

    /// Set the specular highlight color of the current material.
    ///
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        currentMaterial.specularAndShininess = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.specularAndShininess.w
        )
    }

    /// Set the specular highlight color as a grayscale value.
    ///
    /// - Parameter gray: The grayscale intensity applied to all channels.
    public func specular(_ gray: Float) {
        currentMaterial.specularAndShininess = SIMD4(
            gray, gray, gray,
            currentMaterial.specularAndShininess.w
        )
    }

    /// Set the shininess exponent of the current material.
    ///
    /// - Parameter value: The shininess exponent (higher values produce tighter highlights).
    public func shininess(_ value: Float) {
        currentMaterial.specularAndShininess.w = value
    }

    /// Set the emissive color of the current material.
    ///
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// Set the emissive color as a grayscale value.
    ///
    /// - Parameter gray: The grayscale intensity applied to all channels.
    public func emissive(_ gray: Float) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            gray, gray, gray,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// Set the metallic factor of the current material.
    ///
    /// - Parameter value: The metallic factor from 0.0 (dielectric) to 1.0 (fully metallic).
    public func metallic(_ value: Float) {
        currentMaterial.emissiveAndMetallic.w = value
    }

    /// Set the PBR roughness, automatically enabling PBR shading mode.
    ///
    /// - Parameter value: The roughness from 0.0 (mirror-like) to 1.0 (fully diffuse).
    public func roughness(_ value: Float) {
        currentMaterial.pbrParams.x = value
        currentMaterial.pbrParams.y = 1  // Automatically enable PBR mode
    }

    /// Set the PBR ambient occlusion factor.
    ///
    /// - Parameter value: The occlusion from 0.0 (fully occluded) to 1.0 (no occlusion).
    public func ambientOcclusion(_ value: Float) {
        currentMaterial.pbrParams.z = value
    }

    /// Toggle PBR shading mode explicitly.
    ///
    /// - Parameter enabled: Pass `true` for Cook-Torrance GGX shading, `false` for Blinn-Phong.
    public func pbr(_ enabled: Bool) {
        currentMaterial.pbrParams.y = enabled ? 1 : 0
    }

    // MARK: - Custom Material

    /// Apply a custom fragment shader material for subsequent draw calls.
    ///
    /// - Parameter custom: The custom material to apply.
    public func material(_ custom: CustomMaterial) {
        currentCustomMaterial = custom
    }

    /// Remove the custom material, reverting to the built-in shader.
    public func noMaterial() {
        currentCustomMaterial = nil
    }

    // MARK: - Texture

    /// Set the texture for subsequent textured draw calls.
    ///
    /// - Parameter img: The image whose texture will be bound.
    public func texture(_ img: MImage) {
        currentTexture = img.texture
    }

    /// Remove the currently bound texture.
    public func noTexture() {
        currentTexture = nil
    }

    // MARK: - Transform Stack

    /// Save the entire state including transform, style, and material.
    public func pushState() {
        stateStack.append(StyleState3D(
            transform: currentTransform,
            fillColor: fillColor,
            hasFill: hasFill,
            hasStroke3D: hasStroke3D,
            strokeColor3D: strokeColor3D,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            texture: currentTexture,
            colorModeConfig: colorModeConfig
        ))
    }

    /// Restore the previously saved state.
    public func popState() {
        guard let saved = stateStack.popLast() else { return }
        currentTransform = saved.transform
        fillColor = saved.fillColor
        hasFill = saved.hasFill
        hasStroke3D = saved.hasStroke3D
        strokeColor3D = saved.strokeColor3D
        currentMaterial = saved.material
        currentCustomMaterial = saved.customMaterial
        currentTexture = saved.texture
        colorModeConfig = saved.colorModeConfig
    }

    /// Save only the current transform matrix.
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// Restore only the previously saved transform matrix.
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// Translate the current transform by the given offsets.
    ///
    /// - Parameters:
    ///   - x: The translation along the x-axis.
    ///   - y: The translation along the y-axis.
    ///   - z: The translation along the z-axis.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(translation: SIMD3(x, y, z))
    }

    /// Rotate the current transform around the x-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationX: angle) }

    /// Rotate the current transform around the y-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationY: angle) }

    /// Rotate the current transform around the z-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationZ: angle) }

    /// Scale the current transform non-uniformly along each axis.
    ///
    /// - Parameters:
    ///   - x: The scale factor along the x-axis.
    ///   - y: The scale factor along the y-axis.
    ///   - z: The scale factor along the z-axis.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(scale: SIMD3(x, y, z))
    }

    /// Scale the current transform uniformly along all axes.
    ///
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) { currentTransform = currentTransform * float4x4(scale: s) }

    // MARK: - Style Sync

    /// Synchronize common style properties from a shared drawing style.
    ///
    /// - Parameter style: The drawing style to synchronize from.
    public func syncStyle(_ style: DrawingStyle) {
        fillColor = style.fillColor
        strokeColor3D = style.strokeColor
        hasFill = style.hasFill
        hasStroke3D = style.hasStroke
        colorModeConfig = style.colorModeConfig
    }

    // MARK: - Style

    /// Set the fill color.
    ///
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) { fillColor = color.simd; hasFill = true }

    /// Set the fill color using components interpreted according to the current color mode.
    ///
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha component.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasFill = true
    }

    /// Set the fill color as a grayscale value.
    ///
    /// - Parameter gray: The grayscale intensity.
    public func fill(_ gray: Float) {
        fillColor = colorModeConfig.toGray(gray).simd
        hasFill = true
    }

    /// Set the fill color as a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) {
        fillColor = colorModeConfig.toGray(gray, alpha).simd
        hasFill = true
    }

    /// Disable fill for subsequent shapes.
    public func noFill() { hasFill = false }

    /// Set the stroke color.
    ///
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) { strokeColor3D = color.simd; hasStroke3D = true }

    /// Set the stroke color using components interpreted according to the current color mode.
    ///
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha component.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        strokeColor3D = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasStroke3D = true
    }

    /// Set the stroke color as a grayscale value.
    ///
    /// - Parameter gray: The grayscale intensity.
    public func stroke(_ gray: Float) {
        strokeColor3D = colorModeConfig.toGray(gray).simd
        hasStroke3D = true
    }

    /// Set the stroke color as a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        strokeColor3D = colorModeConfig.toGray(gray, alpha).simd
        hasStroke3D = true
    }

    /// Disable stroke for subsequent shapes.
    public func noStroke() { hasStroke3D = false }

    /// Set the color space and per-component maximum values.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value for the first component.
    ///   - max2: The maximum value for the second component.
    ///   - max3: The maximum value for the third component.
    ///   - maxA: The maximum value for the alpha component.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        colorModeConfig = ColorModeConfig(space: space, max1: max1, max2: max2, max3: max3, maxAlpha: maxA)
    }

    /// Set the color space with a uniform maximum value for all components.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The maximum value applied to all components including alpha.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        colorModeConfig = ColorModeConfig(space: space, max1: maxAll, max2: maxAll, max3: maxAll, maxAlpha: maxAll)
    }

    // MARK: - 3D Shapes

    /// Draw a box with the given dimensions.
    ///
    /// - Parameters:
    ///   - width: The box width.
    ///   - height: The box height.
    ///   - depth: The box depth.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        let key = "box_\(width)_\(height)_\(depth)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.box(device: device, width: width, height: height, depth: depth) }) else { return }
        drawMesh(mesh)
    }

    /// Draw a cube with equal dimensions.
    ///
    /// - Parameter size: The edge length of the cube.
    public func box(_ size: Float) { box(size, size, size) }

    /// Draw a sphere with the given radius and tessellation detail.
    ///
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - detail: The number of longitudinal segments (rings are derived from this).
    public func sphere(_ radius: Float, detail: Int = 24) {
        let rings = max(detail / 2, 4)
        let key = "sphere_\(radius)_\(detail)_\(rings)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.sphere(device: device, radius: radius, segments: detail, rings: rings) }) else { return }
        drawMesh(mesh)
    }

    /// Draw a flat plane with the given dimensions.
    ///
    /// - Parameters:
    ///   - width: The plane width.
    ///   - height: The plane height.
    public func plane(_ width: Float, _ height: Float) {
        let key = "plane_\(width)_\(height)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.plane(device: device, width: width, height: height) }) else { return }
        drawMesh(mesh)
    }

    /// Draw a cylinder with the given radius, height, and tessellation detail.
    ///
    /// - Parameters:
    ///   - radius: The cylinder radius.
    ///   - height: The cylinder height.
    ///   - detail: The number of radial segments.
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cylinder_\(radius)_\(height)_\(detail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.cylinder(device: device, radius: radius, height: height, segments: detail) }) else { return }
        drawMesh(mesh)
    }

    /// Draw a cone with the given radius, height, and tessellation detail.
    ///
    /// - Parameters:
    ///   - radius: The base radius.
    ///   - height: The cone height.
    ///   - detail: The number of radial segments.
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cone_\(radius)_\(height)_\(detail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.cone(device: device, radius: radius, height: height, segments: detail) }) else { return }
        drawMesh(mesh)
    }

    /// Draw a torus with the given ring and tube radii.
    ///
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The number of radial segments around the ring.
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        let tubeDetail = max(detail / 2, 8)
        let key = "torus_\(ringRadius)_\(tubeRadius)_\(detail)_\(tubeDetail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.torus(device: device, ringRadius: ringRadius, tubeRadius: tubeRadius, segments: detail, tubeSegments: tubeDetail) }) else { return }
        drawMesh(mesh)
    }

    /// Look up or create a cached mesh, logging errors on failure.
    private func cachedMesh(key: String, create: () throws -> Mesh) -> Mesh? {
        if let cached = meshCache[key] { return cached }
        do {
            let mesh = try create()
            meshCache[key] = mesh
            return mesh
        } catch {
            print("[metaphor] Failed to create mesh '\(key)': \(error)")
            return nil
        }
    }

    /// Draw a pre-built mesh.
    ///
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) { drawMesh(mesh) }

    /// Draw a dynamic mesh that supports runtime vertex modifications.
    ///
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        mesh.ensureBuffers()
        guard let encoder = encoder,
              let vb = mesh.vertexBuffer else { return }
        guard hasFill || hasStroke3D else { return }

        // DynamicMesh is not eligible for instancing
        flushInstanceBatch()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setVertexBuffer(vb, offset: 0, index: 0)

        if hasFill {
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 0
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }
        }

        if hasStroke3D {
            encoder.setTriangleFillMode(.lines)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor3D,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - 3D Custom Shapes (beginShape / endShape)

    /// Begin recording vertices for a 3D custom shape.
    ///
    /// - Parameter mode: The shape tessellation mode.
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape3D = true
        shapeMode3D = mode
        shapeVertices3D.removeAll(keepingCapacity: true)
        pendingNormal = nil
    }

    /// Add a 3D vertex at the given position.
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: fillColor
        ))
    }

    /// Add a 3D vertex with a per-vertex color.
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: color.simd
        ))
    }

    /// Set the normal vector to apply to subsequent vertices.
    ///
    /// - Parameters:
    ///   - nx: The x component of the normal.
    ///   - ny: The y component of the normal.
    ///   - nz: The z component of the normal.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal = SIMD3(nx, ny, nz)
    }

    /// End recording and draw the 3D shape.
    ///
    /// - Parameter close: Whether to close the shape.
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape3D else { return }
        isRecordingShape3D = false

        guard !shapeVertices3D.isEmpty else { return }

        // Auto-compute normals when in polygon/triangles mode and no normal was explicitly set
        if pendingNormal == nil {
            autoComputeNormals()
        }

        switch shapeMode3D {
        case .polygon:
            drawShape3DPolygon(close: close)
        case .triangles:
            drawShape3DTriangles()
        case .triangleStrip:
            drawShape3DTriangleStrip()
        case .triangleFan:
            drawShape3DTriangleFan()
        case .points:
            drawShape3DPoints()
        case .lines:
            drawShape3DLines()
        }

        pendingNormal = nil
    }

    // MARK: - Private: 3D Shape Tessellation

    // Compute face normals for every group of 3 vertices.
    private func autoComputeNormals() {
        var i = 0
        while i + 2 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let p2 = shapeVertices3D[i + 2].position
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            let n = simd_normalize(simd_cross(edge1, edge2))
            let safeN = n.x.isNaN ? SIMD3<Float>(0, 1, 0) : n
            shapeVertices3D[i].normal = safeN
            shapeVertices3D[i + 1].normal = safeN
            shapeVertices3D[i + 2].normal = safeN
            i += 3
        }
    }

    // Draw an array of pre-tessellated 3D vertices with fill and/or wireframe passes.
    private func drawShape3DVertices(_ vertices: [Vertex3D]) {
        guard let encoder = encoder, !vertices.isEmpty else { return }
        guard hasFill || hasStroke3D else { return }

        // Flush instance batch since beginShape/endShape uses individual vertex drawing
        flushInstanceBatch()

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if hasFill {
            encoder.setRenderPipelineState(pipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 0
            )

            encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex3D>.stride * vertices.count, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        if hasStroke3D {
            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(pipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor3D,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex3D>.stride * vertices.count, index: 0)
            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            encoder.setTriangleFillMode(.fill)
        }
    }

    // Tessellate a polygon using a simple triangle fan (suitable for convex polygons).
    private func drawShape3DPolygon(close: CloseMode) {
        guard shapeVertices3D.count >= 3 else { return }

        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        // Compute face normal from the first 3 vertices
        let p0 = shapeVertices3D[0].position
        let p1 = shapeVertices3D[1].position
        let p2 = shapeVertices3D[2].position
        let faceNormal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
        let safeNormal = faceNormal.x.isNaN ? SIMD3<Float>(0, 1, 0) : faceNormal

        for i in 1..<(shapeVertices3D.count - 1) {
            var v0 = shapeVertices3D[0]
            var v1 = shapeVertices3D[i]
            var v2 = shapeVertices3D[i + 1]
            // Apply face normal to vertices that lack an explicit normal
            if pendingNormal == nil {
                v0.normal = safeNormal
                v1.normal = safeNormal
                v2.normal = safeNormal
            }
            triangulated.append(v0)
            triangulated.append(v1)
            triangulated.append(v2)
        }

        drawShape3DVertices(triangulated)
    }

    // Draw vertices directly as independent triangles (every 3 vertices form one triangle).
    private func drawShape3DTriangles() {
        let count = (shapeVertices3D.count / 3) * 3
        guard count >= 3 else { return }
        drawShape3DVertices(Array(shapeVertices3D.prefix(count)))
    }

    // Tessellate a triangle strip into independent triangles.
    private func drawShape3DTriangleStrip() {
        guard shapeVertices3D.count >= 3 else { return }
        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 0..<(shapeVertices3D.count - 2) {
            if i % 2 == 0 {
                triangulated.append(shapeVertices3D[i])
                triangulated.append(shapeVertices3D[i + 1])
                triangulated.append(shapeVertices3D[i + 2])
            } else {
                triangulated.append(shapeVertices3D[i + 1])
                triangulated.append(shapeVertices3D[i])
                triangulated.append(shapeVertices3D[i + 2])
            }
        }
        drawShape3DVertices(triangulated)
    }

    // Tessellate a triangle fan into independent triangles.
    private func drawShape3DTriangleFan() {
        guard shapeVertices3D.count >= 3 else { return }
        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 1..<(shapeVertices3D.count - 1) {
            triangulated.append(shapeVertices3D[0])
            triangulated.append(shapeVertices3D[i])
            triangulated.append(shapeVertices3D[i + 1])
        }
        drawShape3DVertices(triangulated)
    }

    // Draw each vertex as a small triangle to simulate a point.
    private func drawShape3DPoints() {
        guard let encoder = encoder else { return }
        guard !shapeVertices3D.isEmpty else { return }

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        // Build triangles for all vertices in a single batch
        var allVerts: [Vertex3D] = []
        allVerts.reserveCapacity(shapeVertices3D.count * 3)

        let s: Float = 0.5
        for v in shapeVertices3D {
            allVerts.append(Vertex3D(position: v.position + SIMD3(-s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( 0,  s, 0), normal: v.normal, color: v.color))
        }

        var uniforms = Canvas3DUniforms(
            modelMatrix: currentTransform,
            viewProjectionMatrix: viewProj,
            normalMatrix: normalMatrix,
            color: shapeVertices3D[0].color,
            cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
            time: currentTime,
            lightCount: 0,
            hasTexture: 0
        )

        encoder.setVertexBytes(allVerts, length: MemoryLayout<Vertex3D>.stride * allVerts.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

        var dummy = Light3D.zero
        encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
        var mat = currentMaterial
        encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: allVerts.count)
    }

    // Draw line segments as thin triangle pairs (2 vertices per segment).
    private func drawShape3DLines() {
        guard shapeVertices3D.count >= 2 else { return }
        var lineVerts: [Vertex3D] = []
        lineVerts.reserveCapacity((shapeVertices3D.count / 2) * 6)

        let lineWidth: Float = 0.5
        var i = 0
        while i + 1 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let dir = p1 - p0
            let len = simd_length(dir)
            guard len > 0 else { i += 2; continue }

            // Compute offset using the cross product of the line direction and view direction
            let viewDir = simd_normalize(cameraEye - (p0 + p1) * 0.5)
            var offset = simd_normalize(simd_cross(dir, viewDir)) * lineWidth * 0.5
            if offset.x.isNaN { offset = SIMD3(0, lineWidth * 0.5, 0) }

            let n = shapeVertices3D[i].normal
            let c = shapeVertices3D[i].color

            lineVerts.append(Vertex3D(position: p0 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            i += 2
        }

        drawShape3DVertices(lineVerts)
    }

    // MARK: - Internal Drawing

    // Route mesh drawing through the instancing path or immediate fallback.
    private func drawMesh(_ mesh: Mesh) {
        guard encoder != nil else { return }
        guard hasFill || hasStroke3D else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        // Record draw call for shadow pass when shadows are enabled
        if shadowMap != nil {
            recordedDrawCalls.append(DrawCall3D(
                mesh: mesh,
                transform: currentTransform,
                fillColor: fillColor,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                texture: currentTexture,
                isTextured: isTextured,
                hasFill: hasFill,
                hasStroke: hasStroke3D,
                strokeColor: strokeColor3D
            ))
        }

        // Custom vertex shader prevents instancing; fall back to immediate path
        if let customMat = currentCustomMaterial, customMat.vertexFunction != nil {
            flushInstanceBatch()
            drawMeshImmediate(mesh)
            return
        }

        // Generate batch key
        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let key = InstanceBatcher3D.BatchKey(
            meshID: ObjectIdentifier(mesh),
            isTextured: isTextured,
            textureID: currentTexture.map { ObjectIdentifier($0 as AnyObject) },
            material: currentMaterial,
            customMaterialID: currentCustomMaterial.map { ObjectIdentifier($0) },
            hasFill: hasFill,
            hasStroke: hasStroke3D,
            strokeColor: strokeColor3D
        )

        // Attempt to accumulate into instance batch
        if !instanceBatcher.tryAddInstance(
            key: key,
            mesh: mesh,
            texture: currentTexture,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            hasFill: hasFill,
            hasStroke: hasStroke3D,
            strokeColor: strokeColor3D,
            transform: currentTransform,
            normalMatrix: normalMatrix,
            color: fillColor
        ) {
            // Key mismatch or buffer full; flush current batch and retry
            flushInstanceBatch()
            let _ = instanceBatcher.tryAddInstance(
                key: key,
                mesh: mesh,
                texture: currentTexture,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                hasFill: hasFill,
                hasStroke: hasStroke3D,
                strokeColor: strokeColor3D,
                transform: currentTransform,
                normalMatrix: normalMatrix,
                color: fillColor
            )
        }
    }

    // MARK: - Instanced Batch Flush

    /// Flush accumulated instances as a single instanced draw call.
    private func flushInstanceBatch() {
        guard let encoder = encoder,
              instanceBatcher.instanceCount > 0,
              let mesh = instanceBatcher.currentMesh else { return }

        let isTextured = instanceBatcher.currentBatchKey?.isTextured ?? false
        let batchHasFill = instanceBatcher.currentHasFill
        let batchHasStroke = instanceBatcher.currentHasStroke

        // Select pipeline
        if let customMat = instanceBatcher.currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? instancedTexturedPipelineState : instancedPipelineState)
        }

        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        // Vertex buffer
        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // Instance buffer at buffer(6)
        encoder.setVertexBuffer(instanceBatcher.currentBuffer, offset: instanceBatcher.currentBufferOffset, index: 6)

        // --- Fill pass ---
        if batchHasFill {
            var sceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )
            encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            // Lights
            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            // Material
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // Custom material parameters
            if let customMat = instanceBatcher.currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            // Shadow
            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                if let dummy = dummyShadowTexture {
                    encoder.setFragmentTexture(dummy, index: 1)
                }
            }

            // Texture
            if isTextured, let tex = instanceBatcher.currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            // Instanced draw
            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                let vc = isTextured ? mesh.uvVertexCount : mesh.vertexCount
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: vc,
                    instanceCount: instanceBatcher.instanceCount
                )
            }
        }

        // --- Wireframe (stroke) pass ---
        if batchHasStroke {
            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(instancedPipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)

            // Wireframe uses no lighting. Stroke color is uniform across all instances
            // (BatchKey requires matching strokeColor, so all instances share the same value).
            // Instead of overwriting the instance buffer's color for stroke, we simply set
            // lightCount=0 in scene uniforms and use the instance color as-is.
            var wireSceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )
            encoder.setVertexBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // Shadow disabled for wireframe
            var shadowOff = ShadowFragmentUniforms(lightSpaceMatrix: .identity, shadowBias: 0, shadowEnabled: 0)
            encoder.setFragmentBytes(&shadowOff, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
            if let dummyTex = dummyShadowTexture {
                encoder.setFragmentTexture(dummyTex, index: 1)
            }

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount,
                    instanceCount: instanceBatcher.instanceCount
                )
            }

            encoder.setTriangleFillMode(.fill)
        }

        instanceBatcher.reset()
    }

    // MARK: - Immediate Drawing (fallback, non-instanced)

    // Draw a mesh without instancing (fallback for custom vertex shaders).
    private func drawMeshImmediate(_ mesh: Mesh) {
        guard let encoder = encoder else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        if let customMat = currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured, customVertexFunction: customMat.vertexFunction) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? texturedPipelineState : pipelineState)
        }
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // --- Fill pass ---
        if hasFill {
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let customMat = currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                if let dummy = dummyShadowTexture {
                    encoder.setFragmentTexture(dummy, index: 1)
                }
            }

            if isTextured, let tex = currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: isTextured ? mesh.uvVertexCount : mesh.vertexCount
                )
            }
        }

        // --- Wireframe (stroke) pass ---
        if hasStroke3D {
            encoder.setTriangleFillMode(.lines)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor3D,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: mesh.vertexCount
                )
            }

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - Custom Pipeline

    /// Clear the custom pipeline cache, typically called after shader hot-reload.
    public func clearCustomPipelineCache() {
        customPipelineCache.removeAll()
    }

    // Retrieve or create a cached pipeline for custom shaders.
    private func getCustomPipeline(fragmentFunction: MTLFunction, isTextured: Bool, customVertexFunction: MTLFunction? = nil) -> MTLRenderPipelineState? {
        let vtxName = customVertexFunction?.name ?? "default"
        let cacheKey = "\(fragmentFunction.name)_\(vtxName)_\(isTextured)_\(sampleCount)"
        if let cached = customPipelineCache[cacheKey] {
            return cached
        }

        let vertexFn: MTLFunction?
        let layout: VertexLayout

        if let customVtx = customVertexFunction {
            vertexFn = customVtx
            layout = isTextured ? .positionNormalUV : .positionNormalColor
        } else if isTextured {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
                from: ShaderLibrary.BuiltinKey.canvas3DTextured
            )
            layout = .positionNormalUV
        } else {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DVertex,
                from: ShaderLibrary.BuiltinKey.canvas3D
            )
            layout = .positionNormalColor
        }

        guard let pipeline = try? PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFunction)
            .vertexLayout(layout)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()
        else {
            return nil
        }

        customPipelineCache[cacheKey] = pipeline
        return pipeline
    }

    // MARK: - Private Helpers

    // Compute and cache the view-projection matrix.
    private func computeViewProjection() -> float4x4 {
        if viewProjectionDirty {
            let view = float4x4(lookAt: cameraEye, center: cameraCenter, up: cameraUp)
            let proj: float4x4
            if useOrthographic {
                proj = float4x4(
                    orthographic: orthoLeft, right: orthoRight,
                    bottom: orthoBottom, top: orthoTop,
                    near: nearPlane, far: farPlane
                )
            } else {
                let aspect = width / height
                proj = float4x4(perspectiveFov: fov, aspect: aspect, near: nearPlane, far: farPlane)
            }
            // Flip Y so 3D matches Processing's Y-down convention (same as Canvas2D).
            var flipY = float4x4(1)
            flipY.columns.1.y = -1
            cachedViewProjection = flipY * proj * view
            viewProjectionDirty = false
        }
        return cachedViewProjection
    }

    // Compute the normal matrix (inverse-transpose of the upper-left 3x3) from a model matrix.
    private func computeNormalMatrix(from model: float4x4) -> float4x4 {
        let m3 = float3x3(
            SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
            SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
            SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z)
        )
        let invT = m3.inverse.transpose
        return float4x4(columns: (
            SIMD4(invT.columns.0.x, invT.columns.0.y, invT.columns.0.z, 0),
            SIMD4(invT.columns.1.x, invT.columns.1.y, invT.columns.1.z, 0),
            SIMD4(invT.columns.2.x, invT.columns.2.y, invT.columns.2.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    // Set default ambient values when the first light is added.
    private func ensureAmbientIfFirstLight() {
        if lightArray.isEmpty {
            ambientColor = SIMD3(0.3, 0.3, 0.3)
            currentMaterial.ambientColor = SIMD4(0.3, 0.3, 0.3, 0)
        }
    }
}
