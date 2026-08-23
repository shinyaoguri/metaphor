import Metal
import simd

/// Provides a 3D offscreen drawing buffer (used through `createGraphics3D()`).
///
/// It owns an independent Canvas3D, so it draws 3D content separately from the main canvas.
/// The result is obtained as an MImage and can be drawn to the main canvas with `image()`.
///
/// ```swift
/// let pg3d = createGraphics3D(800, 600)
/// pg3d.beginDraw()
/// pg3d.lights()
/// pg3d.fill(.red)
/// pg3d.rotateY(time)
/// pg3d.box(200)
/// pg3d.endDraw()
/// image(pg3d, 0, 0)
/// ```
@MainActor
public final class Graphics3D {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureManager: TextureManager
    private let canvas3D: Canvas3D
    private var commandBuffer: MTLCommandBuffer?
    private var encoder: MTLRenderCommandEncoder?
    private var drawTime: Float = 0

    // メインレンダラーと同じトリプルバッファリング（Graphics と同様）。
    // 以前は常にスロット 0 を使っていたため、毎フレーム描画すると GPU が
    // まだ読んでいるインスタンスバッファを CPU が上書きし得た。
    private static let inflightCount = 3
    private let inflightSemaphore = DispatchSemaphore(value: inflightCount)
    private var bufferIndex = 0

    /// Copy-on-write rotation of the render target texture (#745).
    private let targetRotator: OffscreenTargetRotator

    /// The width in pixels.
    public var width: Float { canvas3D.width }

    /// The height in pixels.
    public var height: Float { canvas3D.height }

    /// The internal color texture.
    ///
    /// The contents of the returned texture are frozen at the next ``beginDraw(time:)``
    /// (drawing rotates to a different texture, so an image already placed with
    /// `image()` is never rewritten afterwards. #745).
    public var texture: MTLTexture {
        targetRotator.markHandedOut()
        return textureManager.colorTexture
    }

