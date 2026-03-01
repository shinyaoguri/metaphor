import Metal
import simd

// MARK: - Canvas3D Uniforms

/// Canvas3Dシェーダー用ユニフォーム（MSLのCanvas3DUniformsと一致）
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

/// GPU互換ライトデータ（64 bytes、16-byte aligned）
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

/// GPU互換マテリアルデータ（48 bytes）
struct Material3D {
    var ambientColor: SIMD4<Float>         // xyz=ambient color
    var specularAndShininess: SIMD4<Float> // xyz=specular color, w=shininess
    var emissiveAndMetallic: SIMD4<Float>  // xyz=emissive color, w=metallic

    static let `default` = Material3D(
        ambientColor: SIMD4(0.2, 0.2, 0.2, 0),
        specularAndShininess: SIMD4(0, 0, 0, 32),
        emissiveAndMetallic: SIMD4(0, 0, 0, 0)
    )
}

// MARK: - Canvas3D

/// Immediate-mode 3D描画コンテキスト
///
/// p5.js WEBGL mode風のAPIで3Dシーンを描画する。
/// Canvas2Dと同一エンコーダを共有し、3D描画は即時実行される。
@MainActor
public final class Canvas3D {
    // MARK: - Metal Resources

    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let texturedPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState?

    private static let maxLights = 8

    // MARK: - Dimensions

    public let width: Float
    public let height: Float

    // MARK: - Per-frame State

    private var encoder: MTLRenderCommandEncoder?
    private var currentTime: Float = 0

    // MARK: - Camera State

    private var cameraEye: SIMD3<Float> = SIMD3(0, 0, 5)
    private var cameraCenter: SIMD3<Float> = .zero
    private var cameraUp: SIMD3<Float> = SIMD3(0, 1, 0)
    private var fov: Float = Float.pi / 3
    private var nearPlane: Float = 0.1
    private var farPlane: Float = 10000
    private var viewProjectionDirty: Bool = true
    private var cachedViewProjection: float4x4 = .identity

    // MARK: - Lighting State

    private var lightArray: [Light3D] = []
    private var ambientColor: SIMD3<Float> = SIMD3(0.2, 0.2, 0.2)

    // MARK: - Material State

    private var currentMaterial: Material3D = .default

    // MARK: - Texture State

    private var currentTexture: MTLTexture?

    // MARK: - Transform Stack

    private var transformStack: [float4x4] = []
    private var currentTransform: float4x4 = .identity

    // MARK: - Style

    private var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    // MARK: - Mesh Cache

    private var meshCache: [String: Mesh] = [:]

    // MARK: - Initialization

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

