import Metal
import simd

/// Provide a 3D offscreen drawing buffer (used by `createGraphics3D()`).
///
/// Owns an independent Canvas3D and can draw 3D content separately from the main canvas.
/// The result can be extracted as an MImage and rendered onto the main canvas with `image()`.
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

    /// Return the width in pixels.
    public var width: Float { canvas3D.width }

    /// Return the height in pixels.
    public var height: Float { canvas3D.height }

    /// Return the internal color texture.
    public var texture: MTLTexture { textureManager.colorTexture }

    // MARK: - Initialization

    init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Int,
        height: Int
    ) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        self.commandQueue = queue
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
    }

    // MARK: - Draw Lifecycle

    /// Begin drawing with an optional time value for animations.
    /// - Parameter time: The elapsed time passed to Canvas3D.
    public func beginDraw(time: Float = 0) {
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        self.commandBuffer = cb
        self.drawTime = time

        guard let enc = cb.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else {
            cb.commit()
            self.commandBuffer = nil
            return
        }
        self.encoder = enc
        canvas3D.begin(encoder: enc, time: time)
    }

    /// End drawing and wait for GPU completion.
    public func endDraw() {
        canvas3D.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// Return the offscreen texture as an MImage.
    /// - Returns: An MImage wrapping the internal color texture.
    public func toImage() -> MImage {
        MImage(texture: textureManager.colorTexture)
    }

    // MARK: - Camera

    /// Set the camera position and orientation.
    /// - Parameters:
    ///   - eye: Camera position.
    ///   - center: Look-at target.
    ///   - up: Up direction vector.
    public func camera(
        eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) { canvas3D.camera(eye: eye, center: center, up: up) }

    /// Set the perspective projection.
    /// - Parameters:
    ///   - fov: Field of view in radians.
    ///   - near: Near clipping plane distance.
    ///   - far: Far clipping plane distance.
    public func perspective(
        fov: Float = .pi / 3, near: Float = 0.1, far: Float = 10000
    ) { canvas3D.perspective(fov: fov, near: near, far: far) }

    /// Set the orthographic projection.
    /// - Parameters:
    ///   - left: Left clipping plane.
    ///   - right: Right clipping plane.
    ///   - bottom: Bottom clipping plane.
    ///   - top: Top clipping plane.
    ///   - near: Near clipping plane distance.
    ///   - far: Far clipping plane distance.
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -10, far: Float = 10000
    ) { canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far) }

    // MARK: - Lighting

    /// Enable default lighting.
    public func lights() { canvas3D.lights() }

    /// Disable all lighting.
    public func noLights() { canvas3D.noLights() }

    /// Add a directional light with the given direction.
    /// - Parameters:
    ///   - x: Light direction X component.
    ///   - y: Light direction Y component.
    ///   - z: Light direction Z component.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// Add a directional light with the given direction and color.
    /// - Parameters:
    ///   - x: Light direction X component.
    ///   - y: Light direction Y component.
    ///   - z: Light direction Z component.
    ///   - color: Light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// Add a point light at the given position.
    /// - Parameters:
    ///   - x: Light position X.
    ///   - y: Light position Y.
    ///   - z: Light position Z.
    ///   - color: Light color.
    ///   - falloff: Attenuation factor.
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white, falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// Add a spot light at the given position aiming in the given direction.
    /// - Parameters:
    ///   - x: Light position X.
    ///   - y: Light position Y.
    ///   - z: Light position Z.
    ///   - dirX: Direction X component.
    ///   - dirY: Direction Y component.
    ///   - dirZ: Direction Z component.
    ///   - angle: Cone half-angle in radians.
    ///   - falloff: Attenuation factor.
    ///   - color: Light color.
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = .pi / 6, falloff: Float = 0.01, color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// Set the ambient light strength.
    /// - Parameter strength: Ambient light intensity.
    public func ambientLight(_ strength: Float) { canvas3D.ambientLight(strength) }

    /// Set the ambient light color using RGB values.
    /// - Parameters:
    ///   - r: Red component.
    ///   - g: Green component.
    ///   - b: Blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) { canvas3D.ambientLight(r, g, b) }

    // MARK: - Material

    /// Set the specular highlight color.
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) { canvas3D.specular(color) }

    /// Set the specular highlight to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func specular(_ gray: Float) { canvas3D.specular(gray) }

    /// Set the shininess exponent for specular highlights.
    /// - Parameter value: The shininess exponent.
    public func shininess(_ value: Float) { canvas3D.shininess(value) }

    /// Set the emissive color.
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) { canvas3D.emissive(color) }

    /// Set the emissive to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func emissive(_ gray: Float) { canvas3D.emissive(gray) }

    /// Set the metallic factor for PBR shading.
    /// - Parameter value: Metallic factor (0.0 to 1.0).
    public func metallic(_ value: Float) { canvas3D.metallic(value) }

    /// Set the roughness factor for PBR shading.
    /// - Parameter value: Roughness factor (0.0 to 1.0).
    public func roughness(_ value: Float) { canvas3D.roughness(value) }

    /// Set the ambient occlusion factor for PBR shading.
    /// - Parameter value: Ambient occlusion factor (0.0 to 1.0).
    public func ambientOcclusion(_ value: Float) { canvas3D.ambientOcclusion(value) }

    /// Enable or disable PBR shading.
    /// - Parameter enabled: Whether to use PBR shading.
    public func pbr(_ enabled: Bool) { canvas3D.pbr(enabled) }

    /// Set a custom material for subsequent draw calls.
    /// - Parameter custom: The custom material to apply.
    public func material(_ custom: CustomMaterial) { canvas3D.material(custom) }

    /// Reset to the default material.
    public func noMaterial() { canvas3D.noMaterial() }

    // MARK: - Texture

    /// Set the texture for subsequent 3D primitives.
    /// - Parameter img: The image to use as a texture.
    public func texture(_ img: MImage) { canvas3D.texture(img) }

    /// Disable texturing.
    public func noTexture() { canvas3D.noTexture() }

    // MARK: - Transform

    /// Push the current model matrix onto the stack.
    public func pushMatrix() { canvas3D.pushMatrix() }

    /// Pop the most recent model matrix from the stack.
    public func popMatrix() { canvas3D.popMatrix() }

    /// Translate the model matrix.
    /// - Parameters:
    ///   - x: X translation.
    ///   - y: Y translation.
    ///   - z: Z translation.
    public func translate(_ x: Float, _ y: Float, _ z: Float) { canvas3D.translate(x, y, z) }

    /// Rotate around the X axis.
    /// - Parameter angle: Rotation angle in radians.
    public func rotateX(_ angle: Float) { canvas3D.rotateX(angle) }

    /// Rotate around the Y axis.
    /// - Parameter angle: Rotation angle in radians.
    public func rotateY(_ angle: Float) { canvas3D.rotateY(angle) }

    /// Rotate around the Z axis.
    /// - Parameter angle: Rotation angle in radians.
    public func rotateZ(_ angle: Float) { canvas3D.rotateZ(angle) }

    /// Scale the model matrix by individual axis factors.
    /// - Parameters:
    ///   - x: X scale factor.
    ///   - y: Y scale factor.
    ///   - z: Z scale factor.
    public func scale(_ x: Float, _ y: Float, _ z: Float) { canvas3D.scale(x, y, z) }

    /// Scale the model matrix uniformly.
    /// - Parameter s: Uniform scale factor.
    public func scale(_ s: Float) { canvas3D.scale(s) }

    // MARK: - Style

    /// Set the fill color.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) { canvas3D.fill(color) }

    /// Set the fill color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.fill(v1, v2, v3, a) }

    /// Set the fill to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func fill(_ gray: Float) { canvas3D.fill(gray) }

    /// Set the fill to a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) { canvas3D.fill(gray, alpha) }

    /// Disable filling shapes.
    public func noFill() { canvas3D.noFill() }

    /// Set the stroke color.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) { canvas3D.stroke(color) }

    /// Set the stroke color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.stroke(v1, v2, v3, a) }

    /// Set the stroke to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func stroke(_ gray: Float) { canvas3D.stroke(gray) }

    /// Set the stroke to a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) { canvas3D.stroke(gray, alpha) }

    /// Disable stroking shapes.
    public func noStroke() { canvas3D.noStroke() }

    /// Set the color mode and optional maximum channel values.
    /// - Parameters:
    ///   - space: The color space (RGB or HSB).
    ///   - max1: Maximum value for the first channel.
    ///   - max2: Maximum value for the second channel.
    ///   - max3: Maximum value for the third channel.
    ///   - maxA: Maximum value for the alpha channel.
    public func colorMode(
        _ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0,
        _ max3: Float = 1.0, _ maxA: Float = 1.0
    ) { canvas3D.colorMode(space, max1, max2, max3, maxA) }

    /// Set the color mode with a uniform maximum for all channels.
    /// - Parameters:
    ///   - space: The color space.
    ///   - maxAll: Maximum value applied to all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas3D.colorMode(space, maxAll) }

    // MARK: - Primitives

    /// Draw a box with individual dimensions.
    /// - Parameters:
    ///   - width: Box width.
    ///   - height: Box height.
    ///   - depth: Box depth.
    public func box(_ width: Float, _ height: Float, _ depth: Float) { canvas3D.box(width, height, depth) }

    /// Draw a cube with uniform size.
    /// - Parameter size: Side length.
    public func box(_ size: Float) { canvas3D.box(size) }

    /// Draw a sphere.
    /// - Parameters:
    ///   - radius: Sphere radius.
    ///   - detail: Tessellation detail level.
    public func sphere(_ radius: Float, detail: Int = 24) { canvas3D.sphere(radius, detail: detail) }

    /// Draw a plane.
    /// - Parameters:
    ///   - width: Plane width.
    ///   - height: Plane height.
    public func plane(_ width: Float, _ height: Float) { canvas3D.plane(width, height) }

    /// Draw a cylinder.
    /// - Parameters:
    ///   - radius: Cylinder radius.
    ///   - height: Cylinder height.
    ///   - detail: Tessellation detail level.
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cylinder(radius: radius, height: height, detail: detail) }

    /// Draw a cone.
    /// - Parameters:
    ///   - radius: Base radius.
    ///   - height: Cone height.
    ///   - detail: Tessellation detail level.
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cone(radius: radius, height: height, detail: detail) }

    /// Draw a torus.
    /// - Parameters:
    ///   - ringRadius: Distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: Radius of the tube.
    ///   - detail: Tessellation detail level.
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) { canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail) }

    /// Draw a custom mesh.
    /// - Parameter mesh: The mesh to render.
    public func mesh(_ mesh: Mesh) { canvas3D.mesh(mesh) }
}