    // MARK: - Initialization

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Int,
        height: Int
    ) throws {
        self.device = device
        // renderer の commandQueue を共有することで、メインキャンバスから
        // pg3d.texture を読む際に commit-order 保証で自動同期される。
        self.commandQueue = commandQueue
        self.textureManager = try TextureManager(
            device: device, width: width, height: height, sampleCount: 1
        )
        self.canvas3D = try Canvas3D(
            device: device,
            shaderLibrary: shaderLibrary,
            depthStencilCache: depthStencilCache,
            width: Float(width),
            height: Float(height),
            sampleCount: 1
        )
        self.targetRotator = OffscreenTargetRotator(textureManager: textureManager)
    }

    /// Wires up the frame number used to decide when the render target texture can be
    /// reused (called from `SketchContext.createGraphics3D`).
    func wireFrameCount(_ provider: @escaping () -> UInt32) {
        targetRotator.frameCountProvider = provider
    }

    // MARK: - Draw Lifecycle

    /// Begins drawing for animation with an optional time value.
    /// - Parameter time: The elapsed time passed to Canvas3D.
    public func beginDraw(time: Float = 0) {
        // endDraw 漏れの不均衡呼び出しでもセマフォが詰まらないよう先に閉じる
        if commandBuffer != nil { endDraw() }

        // 前のパスの絵を外へ渡していたら、描き先を別のテクスチャへ回す（#745）
        targetRotator.rotateIfNeeded(commandQueue: commandQueue)

        // GPU が inflightCount フレーム以上遅れている場合はここでブロックし、
        // GPU がまだ読んでいるバッファスロットへの上書きを防ぐ
        inflightSemaphore.wait()
        guard let cb = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }
        let semaphore = inflightSemaphore
        cb.addCompletedHandler { @Sendable _ in semaphore.signal() }
        self.commandBuffer = cb
        self.drawTime = time

        guard
            let enc = cb.makeRenderCommandEncoder(
                descriptor: textureManager.renderPassDescriptor
            )
        else {
            // commit して completed handler を発火させ、セマフォを返す
            cb.commit()
            self.commandBuffer = nil
            return
        }
        self.encoder = enc
        canvas3D.begin(encoder: enc, time: time, bufferIndex: bufferIndex)
        bufferIndex = (bufferIndex + 1) % Self.inflightCount
    }

    /// Ends drawing.
    ///
    /// `Graphics3D` shares the same `MTLCommandQueue` as the renderer, so commit order
    /// automatically orders any subsequent read from the main canvas correctly.
    /// By default it therefore returns immediately, without waiting for the GPU.
    ///
    /// - Parameter wait: When `true`, waits explicitly for GPU completion with
    ///   `waitUntilCompleted()`. This is needed only when reading the texture contents
    ///   directly on the CPU (with `getBytes`, for example).
    ///   It is not needed for `loadPixels()` through the `MImage` that ``toImage()``
    ///   returns (the readback goes on the same queue, so commit order guarantees it).
    public func endDraw(wait: Bool = false) {
        canvas3D.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        if wait {
            commandBuffer?.waitUntilCompleted()
        }
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// Returns the offscreen texture as an MImage.
    ///
    /// Drawing it with `image()` paints **the contents that were visible at that moment**.
    /// The same buffer can be redrawn and placed any number of times within a single frame
    /// (each redraw rotates the render target to a different texture, so the number of
    /// internal textures grows by the number of redraws. #745).
    ///
    /// - Returns: An MImage wrapping the internal color texture.
    public func toImage() -> MImage {
        let image = MImage(texture: textureManager.colorTexture)
        // リードバックを描画と同じキューに載せ、endDraw(wait: false) 直後の
        // loadPixels でも commit 順序で最新内容が読めるようにする
        image.preferredReadbackQueue = commandQueue
        targetRotator.markHandedOut(image)
        return image
    }

    // MARK: - Background

    /// Repaints the backdrop (the background) with a solid color.
    ///
    /// **The background replaces rather than composites** (ADR-0012 / #829). A background
    /// color with alpha < 1 goes in as it is, without mixing with the backdrop, and
    /// `background(0, 0, 0, 0)` returns the backdrop to transparent. This is what lets a
    /// `Graphics3D` layer sit in the foreground of a `MergePass(.alpha)` (#830).
    ///
    /// The default backdrop is **opaque black**, matching ``Graphics`` (the 2D offscreen
    /// buffer). For a layer that should start out transparent, call
    /// `background(0, 0, 0, 0)` explicitly.
    ///
    /// Calling it between ``beginDraw(time:)`` and ``endDraw(wait:)`` **takes effect on
    /// that frame**. Calling it outside them takes effect from the next
    /// ``beginDraw(time:)``. `Graphics3D` clears the backdrop on every
    /// ``beginDraw(time:)``, and the background color that was set is kept on subsequent
    /// frames as well, so there is no need to call it again every frame.
    ///
    /// - Parameter color: The background color (straight alpha).
    public func background(_ color: Color) {
        let c = color.simd
        // キャンバスの中身は premultiplied（ADR-0012）。クリアはブレンドを通らず値を
        // そのまま書くので、ここで α を掛けてから渡す。
        textureManager.setClearColor(
            TextureManager.premultipliedClearColor(
                Double(c.x), Double(c.y), Double(c.z), Double(c.w)
            )
        )
        restartPassWithNewClearColor()
    }

    /// Fills the background with a grayscale value.
    ///
    /// As with `fill`, the value is **relative to the `colorMode` range** (0–255 by
    /// default).
    /// - Parameter gray: The grayscale brightness value.
    public func background(_ gray: Float) {
        background(canvas3D.colorModeConfig.toGray(gray))
    }

    /// Fills the background with color mode values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value. Interpreted according to the current color
    ///     mode.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        background(canvas3D.colorModeConfig.toColor(v1, v2, v3, a))
    }

    /// Discards the render pass that is currently open and reopens it with a new clear
    /// color.
    ///
    /// `Graphics3D` has no background-quad path like the 2D one: the backdrop is always
    /// produced by the render pass's `loadAction = .clear`. The clear color is **fixed at
    /// the moment the pass is opened**, so changing the color partway through a pass has
    /// no effect on that pass. Reopening here is what makes the straightforward form —
    /// writing `background()` after `beginDraw()`, the same as in the ``Graphics``
    /// example — take effect on that frame.
    ///
    /// The reopened pass clears both color and depth, so 3D drawn earlier does not survive
    /// — this is the 3D counterpart of "the background replaces rather than composites"
    /// (ADR-0012 / #829). Frame state such as the camera, the lights and the transforms is
    /// kept, because ``Canvas3D/begin(encoder:time:bufferIndex:)`` is not called again.
    ///
    /// Narrowing the condition to "did this pass draw anything?" would make the discarded
    /// pass avoidable, but that would mean going around marking every drawing path in
    /// Canvas3D, and a mark would be missed every time a path is added. The discarded pass
    /// only writes out the clear result once, so always reopening is the side taken here.
    private func restartPassWithNewClearColor() {
        guard let cb = commandBuffer, let enc = encoder else { return }
        // 保留中のインスタンスバッチは捨てるパスへ出し切る。持ち越すと
        // `background()` より前に積んだものが、後から描いたように現れてしまう。
        canvas3D.end()
        enc.endEncoding()
        encoder = nil
        guard
            let next = cb.makeRenderCommandEncoder(
                descriptor: textureManager.renderPassDescriptor
            )
        else { return }
        encoder = next
        canvas3D.rebindEncoder(next)
    }

    // MARK: - Camera

    /// Sets the position and orientation of the camera.
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - center: The point being looked at.
    ///   - up: The up vector.
    public func camera(
        eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) { canvas3D.camera(eye: eye, center: center, up: up) }

    /// Sets a perspective projection.
    /// - Parameters:
    ///   - fov: The field of view in radians.
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    public func perspective(
        fov: Float = .pi / 3, near: Float = 0.1, far: Float = 10000
    ) { canvas3D.perspective(fov: fov, near: near, far: far) }

    /// Sets an orthographic projection.
    ///
    /// Omitted planes are filled in with a range that meshes with the default camera
    /// (straddling the origin, which is the center of the screen). Of `bottom` and `top`,
    /// `bottom` is the side with the smaller y in view space (that is, the top edge of the
    /// screen).
    /// - Parameters:
    ///   - left: The left clipping plane (`-width / 2` when nil).
    ///   - right: The right clipping plane (`width / 2` when nil).
    ///   - bottom: The bottom clipping plane (`-height / 2` when nil).
    ///   - top: The top clipping plane (`height / 2` when nil).
    ///   - near: The distance to the near clipping plane (-10 times the default camera
    ///     distance when nil).
    ///   - far: The distance to the far clipping plane (10 times the default camera
    ///     distance when nil).
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float? = nil, far: Float? = nil
    ) { canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far) }

    // MARK: - Lighting

    /// Enables the default lighting.
    ///
    /// The ambient light is set to 30% of the `colorMode` range (equivalent to
    /// `ambientLight(76.5)` with the default range of 0–255).
    public func lights() { canvas3D.lights() }

    /// Disables all lighting.
    public func noLights() { canvas3D.noLights() }

    /// Adds a directional light with the given direction, color and intensity.
    /// - Parameters:
    ///   - x: The x component of the light direction.
    ///   - y: The y component of the light direction.
    ///   - z: The z component of the light direction.
    ///   - color: The color of the light (white by default).
    ///   - intensity: The intensity multiplier of the light (1.0 by default).
    public func directionalLight(
        _ x: Float, _ y: Float, _ z: Float, color: Color = .white, intensity: Float = 1.0
    ) {
        canvas3D.directionalLight(x, y, z, color: color, intensity: intensity)
    }

    /// Adds a point light at the given position.
    /// - Parameters:
    ///   - x: The x position of the light.
    ///   - y: The y position of the light.
    ///   - z: The z position of the light.
    ///   - color: The color of the light.
    ///   - falloff: The falloff factor.
    ///   - intensity: The intensity multiplier of the light (1.0 by default).
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white, falloff: Float = 0.1, intensity: Float = 1.0
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff, intensity: intensity)
    }

    /// Adds a spot light at the given position and direction.
    /// - Parameters:
    ///   - x: The x position of the light.
    ///   - y: The y position of the light.
    ///   - z: The z position of the light.
    ///   - dirX: The x component of the direction.
    ///   - dirY: The y component of the direction.
    ///   - dirZ: The z component of the direction.
    ///   - angle: The half angle of the cone in radians.
    ///   - falloff: The falloff factor.
    ///   - color: The color of the light.
    ///   - intensity: The intensity multiplier of the light (1.0 by default).
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = .pi / 6, falloff: Float = 0.01, color: Color = .white,
        intensity: Float = 1.0
    ) {
        canvas3D.spotLight(
            x, y, z, dirX, dirY, dirZ,
            angle: angle, falloff: falloff, color: color, intensity: intensity
        )
    }

    /// Sets the intensity of the ambient light.
    ///
    /// As with `fill`, the value is **relative to the `colorMode` range** (0–255 by
    /// default). A value meant as 0–1 (`ambientLight(0.35)`, for example) comes out almost
    /// completely dark. The default ambient light applied by `lights()` or by adding the
    /// first light is 30% of the range (`ambientLight(76.5)` with the default range).
    ///
    /// - Parameter strength: The intensity of the ambient light (relative to the
    ///   `colorMode` range).
    public func ambientLight(_ strength: Float) { canvas3D.ambientLight(strength) }

    /// Sets the color of the ambient light from RGB values.
    ///
    /// As with `fill`, the values are **relative to the `colorMode` range** (0–255 by
    /// default).
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) { canvas3D.ambientLight(r, g, b) }

    // MARK: - Material

    /// Sets the color of specular highlights.
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) { canvas3D.specular(color) }

    /// Sets the color of specular highlights from channel values.
    ///
    /// As with `fill` and the others, the values are **relative to the `colorMode` range**
    /// (0–255 by default).
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    public func specular(_ v1: Float, _ v2: Float, _ v3: Float) { canvas3D.specular(v1, v2, v3) }

    /// Sets specular highlights from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func specular(_ gray: Float) { canvas3D.specular(gray) }

    /// Sets the shininess exponent of specular highlights.
    /// - Parameter value: The shininess exponent.
    public func shininess(_ value: Float) { canvas3D.shininess(value) }

    /// Sets the emissive color.
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) { canvas3D.emissive(color) }

    /// Sets the emissive color from channel values.
    ///
    /// As with `fill` and the others, the values are **relative to the `colorMode` range**
    /// (0–255 by default).
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    public func emissive(_ v1: Float, _ v2: Float, _ v3: Float) { canvas3D.emissive(v1, v2, v3) }

    /// Sets the emissive color from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func emissive(_ gray: Float) { canvas3D.emissive(gray) }

    /// Sets the metallic factor for PBR shading.
    /// - Parameter value: The metallic factor (0.0 to 1.0).
    public func metallic(_ value: Float) { canvas3D.metallic(value) }

    /// Sets the roughness factor for PBR shading.
    /// - Parameter value: The roughness factor (0.0 to 1.0).
    public func roughness(_ value: Float) { canvas3D.roughness(value) }

    /// Sets the ambient occlusion factor for PBR shading.
    /// - Parameter value: The ambient occlusion factor (0.0 to 1.0).
    public func ambientOcclusion(_ value: Float) { canvas3D.ambientOcclusion(value) }

    /// Enables or disables PBR shading.
    /// - Parameter enabled: Whether to use PBR shading.
    public func pbr(_ enabled: Bool) { canvas3D.pbr(enabled) }

    /// Sets the tone mapping applied to the 3D lighting result.
    /// - Parameter mode: The tone mapping method.
    public func toneMapping(_ mode: ToneMapMode) { canvas3D.toneMapping(mode) }

    /// Sets the exposure multiplier applied before tone mapping.
    /// - Parameter value: The exposure multiplier (1.0 by default).
    public func exposure(_ value: Float) { canvas3D.exposure(value) }

    /// Sets the environment (IBL and the background skybox).
    /// - Parameters:
    ///   - preset: The environment preset.
    ///   - intensity: The intensity of the environment (1.0 by default). Values of 0 or
    ///     less disable it.
    ///   - background: When `true`, it is also drawn as the background.
    public func environment(
        _ preset: EnvironmentPreset,
        intensity: Float = 1.0,
        background: Bool = true
    ) {
        canvas3D.environment(preset, intensity: intensity, background: background)
    }

    /// Disables the environment (IBL and the skybox).
    public func noEnvironment() { canvas3D.noEnvironment() }

    /// Sets a custom material for subsequent draw calls.
    /// - Parameter custom: The custom material to apply.
    public func material(_ custom: CustomMaterial) { canvas3D.material(custom) }

    /// Resets to the default material.
    public func noMaterial() { canvas3D.noMaterial() }

    // MARK: - Texture

    /// Sets the texture for subsequent 3D primitives.
    /// - Parameter img: The image to use as the texture.
    public func texture(_ img: MImage) { canvas3D.texture(img) }

    /// Disables texturing.
    public func noTexture() { canvas3D.noTexture() }

    // MARK: - Transform

    /// Pushes the current model matrix onto the stack.
    public func pushMatrix() { canvas3D.pushMatrix() }

    /// Pops the most recently saved model matrix off the stack.
    public func popMatrix() { canvas3D.popMatrix() }

    /// Translates the model matrix.
    /// - Parameters:
    ///   - x: The amount of translation along x.
    ///   - y: The amount of translation along y.
    ///   - z: The amount of translation along z.
    public func translate(_ x: Float, _ y: Float, _ z: Float) { canvas3D.translate(x, y, z) }

    /// Rotates around the x axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) { canvas3D.rotateX(angle) }

    /// Rotates around the y axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) { canvas3D.rotateY(angle) }

    /// Rotates around the z axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) { canvas3D.rotateZ(angle) }

    /// Scales the model matrix by a factor per axis.
    /// - Parameters:
    ///   - x: The x scale factor.
    ///   - y: The y scale factor.
    ///   - z: The z scale factor.
    public func scale(_ x: Float, _ y: Float, _ z: Float) { canvas3D.scale(x, y, z) }

    /// Scales the model matrix uniformly.
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) { canvas3D.scale(s) }

    // MARK: - Style

    /// Sets the fill color.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) { canvas3D.fill(color) }

    /// Sets the fill color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas3D.fill(v1, v2, v3, a)
    }

    /// Sets the fill from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func fill(_ gray: Float) { canvas3D.fill(gray) }

    /// Sets the fill from a grayscale value and an alpha value.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) { canvas3D.fill(gray, alpha) }

    /// Disables filling of shapes.
    public func noFill() { canvas3D.noFill() }

    /// Sets the stroke color.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) { canvas3D.stroke(color) }

    /// Sets the stroke color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas3D.stroke(v1, v2, v3, a)
    }

    /// Sets the stroke from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func stroke(_ gray: Float) { canvas3D.stroke(gray) }

    /// Sets the stroke from a grayscale value and an alpha value.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) { canvas3D.stroke(gray, alpha) }

    /// Disables stroking of shapes.
    public func noStroke() { canvas3D.noStroke() }

    /// Sets the color mode and optional maximum channel values.
    /// - Parameters:
    ///   - space: The color space (RGB or HSB).
    ///   - max1: The maximum value of the first channel.
    ///   - max2: The maximum value of the second channel.
    ///   - max3: The maximum value of the third channel.
    ///   - maxA: The maximum value of the alpha channel.
    public func colorMode(
        _ space: ColorSpace, _ max1: Float? = nil, _ max2: Float? = nil,
        _ max3: Float? = nil, _ maxA: Float? = nil
    ) { canvas3D.colorMode(space, max1, max2, max3, maxA) }

    /// Sets the color mode with a uniform maximum value for all channels.
    /// - Parameters:
    ///   - space: The color space.
    ///   - maxAll: The maximum value applied to all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas3D.colorMode(space, maxAll)
    }

    // MARK: - Primitives

    /// Draws a box with individual dimensions.
    /// - Parameters:
    ///   - width: The width of the box.
    ///   - height: The height of the box.
    ///   - depth: The depth of the box.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        canvas3D.box(width, height, depth)
    }

    /// Draws a cube with a uniform size.
    /// - Parameter size: The side length.
    public func box(_ size: Float) { canvas3D.box(size) }

    /// Draws a sphere.
    /// - Parameters:
    ///   - radius: The radius of the sphere.
    ///   - detail: The level of tessellation detail.
    public func sphere(_ radius: Float, detail: Int = 24) {
        canvas3D.sphere(radius, detail: detail)
    }

    /// Draws a plane.
    /// - Parameters:
    ///   - width: The width of the plane.
    ///   - height: The height of the plane.
    public func plane(_ width: Float, _ height: Float) { canvas3D.plane(width, height) }

    /// Draws a cylinder.
    /// - Parameters:
    ///   - radius: The radius of the cylinder.
    ///   - height: The height of the cylinder.
    ///   - detail: The level of tessellation detail.
    public func cylinder(radius: Float, height: Float, detail: Int = 24) {
        canvas3D.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draws a cone.
    /// - Parameters:
    ///   - radius: The radius of the base.
    ///   - height: The height of the cone.
    ///   - detail: The level of tessellation detail.
    public func cone(radius: Float, height: Float, detail: Int = 24) {
        canvas3D.cone(radius: radius, height: height, detail: detail)
    }

    /// Draws a torus.
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The level of tessellation detail.
    public func torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24) {
        canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draws a custom mesh.
    /// - Parameter mesh: The mesh to render.
    public func mesh(_ mesh: Mesh) { canvas3D.mesh(mesh) }

    /// Draws the same mesh with multiple transforms in a single batch (explicit
    /// instancing).
    /// - Parameters:
    ///   - mesh: The mesh to draw.
    ///   - transforms: The local transform of each instance.
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4]) {
        canvas3D.drawInstanced(mesh, transforms: transforms)
    }

    /// Draws the same mesh in a single batch, with a fill color per instance.
    /// - Parameters:
    ///   - mesh: The mesh to draw.
    ///   - transforms: The local transform of each instance.
    ///   - colors: The fill color of each instance.
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4], colors: [Color]) {
        canvas3D.drawInstanced(mesh, transforms: transforms, colors: colors)
    }
}
