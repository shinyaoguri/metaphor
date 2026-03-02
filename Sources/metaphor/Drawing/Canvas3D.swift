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
    private let shaderLibrary: ShaderLibrary
    private let sampleCount: Int
    private let pipelineState: MTLRenderPipelineState
    private let texturedPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState?

    private static let maxLights = 8

    // MARK: - Custom Material State

    private var currentCustomMaterial: CustomMaterial?
    private var customPipelineCache: [String: MTLRenderPipelineState] = [:]

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
        self.shaderLibrary = shaderLibrary
        self.sampleCount = sampleCount
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
        self.stateStack.removeAll(keepingCapacity: true)
        self.fillColor = SIMD4(1, 1, 1, 1)
        self.hasFill = true
        self.hasStroke3D = false
        self.strokeColor3D = SIMD4(1, 1, 1, 1)
        self.lightArray.removeAll(keepingCapacity: true)
        self.ambientColor = SIMD3(0.2, 0.2, 0.2)
        self.currentMaterial = .default
        self.currentTexture = nil
        self.currentCustomMaterial = nil

        let defaultZ = (height / 2) / tan(fov / 2)
        self.cameraEye = SIMD3(0, 0, defaultZ)
        self.cameraCenter = .zero
        self.cameraUp = SIMD3(0, 1, 0)
        self.viewProjectionDirty = true
        self.useOrthographic = false
    }

    func end() {
        self.encoder = nil
    }

    // MARK: - Public Camera Accessors

    /// 現在のビュー・プロジェクション行列
    public var currentViewProjection: float4x4 {
        computeViewProjection()
    }

    /// カメラの右方向ベクトル（ビルボード用）
    public var currentCameraRight: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        return normalize(cross(cameraUp, z))
    }

    /// カメラの上方向ベクトル（ビルボード用）
    public var currentCameraUp: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        let x = normalize(cross(cameraUp, z))
        return cross(z, x)
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
        self.useOrthographic = false
        self.viewProjectionDirty = true
    }

    /// 正射影カメラに切り替え
    /// - Parameters:
    ///   - left: 左端（nilならば0）
    ///   - right: 右端（nilならばwidth）
    ///   - bottom: 下端（nilならばheight）
    ///   - top: 上端（nilならば0）
    ///   - near: ニアクリップ
    ///   - far: ファークリップ
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

    // MARK: - Custom Material

    /// カスタムフラグメントシェーダーマテリアルを適用
    public func material(_ custom: CustomMaterial) {
        currentCustomMaterial = custom
    }

    /// カスタムマテリアルを解除（組み込みシェーダーに戻す）
    public func noMaterial() {
        currentCustomMaterial = nil
    }

    // MARK: - Texture

    public func texture(_ img: MImage) {
        currentTexture = img.texture
    }

    public func noTexture() {
        currentTexture = nil
    }

    // MARK: - Transform Stack

    /// 全状態を保存（トランスフォーム + スタイル + マテリアル）
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

    /// 全状態を復元
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

    /// トランスフォームのみを保存
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// トランスフォームのみを復元
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }
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

    public func fill(_ color: Color) { fillColor = color.simd; hasFill = true }

    /// 塗りつぶし色を設定（colorModeに従って解釈）
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasFill = true
    }

    /// グレースケールで塗りつぶし色を設定
    public func fill(_ gray: Float) {
        fillColor = colorModeConfig.toGray(gray).simd
        hasFill = true
    }

    /// グレースケール＋アルファで塗りつぶし色を設定
    public func fill(_ gray: Float, _ alpha: Float) {
        fillColor = colorModeConfig.toGray(gray, alpha).simd
        hasFill = true
    }

    /// 塗りつぶしなし
    public func noFill() { hasFill = false }

    /// 線の色を設定
    public func stroke(_ color: Color) { strokeColor3D = color.simd; hasStroke3D = true }

    /// 線の色を設定（colorModeに従って解釈）
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        strokeColor3D = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasStroke3D = true
    }

    /// グレースケールで線の色を設定
    public func stroke(_ gray: Float) {
        strokeColor3D = colorModeConfig.toGray(gray).simd
        hasStroke3D = true
    }

    /// グレースケール＋アルファで線の色を設定
    public func stroke(_ gray: Float, _ alpha: Float) {
        strokeColor3D = colorModeConfig.toGray(gray, alpha).simd
        hasStroke3D = true
    }

    /// 線なし
    public func noStroke() { hasStroke3D = false }

    /// 色空間と最大値を設定
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        colorModeConfig = ColorModeConfig(space: space, max1: max1, max2: max2, max3: max3, maxAlpha: maxA)
    }

    /// 色空間と均一な最大値を設定
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        colorModeConfig = ColorModeConfig(space: space, max1: maxAll, max2: maxAll, max3: maxAll, maxAlpha: maxAll)
    }

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

    /// 動的メッシュを描画
    public func dynamicMesh(_ mesh: DynamicMesh) {
        mesh.ensureBuffers()
        guard let encoder = encoder,
              let vb = mesh.vertexBuffer else { return }
        guard hasFill || hasStroke3D else { return }

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

    /// 3D頂点ベースの形状記録を開始
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape3D = true
        shapeMode3D = mode
        shapeVertices3D.removeAll(keepingCapacity: true)
        pendingNormal = nil
    }

    /// 3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: fillColor
        ))
    }

    /// 頂点カラー付き3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: color.simd
        ))
    }

    /// 次の vertex に適用する法線を設定
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal = SIMD3(nx, ny, nz)
    }

    /// 3D形状記録を終了して描画
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape3D else { return }
        isRecordingShape3D = false

        guard !shapeVertices3D.isEmpty else { return }

        // 自動法線計算（polygon/triangles モードで法線未設定の場合）
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

    private func autoComputeNormals() {
        // triangles モード: 3頂点ずつフェイス法線を計算
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

    private func drawShape3DVertices(_ vertices: [Vertex3D]) {
        guard let encoder = encoder, !vertices.isEmpty else { return }
        guard hasFill || hasStroke3D else { return }

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

    private func drawShape3DPolygon(close: CloseMode) {
        guard shapeVertices3D.count >= 3 else { return }

        // 簡易三角形ファン分割（凸多角形向け）
        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        // フェイス法線を最初の3頂点から計算
        let p0 = shapeVertices3D[0].position
        let p1 = shapeVertices3D[1].position
        let p2 = shapeVertices3D[2].position
        let faceNormal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
        let safeNormal = faceNormal.x.isNaN ? SIMD3<Float>(0, 1, 0) : faceNormal

        for i in 1..<(shapeVertices3D.count - 1) {
            var v0 = shapeVertices3D[0]
            var v1 = shapeVertices3D[i]
            var v2 = shapeVertices3D[i + 1]
            // 法線未設定頂点にはフェイス法線を適用
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

    private func drawShape3DTriangles() {
        // 3頂点ずつそのまま描画
        let count = (shapeVertices3D.count / 3) * 3
        guard count >= 3 else { return }
        drawShape3DVertices(Array(shapeVertices3D.prefix(count)))
    }

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

    private func drawShape3DPoints() {
        // 各頂点を小さな十字として描画（簡易実装）
        // 3Dの点は三角形として描画が必要なため、極小三角形に変換
        guard let encoder = encoder else { return }
        guard !shapeVertices3D.isEmpty else { return }

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        for v in shapeVertices3D {
            let s: Float = 0.5
            let verts = [
                Vertex3D(position: v.position + SIMD3(-s, -s, 0), normal: v.normal, color: v.color),
                Vertex3D(position: v.position + SIMD3( s, -s, 0), normal: v.normal, color: v.color),
                Vertex3D(position: v.position + SIMD3( 0,  s, 0), normal: v.normal, color: v.color),
            ]

            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: v.color,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setVertexBytes(verts, length: MemoryLayout<Vertex3D>.stride * 3, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    private func drawShape3DLines() {
        // 2頂点ずつ極細の三角形ペアで線を表現
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

            // カメラ方向とラインの外積でオフセットを計算
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

    private func drawMesh(_ mesh: Mesh) {
        guard let encoder = encoder else { return }
        guard hasFill || hasStroke3D else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        // カスタムマテリアルが設定されている場合はカスタムパイプラインを使用
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

            // カスタムマテリアルのパラメータをbuffer(4)にバインド
            if let customMat = currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
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

            // ワイヤフレームはライティングなし・テクスチャなしで描画
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

            // ワイヤフレームは常にuntexturedパイプラインを使用
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

    /// カスタムパイプラインキャッシュをクリア（シェーダーホットリロード時に呼ぶ）
    public func clearCustomPipelineCache() {
        customPipelineCache.removeAll()
    }

    /// カスタムシェーダー用パイプラインを取得（キャッシュ付き）
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
