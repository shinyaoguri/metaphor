import Metal
import simd

extension SketchContext {

    // MARK: - 3D Custom Shapes (beginShape / endShape)

    /// Begins recording a 3D vertex-based custom shape.
    /// - Parameter mode: The shape drawing mode (default `.polygon`).
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        canvas3D.beginShape(mode)
    }

    /// Adds a 3D vertex to the current shape.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.vertex(x, y, z)
    }

    /// Adds a 3D vertex with a per-vertex color.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        canvas3D.vertex(x, y, z, color)
    }

    /// Sets the normal vector for the next 3D vertex.
    /// - Parameters:
    ///   - nx: The normal x-component.
    ///   - ny: The normal y-component.
    ///   - nz: The normal z-component.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        canvas3D.normal(nx, ny, nz)
    }

    /// Ends the 3D shape recording and draws the shape.
    /// - Parameter close: Whether to close the shape (default `.open`).
    public func endShape3D(_ close: CloseMode = .open) {
        canvas3D.endShape(close)
    }

    /// Draws a Catmull-Rom spline curve through four points.
    /// - Parameters:
    ///   - x1: The first guide point x-coordinate.
    ///   - y1: The first guide point y-coordinate.
    ///   - x2: The start of the visible curve x-coordinate.
    ///   - y2: The start of the visible curve y-coordinate.
    ///   - x3: The end of the visible curve x-coordinate.
    ///   - y3: The end of the visible curve y-coordinate.
    ///   - x4: The second guide point x-coordinate.
    ///   - y4: The second guide point y-coordinate.
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    // MARK: - 3D Camera

    /// Sets the camera position and orientation.
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector (default Y-up).
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        canvas3D.camera(eye: eye, center: center, up: up)
    }

    /// Sets the camera position and orientation using positional arguments (p5.js-style).
    /// - Parameters:
    ///   - eyeX: The camera x-position.
    ///   - eyeY: The camera y-position.
    ///   - eyeZ: The camera z-position.
    ///   - centerX: The look-at target x-coordinate.
    ///   - centerY: The look-at target y-coordinate.
    ///   - centerZ: The look-at target z-coordinate.
    ///   - upX: The up vector x-component.
    ///   - upY: The up vector y-component.
    ///   - upZ: The up vector z-component.
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        canvas3D.camera(
            eye: SIMD3(eyeX, eyeY, eyeZ),
            center: SIMD3(centerX, centerY, centerZ),
            up: SIMD3(upX, upY, upZ)
        )
    }

    /// Configures perspective projection.
    /// - Parameters:
    ///   - fov: The field of view in radians (default pi/3).
    ///   - near: The near clipping plane distance (default 0.1).
    ///   - far: The far clipping plane distance (default 10000).
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        canvas3D.perspective(fov: fov, near: near, far: far)
    }

    /// Switches to orthographic projection.
    /// - Parameters:
    ///   - left: The left clipping plane (nil uses canvas bounds).
    ///   - right: The right clipping plane (nil uses canvas bounds).
    ///   - bottom: The bottom clipping plane (nil uses canvas bounds).
    ///   - top: The top clipping plane (nil uses canvas bounds).
    ///   - near: The near clipping plane distance (default -1000).
    ///   - far: The far clipping plane distance (default 1000).
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: - 3D Lighting

    /// Enables default lighting.
    public func lights() {
        canvas3D.lights()
    }

    /// Removes all lights from the scene.
    public func noLights() {
        canvas3D.noLights()
    }

    /// Sets the direction of the directional light.
    /// - Parameters:
    ///   - x: The direction x-component.
    ///   - y: The direction y-component.
    ///   - z: The direction z-component.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// Sets the direction and color of the directional light.
    /// - Parameters:
    ///   - x: The direction x-component.
    ///   - y: The direction y-component.
    ///   - z: The direction z-component.
    ///   - color: The light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// Adds a point light to the scene.
    /// - Parameters:
    ///   - x: The light x-position.
    ///   - y: The light y-position.
    ///   - z: The light z-position.
    ///   - color: The light color (default white).
    ///   - falloff: The attenuation factor (default 0.1).
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// Adds a spot light to the scene.
    /// - Parameters:
    ///   - x: The light x-position.
    ///   - y: The light y-position.
    ///   - z: The light z-position.
    ///   - dirX: The spotlight direction x-component.
    ///   - dirY: The spotlight direction y-component.
    ///   - dirZ: The spotlight direction z-component.
    ///   - angle: The cone angle in radians (default pi/6).
    ///   - falloff: The attenuation factor (default 0.01).
    ///   - color: The light color (default white).
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// Sets the ambient light intensity.
    /// - Parameter strength: The ambient light strength.
    public func ambientLight(_ strength: Float) {
        canvas3D.ambientLight(strength)
    }

    /// Sets the ambient light color using RGB components.
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        canvas3D.ambientLight(r, g, b)
    }

    // MARK: - Shadow Mapping

    /// Enables shadow mapping.
    /// - Parameter resolution: The shadow map resolution in pixels (default 2048).
    public func enableShadows(resolution: Int = 2048) {
        if canvas3D.shadowMap == nil {
            canvas3D.shadowMap = try? ShadowMap(
                device: renderer.device,
                shaderLibrary: renderer.shaderLibrary,
                resolution: resolution
            )
        }
    }

    /// Disables shadow mapping.
    public func disableShadows() {
        canvas3D.shadowMap = nil
    }

    /// Sets the shadow bias to prevent shadow acne.
    /// - Parameter value: The bias value.
    public func shadowBias(_ value: Float) {
        canvas3D.shadowMap?.shadowBias = value
    }

    // MARK: - 3D Material

    /// Sets the specular highlight color.
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        canvas3D.specular(color)
    }

    /// Sets the specular highlight color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func specular(_ gray: Float) {
        canvas3D.specular(gray)
    }

    /// Sets the specular shininess exponent.
    /// - Parameter value: The shininess value.
    public func shininess(_ value: Float) {
        canvas3D.shininess(value)
    }

    /// Sets the emissive color.
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        canvas3D.emissive(color)
    }

    /// Sets the emissive color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func emissive(_ gray: Float) {
        canvas3D.emissive(gray)
    }

    /// Sets the metallic coefficient.
    /// - Parameter value: The metallic value between 0.0 and 1.0.
    public func metallic(_ value: Float) {
        canvas3D.metallic(value)
    }

    /// Sets the PBR roughness and automatically switches to PBR mode.
    /// - Parameter value: The roughness from 0.0 (mirror) to 1.0 (fully diffuse).
    public func roughness(_ value: Float) {
        canvas3D.roughness(value)
    }

    /// Sets the PBR ambient occlusion factor.
    /// - Parameter value: The occlusion from 0.0 (fully occluded) to 1.0 (no occlusion).
    public func ambientOcclusion(_ value: Float) {
        canvas3D.ambientOcclusion(value)
    }

    /// Toggles PBR mode explicitly.
    /// - Parameter enabled: Pass true for Cook-Torrance GGX, false for Blinn-Phong.
    public func pbr(_ enabled: Bool) {
        canvas3D.pbr(enabled)
    }

    // MARK: - 3D Custom Material

    /// Creates a custom material from MSL shader source.
    ///
    /// Compiles the MSL source and builds a `CustomMaterial` from the specified
    /// fragment function. The source should include `BuiltinShaders.canvas3DStructs`
    /// as a prefix.
    /// - Parameters:
    ///   - source: The MSL shader source code.
    ///   - fragmentFunction: The fragment shader function name.
    ///   - vertexFunction: An optional custom vertex shader function name.
    /// - Returns: A `CustomMaterial` instance.
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunction))
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    /// Applies a custom material to subsequent 3D draws.
    /// - Parameter customMaterial: The custom material to use.
    public func material(_ customMaterial: CustomMaterial) {
        canvas3D.material(customMaterial)
    }

    /// Removes the custom material and reverts to the built-in shader.
    public func noMaterial() {
        canvas3D.noMaterial()
    }

    // MARK: - 3D Texture

    /// Sets the texture for subsequent 3D draws.
    /// - Parameter img: The texture image.
    public func texture(_ img: MImage) {
        canvas3D.texture(img)
    }

    /// Removes the current texture.
    public func noTexture() {
        canvas3D.noTexture()
    }

    // MARK: - 3D Transform Stack

    /// Saves the transform matrix for both 2D and 3D canvases.
    public func pushMatrix() {
        canvas.pushMatrix()
        canvas3D.pushMatrix()
    }

    /// Restores the transform matrix for both 2D and 3D canvases.
    public func popMatrix() {
        canvas.popMatrix()
        canvas3D.popMatrix()
    }

    /// Applies a 3D translation.
    /// - Parameters:
    ///   - x: The x-axis translation.
    ///   - y: The y-axis translation.
    ///   - z: The z-axis translation.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.translate(x, y, z)
    }

    /// Rotates around the X axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) {
        canvas3D.rotateX(angle)
    }

    /// Rotates around the Y axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) {
        canvas3D.rotateY(angle)
    }

    /// Rotates around the Z axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) {
        canvas3D.rotateZ(angle)
    }

    /// Applies a 3D scale.
    /// - Parameters:
    ///   - x: The x-axis scale factor.
    ///   - y: The y-axis scale factor.
    ///   - z: The z-axis scale factor.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.scale(x, y, z)
    }

    // MARK: - 3D Shapes

    /// Draws a box with the specified dimensions.
    /// - Parameters:
    ///   - width: The box width.
    ///   - height: The box height.
    ///   - depth: The box depth.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        canvas3D.box(width, height, depth)
    }

    /// Draws a uniform box (cube) with the given side length.
    /// - Parameter size: The side length.
    public func box(_ size: Float) {
        canvas3D.box(size)
    }

    /// Draws a sphere.
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - detail: The tessellation level (default 24).
    public func sphere(_ radius: Float, detail: Int = 24) {
        canvas3D.sphere(radius, detail: detail)
    }

    /// Draws a plane.
    /// - Parameters:
    ///   - width: The plane width.
    ///   - height: The plane height.
    public func plane(_ width: Float, _ height: Float) {
        canvas3D.plane(width, height)
    }

    /// Draws a cylinder.
    /// - Parameters:
    ///   - radius: The cylinder radius (default 0.5).
    ///   - height: The cylinder height (default 1).
    ///   - detail: The tessellation level (default 24).
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draws a cone.
    /// - Parameters:
    ///   - radius: The base radius (default 0.5).
    ///   - height: The cone height (default 1).
    ///   - detail: The tessellation level (default 24).
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cone(radius: radius, height: height, detail: detail)
    }

    /// Draws a torus.
    /// - Parameters:
    ///   - ringRadius: The ring (major) radius (default 0.5).
    ///   - tubeRadius: The tube (minor) radius (default 0.2).
    ///   - detail: The tessellation level (default 24).
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draws a pre-built mesh.
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) {
        canvas3D.mesh(mesh)
    }

    /// Draws a dynamic mesh.
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        canvas3D.dynamicMesh(mesh)
    }

    /// Creates an empty dynamic mesh for procedural geometry.
    /// - Returns: A new `DynamicMesh` instance.
    public func createDynamicMesh() -> DynamicMesh {
        DynamicMesh(device: renderer.device)
    }

    /// Loads a 3D model file (OBJ, USDZ, or ABC format).
    /// - Parameters:
    ///   - path: The file path to the model.
    ///   - normalize: Pass true to normalize the bounding box to [-1, 1] (default true).
    /// - Returns: The loaded mesh, or nil on failure.
    public func loadModel(_ path: String, normalize: Bool = true) -> Mesh? {
        let url = URL(fileURLWithPath: path)
        return try? Mesh.load(device: renderer.device, url: url, normalize: normalize)
    }

    // MARK: - Compute

    /// Creates a compute kernel from MSL source code.
    /// - Parameters:
    ///   - source: The MSL source code.
    ///   - function: The kernel function name.
    /// - Returns: A `ComputeKernel` instance.
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try ComputeKernel(device: renderer.device, source: source, functionName: function)
    }

    /// Creates a zero-initialized typed GPU buffer.
    /// - Parameters:
    ///   - count: The number of elements.
    ///   - type: The element type.
    /// - Returns: A new `GPUBuffer`, or nil on failure.
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, count: count)
    }

    /// Creates a GPU buffer from an array of data.
    /// - Parameter data: The source data array.
    /// - Returns: A new `GPUBuffer`, or nil on failure.
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, data: data)
    }

    /// Dispatches a 1D compute kernel.
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - threads: The total number of threads.
    ///   - configure: A closure to configure the compute encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: threads, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches a 2D compute kernel.
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - width: The grid width in threads.
    ///   - height: The grid height in threads.
    ///   - configure: A closure to configure the compute encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let h = max(1, kernel.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Inserts a memory barrier between compute dispatches to resolve data dependencies.
    public func computeBarrier() {
        _computeEncoder?.memoryBarrier(scope: .buffers)
    }

    /// Lazily creates and returns the compute command encoder.
    func ensureComputeEncoder() -> MTLComputeCommandEncoder? {
        if let existing = _computeEncoder { return existing }
        guard let cb = _commandBuffer else { return nil }
        let encoder = cb.makeComputeCommandEncoder()
        _computeEncoder = encoder
        return encoder
    }

    // MARK: - Particle System

    /// Creates a GPU particle system.
    /// - Parameter count: The number of particles (default 100,000).
    /// - Returns: A `ParticleSystem` instance.
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try ParticleSystem(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            sampleCount: renderer.textureManager.sampleCount,
            count: count
        )
    }

    /// Updates a particle system (call during the compute phase).
    /// - Parameter system: The particle system to update.
    public func updateParticles(_ system: ParticleSystem) {
        guard let encoder = ensureComputeEncoder() else { return }
        system.update(encoder: encoder, deltaTime: deltaTime, time: time)
    }

    /// Draws a particle system (call during the draw phase).
    /// - Parameter system: The particle system to draw.
    public func drawParticles(_ system: ParticleSystem) {
        canvas.flush()
        guard let enc = canvas.currentEncoder else { return }
        system.draw(
            encoder: enc,
            viewProjection: canvas3D.currentViewProjection,
            cameraRight: canvas3D.currentCameraRight,
            cameraUp: canvas3D.currentCameraUp
        )
    }

    // MARK: - Shader Hot Reload

    /// Recompiles shader source and clears the pipeline cache.
    ///
    /// Use in combination with `CustomMaterial.reload()` or `CustomPostEffect.reload()`.
    /// - Parameters:
    ///   - key: The shader library registration key.
    ///   - source: The new MSL source code.
    public func reloadShader(key: String, source: String) throws {
        try renderer.shaderLibrary.reload(key: key, source: source)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// Reloads a shader from an external file and clears the pipeline cache.
    /// - Parameters:
    ///   - key: The shader library registration key.
    ///   - path: The file path to the MSL source.
    public func reloadShaderFromFile(key: String, path: String) throws {
        try renderer.shaderLibrary.reloadFromFile(key: key, path: path)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// Creates a custom material from an external MSL file.
    /// - Parameters:
    ///   - path: The file path to the MSL source.
    ///   - fragmentFunction: The fragment shader function name.
    ///   - vertexFunction: An optional custom vertex shader function name.
    /// - Returns: A `CustomMaterial` instance.
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.registerFromFile(path: path, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunction))
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    // MARK: - Tween

    /// Creates a tween and registers it with the tween manager.
    /// - Parameters:
    ///   - from: The starting value.
    ///   - to: The ending value.
    ///   - duration: The tween duration in seconds.
    ///   - easing: The easing function (default ease-in-out cubic).
    /// - Returns: The created `Tween` instance.
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        let t = Tween(from: from, to: to, duration: duration, easing: easing)
        tweenManager.add(t)
        return t
    }

    // MARK: - GIF Export (D-19)

    /// Begins GIF recording.
    /// - Parameter fps: The frame rate for the GIF (default 15).
    public func beginGIFRecord(fps: Int = 15) {
        gifExporter.beginRecord(
            fps: fps,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height
        )
    }

    /// Captures a GIF frame (called internally each frame).
    func captureGIFFrame() {
        guard gifExporter.isRecording else { return }
        gifExporter.captureFrame(
            texture: renderer.textureManager.colorTexture,
            device: renderer.device
        )
    }

    /// Ends GIF recording and writes the file.
    /// - Parameter path: The output file path (nil generates one on the Desktop automatically).
    public func endGIFRecord(_ path: String? = nil) throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try gifExporter.endRecord(to: actualPath)
    }

    /// Ends GIF recording and writes the file asynchronously on a background thread.
    /// - Parameter path: The output file path (nil generates one on the Desktop automatically).
    public func endGIFRecordAsync(_ path: String? = nil) async throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try await gifExporter.endRecordAsync(to: actualPath)
    }

    // MARK: - Orbit Camera (D-20)

    /// Enables orbit camera control (call during the draw phase).
    ///
    /// Drag the mouse to rotate the camera and scroll to zoom.
    public func orbitControl() {
        let inp = input

        // Rotate the camera on mouse drag
        if inp.isMouseDown {
            let dx = inp.mouseX - inp.pmouseX
            let dy = inp.mouseY - inp.pmouseY
            orbitCamera.handleMouseDrag(dx: dx, dy: dy)
        }

        // Zoom on scroll
        let sy = inp.scrollY
        if abs(sy) > 0.01 {
            orbitCamera.handleScroll(delta: sy)
        }

        // Update damping
        orbitCamera.update()

        // Apply to Canvas3D
        canvas3D.camera(eye: orbitCamera.eye, center: orbitCamera.target, up: orbitCamera.up)
    }

}
