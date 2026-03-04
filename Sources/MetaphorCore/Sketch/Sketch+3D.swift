// MARK: - 3D Drawing (Camera, Lighting, Material, Shapes, Transform)

extension Sketch {

    // MARK: 3D Custom Shapes

    /// Begin recording vertices for a 3D custom shape.
    ///
    /// - Parameter mode: The shape mode (e.g., polygon, triangles, lines).
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        _context?.beginShape3D(mode)
    }

    /// Add a 3D vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        _context?.vertex(x, y, z)
    }

    /// Add a 3D vertex with a per-vertex color to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        _context?.vertex(x, y, z, color)
    }

    /// Set the normal vector for subsequent 3D vertices.
    ///
    /// - Parameters:
    ///   - nx: The x-component of the normal.
    ///   - ny: The y-component of the normal.
    ///   - nz: The z-component of the normal.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        _context?.normal(nx, ny, nz)
    }

    /// Finish recording the current 3D shape and draw it.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape3D(_ close: CloseMode = .open) {
        _context?.endShape3D(close)
    }

    // MARK: 3D Camera

    /// Set the 3D camera using eye, center, and up vectors.
    ///
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector.
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        _context?.camera(eye: eye, center: center, up: up)
    }

    /// Set the 3D camera using individual float components.
    ///
    /// - Parameters:
    ///   - eyeX: The x-coordinate of the camera position.
    ///   - eyeY: The y-coordinate of the camera position.
    ///   - eyeZ: The z-coordinate of the camera position.
    ///   - centerX: The x-coordinate of the look-at target.
    ///   - centerY: The y-coordinate of the look-at target.
    ///   - centerZ: The z-coordinate of the look-at target.
    ///   - upX: The x-component of the up vector.
    ///   - upY: The y-component of the up vector.
    ///   - upZ: The z-component of the up vector.
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        _context?.camera(eyeX, eyeY, eyeZ, centerX, centerY, centerZ, upX, upY, upZ)
    }

    /// Set the perspective projection.
    ///
    /// - Parameters:
    ///   - fov: The field of view angle in radians.
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        _context?.perspective(fov: fov, near: near, far: far)
    }

    /// Set the orthographic projection.
    ///
    /// - Parameters:
    ///   - left: The left clipping plane (defaults to canvas bounds).
    ///   - right: The right clipping plane (defaults to canvas bounds).
    ///   - bottom: The bottom clipping plane (defaults to canvas bounds).
    ///   - top: The top clipping plane (defaults to canvas bounds).
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        _context?.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    /// Enable default lighting (a directional light and ambient light).
    public func lights() {
        _context?.lights()
    }

    /// Disable all lights.
    public func noLights() {
        _context?.noLights()
    }

    /// Add a directional light with the default color.
    ///
    /// - Parameters:
    ///   - x: The x-component of the light direction.
    ///   - y: The y-component of the light direction.
    ///   - z: The z-component of the light direction.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        _context?.directionalLight(x, y, z)
    }

    /// Add a directional light with a specified color.
    ///
    /// - Parameters:
    ///   - x: The x-component of the light direction.
    ///   - y: The y-component of the light direction.
    ///   - z: The z-component of the light direction.
    ///   - color: The light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        _context?.directionalLight(x, y, z, color: color)
    }

    /// Add a point light at the specified position.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the light position.
    ///   - y: The y-coordinate of the light position.
    ///   - z: The z-coordinate of the light position.
    ///   - color: The light color.
    ///   - falloff: The attenuation factor.
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        _context?.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// Add a spot light at the specified position pointing in the given direction.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the light position.
    ///   - y: The y-coordinate of the light position.
    ///   - z: The z-coordinate of the light position.
    ///   - dirX: The x-component of the light direction.
    ///   - dirY: The y-component of the light direction.
    ///   - dirZ: The z-component of the light direction.
    ///   - angle: The cone angle in radians.
    ///   - falloff: The attenuation factor.
    ///   - color: The light color.
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        _context?.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// Set the ambient light intensity using a single grayscale value.
    ///
    /// - Parameter strength: The ambient light strength.
    public func ambientLight(_ strength: Float) {
        _context?.ambientLight(strength)
    }

    /// Set the ambient light color using RGB values.
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        _context?.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// Enable shadow mapping.
    ///
    /// - Parameter resolution: The shadow map resolution in pixels.
    public func enableShadows(resolution: Int = 2048) {
        _context?.enableShadows(resolution: resolution)
    }

    /// Disable shadow mapping.
    public func disableShadows() {
        _context?.disableShadows()
    }

    /// Set the shadow depth bias to reduce shadow acne.
    ///
    /// - Parameter value: The bias value.
    public func shadowBias(_ value: Float) {
        _context?.shadowBias(value)
    }

    // MARK: 3D Material

    /// Set the specular highlight color.
    ///
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        _context?.specular(color)
    }

    /// Set the specular highlight color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func specular(_ gray: Float) {
        _context?.specular(gray)
    }

    /// Set the specular shininess exponent.
    ///
    /// - Parameter value: The shininess value (higher values produce smaller highlights).
    public func shininess(_ value: Float) {
        _context?.shininess(value)
    }

    /// Set the emissive (self-illumination) color.
    ///
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        _context?.emissive(color)
    }

    /// Set the emissive color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func emissive(_ gray: Float) {
        _context?.emissive(gray)
    }

    /// Set the metallic factor for the material.
    ///
    /// - Parameter value: The metallic value (0 = dielectric, 1 = metal).
    public func metallic(_ value: Float) {
        _context?.metallic(value)
    }

    /// Set the PBR roughness (automatically enables PBR mode).
    ///
    /// - Parameter value: The roughness value (0 = smooth, 1 = rough).
    public func roughness(_ value: Float) {
        _context?.roughness(value)
    }

    /// Set the PBR ambient occlusion factor.
    ///
    /// - Parameter value: The ambient occlusion value (0 = fully occluded, 1 = none).
    public func ambientOcclusion(_ value: Float) {
        _context?.ambientOcclusion(value)
    }

    /// Toggle PBR rendering mode explicitly.
    ///
    /// - Parameter enabled: Whether to enable PBR rendering.
    public func pbr(_ enabled: Bool) {
        _context?.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// Create a custom shader material from MSL source code.
    ///
    /// - Parameters:
    ///   - source: The Metal Shading Language source code.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The optional name of a custom vertex function.
    /// - Returns: A new ``CustomMaterial`` instance.
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterial(source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// Apply a custom material to subsequent 3D draws.
    ///
    /// - Parameter customMaterial: The custom material to apply.
    public func material(_ customMaterial: CustomMaterial) {
        _context?.material(customMaterial)
    }

    /// Remove the active custom material and return to the default shading.
    public func noMaterial() {
        _context?.noMaterial()
    }

    // MARK: 3D Texture

    /// Set the texture for subsequent 3D shapes.
    ///
    /// - Parameter img: The texture image.
    public func texture(_ img: MImage) {
        _context?.texture(img)
    }

    /// Remove the active texture.
    public func noTexture() {
        _context?.noTexture()
    }

    // MARK: 3D Transform Stack

    /// Save the current 3D transformation matrix onto the stack.
    public func pushMatrix() {
        _context?.pushMatrix()
    }

    /// Restore the most recently saved 3D transformation matrix from the stack.
    public func popMatrix() {
        _context?.popMatrix()
    }

    /// Apply a 3D translation to the current transform.
    ///
    /// - Parameters:
    ///   - x: The translation along the x-axis.
    ///   - y: The translation along the y-axis.
    ///   - z: The translation along the z-axis.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        _context?.translate(x, y, z)
    }

    /// Apply a rotation around the x-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) {
        _context?.rotateX(angle)
    }

    /// Apply a rotation around the y-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) {
        _context?.rotateY(angle)
    }

    /// Apply a rotation around the z-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) {
        _context?.rotateZ(angle)
    }

    /// Apply a non-uniform 3D scale to the current transform.
    ///
    /// - Parameters:
    ///   - x: The scale factor along the x-axis.
    ///   - y: The scale factor along the y-axis.
    ///   - z: The scale factor along the z-axis.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        _context?.scale(x, y, z)
    }

    // MARK: 3D Shapes

    /// Draw a box with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The width of the box.
    ///   - height: The height of the box.
    ///   - depth: The depth of the box.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        _context?.box(width, height, depth)
    }

    /// Draw a cube with equal side lengths.
    ///
    /// - Parameter size: The side length.
    public func box(_ size: Float) {
        _context?.box(size)
    }

    /// Draw a sphere.
    ///
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - detail: The number of subdivisions for mesh tessellation.
    public func sphere(_ radius: Float, detail: Int = 24) {
        _context?.sphere(radius, detail: detail)
    }

    /// Draw a flat plane.
    ///
    /// - Parameters:
    ///   - width: The plane width.
    ///   - height: The plane height.
    public func plane(_ width: Float, _ height: Float) {
        _context?.plane(width, height)
    }

    /// Draw a cylinder.
    ///
    /// - Parameters:
    ///   - radius: The cylinder radius.
    ///   - height: The cylinder height.
    ///   - detail: The number of subdivisions around the circumference.
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _context?.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draw a cone.
    ///
    /// - Parameters:
    ///   - radius: The base radius.
    ///   - height: The cone height.
    ///   - detail: The number of subdivisions around the circumference.
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _context?.cone(radius: radius, height: height, detail: detail)
    }

    /// Draw a torus (donut shape).
    ///
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The number of subdivisions.
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        _context?.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draw a prebuilt mesh.
    ///
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) {
        _context?.mesh(mesh)
    }

    /// Draw a dynamic mesh.
    ///
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        _context?.dynamicMesh(mesh)
    }

    /// Create a new empty dynamic mesh.
    ///
    /// - Returns: A new ``DynamicMesh`` instance.
    public func createDynamicMesh() throws -> DynamicMesh {
        try activeContext().createDynamicMesh()
    }

    /// Load a 3D model from a file (OBJ, USDZ, ABC).
    ///
    /// - Parameter path: The file path to the model.
    /// - Returns: The loaded mesh, or `nil` if loading fails.
    public func loadModel(_ path: String) -> Mesh? {
        _context?.loadModel(path)
    }
}