    public init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Float,
        height: Float,
        sampleCount: Int = 1
    ) throws {
        self.device = device
        self.width = width
        self.height = height

        // Untextured パイプライン
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

        // Textured パイプライン
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
    }

    // MARK: - Frame Lifecycle

    func begin(encoder: MTLRenderCommandEncoder, time: Float) {
        self.encoder = encoder
        self.currentTime = time
        self.currentTransform = .identity
        self.transformStack.removeAll(keepingCapacity: true)
        self.fillColor = SIMD4(1, 1, 1, 1)
        self.lightArray.removeAll(keepingCapacity: true)
        self.ambientColor = SIMD3(0.2, 0.2, 0.2)
        self.currentMaterial = .default
        self.currentTexture = nil

        let defaultZ = (height / 2) / tan(fov / 2)
        self.cameraEye = SIMD3(0, 0, defaultZ)
        self.cameraCenter = .zero
        self.cameraUp = SIMD3(0, 1, 0)
        self.viewProjectionDirty = true
    }

    func end() {
        self.encoder = nil
    }

    // MARK: - Camera

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

    public func perspective(
        fov: Float = Float.pi / 3,
        near: Float = 0.1,
        far: Float = 10000
    ) {
        self.fov = fov
        self.nearPlane = near
        self.farPlane = far
        self.viewProjectionDirty = true
    }

    // MARK: - Lighting

    /// デフォルトライティングを有効化（後方互換）
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

    public func noLights() {
        lightArray.removeAll(keepingCapacity: true)
    }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        directionalLight(x, y, z, color: Color.white)
    }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // ローカル座標系の方向をワールド空間に変換（w=0で平行移動を除外）
        let td = currentTransform * SIMD4(x, y, z, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, 0)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // ローカル座標系の位置をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 1)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, 0)
        lightArray.append(light)
    }

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
        // ローカル座標系の位置と方向をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        let td = currentTransform * SIMD4(dirX, dirY, dirZ, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 2)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, cos(innerAngle))
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, cos(angle))
        lightArray.append(light)
    }

    public func ambientLight(_ strength: Float) {
        ambientColor = SIMD3(strength, strength, strength)
        currentMaterial.ambientColor = SIMD4(strength, strength, strength, 0)
    }

    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        ambientColor = SIMD3(r, g, b)
        currentMaterial.ambientColor = SIMD4(r, g, b, 0)
    }

    // MARK: - Material

    public func specular(_ color: Color) {
        currentMaterial.specularAndShininess = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.specularAndShininess.w
        )
    }

    public func specular(_ gray: Float) {
        currentMaterial.specularAndShininess = SIMD4(
            gray, gray, gray,
            currentMaterial.specularAndShininess.w
        )
    }

    public func shininess(_ value: Float) {
        currentMaterial.specularAndShininess.w = value
    }

    public func emissive(_ color: Color) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    public func emissive(_ gray: Float) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            gray, gray, gray,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    public func metallic(_ value: Float) {
        currentMaterial.emissiveAndMetallic.w = value
    }

    // MARK: - Texture

    public func texture(_ img: MImage) {
        currentTexture = img.texture
    }

    public func noTexture() {
        currentTexture = nil
    }

    // MARK: - Transform Stack

    public func pushMatrix() { transformStack.append(currentTransform) }
    public func popMatrix() { if let s = transformStack.popLast() { currentTransform = s } }
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(translation: SIMD3(x, y, z))
    }
    public func rotateX(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationX: angle) }
    public func rotateY(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationY: angle) }
    public func rotateZ(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationZ: angle) }
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(scale: SIMD3(x, y, z))
    }
    public func scale(_ s: Float) { currentTransform = currentTransform * float4x4(scale: s) }

    // MARK: - Style

    public func fill(_ color: Color) { fillColor = color.simd }
    public func fill(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) { fillColor = SIMD4(r, g, b, a) }

    // MARK: - 3D Shapes

    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        let key = "box_\(width)_\(height)_\(depth)"
        let mesh = meshCache[key] ?? { let m = Mesh.box(device: device, width: width, height: height, depth: depth); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func box(_ size: Float) { box(size, size, size) }

    public func sphere(_ radius: Float, detail: Int = 24) {
        let rings = max(detail / 2, 4)
        let key = "sphere_\(radius)_\(detail)_\(rings)"
        let mesh = meshCache[key] ?? { let m = Mesh.sphere(device: device, radius: radius, segments: detail, rings: rings); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func plane(_ width: Float, _ height: Float) {
        let key = "plane_\(width)_\(height)"
        let mesh = meshCache[key] ?? { let m = Mesh.plane(device: device, width: width, height: height); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cylinder_\(radius)_\(height)_\(detail)"
        let mesh = meshCache[key] ?? { let m = Mesh.cylinder(device: device, radius: radius, height: height, segments: detail); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cone_\(radius)_\(height)_\(detail)"
        let mesh = meshCache[key] ?? { let m = Mesh.cone(device: device, radius: radius, height: height, segments: detail); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        let tubeDetail = max(detail / 2, 8)
        let key = "torus_\(ringRadius)_\(tubeRadius)_\(detail)_\(tubeDetail)"
        let mesh = meshCache[key] ?? { let m = Mesh.torus(device: device, ringRadius: ringRadius, tubeRadius: tubeRadius, segments: detail, tubeSegments: tubeDetail); meshCache[key] = m; return m }()
        drawMesh(mesh)
    }

    public func mesh(_ mesh: Mesh) { drawMesh(mesh) }

    // MARK: - Internal Drawing

    private func drawMesh(_ mesh: Mesh) {
        guard let encoder = encoder else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        encoder.setRenderPipelineState(isTextured ? texturedPipelineState : pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

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

        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // setVertexBytes/setFragmentBytes でデータをコマンドバッファにコピー
        // （共有バッファを上書きすると、同一エンコーダ内の複数draw間でデータが壊れる）
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

    // MARK: - Private Helpers

    private func computeViewProjection() -> float4x4 {
        if viewProjectionDirty {
            let aspect = width / height
            let view = float4x4(lookAt: cameraEye, center: cameraCenter, up: cameraUp)
            let proj = float4x4(perspectiveFov: fov, aspect: aspect, near: nearPlane, far: farPlane)
            cachedViewProjection = proj * view
            viewProjectionDirty = false
        }
        return cachedViewProjection
    }

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

    private func ensureAmbientIfFirstLight() {
        if lightArray.isEmpty {
            ambientColor = SIMD3(0.3, 0.3, 0.3)
            currentMaterial.ambientColor = SIMD4(0.3, 0.3, 0.3, 0)
        }
    }
}

// MARK: - Errors

public enum Canvas3DError: Error {
    case bufferCreationFailed
}
