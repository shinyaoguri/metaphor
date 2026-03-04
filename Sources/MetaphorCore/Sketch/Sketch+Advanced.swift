@preconcurrency import Metal

// MARK: - Compute

extension Sketch {

    /// Create a GPU compute kernel from MSL source code.
    ///
    /// - Parameters:
    ///   - source: The Metal Shading Language source code.
    ///   - function: The name of the compute function.
    /// - Returns: A new ``ComputeKernel`` instance.
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try activeContext().createComputeKernel(source: source, function: function)
    }

    /// Create a GPU buffer with the specified element count and type.
    ///
    /// - Parameters:
    ///   - count: The number of elements.
    ///   - type: The element type.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        _context?.createBuffer(count: count, type: type)
    }

    /// Create a GPU buffer initialized with the given data.
    ///
    /// - Parameter data: The initial data array.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        _context?.createBuffer(data)
    }

    /// Dispatch a 1D compute kernel.
    ///
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - threads: The total number of threads.
    ///   - configure: A closure to configure the compute command encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _context?.dispatch(kernel, threads: threads, configure)
    }

    /// Dispatch a 2D compute kernel.
    ///
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - width: The grid width in threads.
    ///   - height: The grid height in threads.
    ///   - configure: A closure to configure the compute command encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _context?.dispatch(kernel, width: width, height: height, configure)
    }

    /// Insert a barrier in the compute command encoder to synchronize dispatches.
    public func computeBarrier() {
        _context?.computeBarrier()
    }
}

// MARK: - Particle System

extension Sketch {
    /// Create a GPU particle system.
    ///
    /// - Parameter count: The maximum number of particles.
    /// - Returns: A new ``ParticleSystem`` instance.
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try activeContext().createParticleSystem(count: count)
    }

    /// Update a particle system (call inside ``compute()``).
    ///
    /// - Parameter system: The particle system to update.
    public func updateParticles(_ system: ParticleSystem) {
        _context?.updateParticles(system)
    }

    /// Draw a particle system (call inside ``draw()``).
    ///
    /// - Parameter system: The particle system to draw.
    public func drawParticles(_ system: ParticleSystem) {
        _context?.drawParticles(system)
    }
}

// MARK: - Tween

extension Sketch {
    /// Create and register a tween animation (automatically added to the tween manager).
    ///
    /// - Parameters:
    ///   - from: The start value.
    ///   - to: The end value.
    ///   - duration: The animation duration in seconds.
    ///   - easing: The easing function.
    /// - Returns: A new ``Tween`` instance, or `nil` if the context is unavailable.
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T>? {
        _context?.tween(from: from, to: to, duration: duration, easing: easing)
    }
}

// MARK: - Shader Hot Reload

extension Sketch {
    /// Recompile a shader from source and clear the pipeline cache.
    ///
    /// - Parameters:
    ///   - key: The shader library key to reload.
    ///   - source: The new MSL source code.
    public func reloadShader(key: String, source: String) throws {
        try activeContext().reloadShader(key: key, source: source)
    }

    /// Reload a shader from an external file and clear the pipeline cache.
    ///
    /// - Parameters:
    ///   - key: The shader library key to reload.
    ///   - path: The file path to the MSL source file.
    public func reloadShaderFromFile(key: String, path: String) throws {
        try activeContext().reloadShaderFromFile(key: key, path: path)
    }

    /// Create a custom material by loading MSL source from an external file.
    ///
    /// - Parameters:
    ///   - path: The file path to the MSL source file.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The optional name of a custom vertex function.
    /// - Returns: A new ``CustomMaterial`` instance.
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterialFromFile(path: path, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }
}

// MARK: - GUI

extension Sketch {
    /// Access the parameter GUI for creating immediate-mode UI controls.
    public var gui: ParameterGUI? {
        _context?.gui
    }
}

// MARK: - Performance HUD

extension Sketch {
    /// Enable the performance heads-up display overlay.
    public func enablePerformanceHUD() {
        _context?.enablePerformanceHUD()
    }

    /// Disable the performance heads-up display overlay.
    public func disablePerformanceHUD() {
        _context?.disablePerformanceHUD()
    }
}

// MARK: - Post Process

extension Sketch {
    /// Create a custom post-processing effect from MSL source code.
    ///
    /// - Parameters:
    ///   - name: The display name for the effect.
    ///   - source: The Metal Shading Language source code.
    ///   - fragmentFunction: The name of the fragment function.
    /// - Returns: A new ``CustomPostEffect`` instance.
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        try activeContext().createPostEffect(name: name, source: source, fragmentFunction: fragmentFunction)
    }

    /// Add a post-processing effect to the pipeline.
    ///
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: PostEffect) {
        _context?.addPostEffect(effect)
    }

    /// Remove a post-processing effect at the specified index.
    ///
    /// - Parameter index: The index of the effect to remove.
    public func removePostEffect(at index: Int) {
        _context?.removePostEffect(at: index)
    }

    /// Remove all post-processing effects from the pipeline.
    public func clearPostEffects() {
        _context?.clearPostEffects()
    }

    /// Replace all post-processing effects with the given array.
    ///
    /// - Parameter effects: The new array of post-processing effects.
    public func setPostEffects(_ effects: [PostEffect]) {
        _context?.setPostEffects(effects)
    }
}

// MARK: - Cursor Control

extension Sketch {
    /// Show the cursor.
    public func cursor() {
        _context?.cursor()
    }

    /// Hide the cursor.
    public func noCursor() {
        _context?.noCursor()
    }
}

// MARK: - GIF Export (D-19)

extension Sketch {
    /// Begin recording frames for GIF export.
    ///
    /// - Parameter fps: The target frames per second for the GIF.
    public func beginGIFRecord(fps: Int = 15) {
        _context?.beginGIFRecord(fps: fps)
    }

    /// Stop recording and write the GIF to a file.
    ///
    /// - Parameter path: The output file path (auto-generated if `nil`).
    public func endGIFRecord(_ path: String? = nil) throws {
        try activeContext().endGIFRecord(path)
    }
}

// MARK: - Orbit Camera (D-20)

extension Sketch {
    /// Enable orbit camera controls (call inside ``draw()``).
    public func orbitControl() {
        _context?.orbitControl()
    }

    /// Access the orbit camera for manual configuration.
    public var orbitCamera: OrbitCamera? {
        _context?.orbitCamera
    }
}

// MARK: - Scene Graph

extension Sketch {
    /// Create a scene graph node.
    ///
    /// - Parameter name: The optional name for the node.
    /// - Returns: A new ``Node`` instance.
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// Draw a scene graph starting from the specified root node.
    ///
    /// - Parameter root: The root node of the scene graph to render.
    public func drawScene(_ root: Node) {
        _context?.drawScene(root)
    }
}

// MARK: - Render Graph

extension Sketch {
    /// Create a source pass for the render graph.
    ///
    /// - Parameters:
    ///   - label: The debug label for the pass.
    ///   - width: The render target width in pixels.
    ///   - height: The render target height in pixels.
    /// - Returns: A new ``SourcePass`` instance, or `nil` if creation fails.
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        _context?.createSourcePass(label: label, width: width, height: height)
    }

    /// Create an effect pass that applies post-processing effects to a render pass.
    ///
    /// - Parameters:
    ///   - input: The input render pass node.
    ///   - effects: The post-processing effects to apply.
    /// - Returns: A new ``EffectPass`` instance, or `nil` if creation fails.
    public func createEffectPass(_ input: RenderPassNode, effects: [PostEffect]) -> EffectPass? {
        _context?.createEffectPass(input, effects: effects)
    }

    /// Create a merge pass that combines two render passes.
    ///
    /// - Parameters:
    ///   - a: The first input render pass node.
    ///   - b: The second input render pass node.
    ///   - blend: The blend type for compositing.
    /// - Returns: A new ``MergePass`` instance, or `nil` if creation fails.
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        _context?.createMergePass(a, b, blend: blend)
    }

    /// Set or clear the active render graph.
    ///
    /// - Parameter graph: The render graph to use, or `nil` to disable.
    public func setRenderGraph(_ graph: RenderGraph?) {
        _context?.setRenderGraph(graph)
    }
}

// MARK: - MLTextureConverter

extension Sketch {
    /// Create a texture converter for Metal-CoreML interoperability.
    ///
    /// Use this to convert between MTLTexture, CVPixelBuffer, and CGImage
    /// when working with CoreML or Vision frameworks directly.
    ///
    /// - Returns: A new ``MLTextureConverter`` instance, or `nil` if the context is unavailable.
    public func createMLTextureConverter() -> MLTextureConverter? {
        _context?.createMLTextureConverter()
    }
}

// MARK: - GameplayKit Noise

extension Sketch {
    /// Create a GameplayKit noise generator.
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - config: The noise generation configuration.
    /// - Returns: A new ``GKNoiseWrapper`` instance, or `nil` if the context is unavailable.
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper? {
        _context?.createNoise(type, config: config)
    }

    /// Generate a noise texture as an image (convenience method).
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - config: The noise generation configuration.
    /// - Returns: The generated noise image, or `nil` if generation fails.
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        _context?.noiseTexture(type, width: width, height: height, config: config)
    }
}

// MARK: - MPS

extension Sketch {
    /// Create an MPS (Metal Performance Shaders) image filter.
    ///
    /// - Returns: A new ``MPSImageFilterWrapper`` instance, or `nil` if the context is unavailable.
    public func createMPSFilter() -> MPSImageFilterWrapper? {
        _context?.createMPSFilter()
    }

    /// Create an MPS ray tracer for GPU-accelerated ray intersection queries.
    ///
    /// - Parameters:
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: A new ``MPSRayTracer`` instance.
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try activeContext().createRayTracer(width: width, height: height)
    }
}

// MARK: - CoreImage Filter

extension Sketch {
    /// Apply a CoreImage filter preset to an image.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - preset: The filter preset to apply.
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        _context?.ciFilter(image, preset)
    }

    /// Apply a CoreImage filter to an image by name with custom parameters.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - name: The CIFilter name.
    ///   - parameters: The filter parameters.
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        _context?.ciFilter(image, name: name, parameters: parameters)
    }

    /// Generate an image using a CoreImage generator filter.
    ///
    /// - Parameters:
    ///   - preset: The generator filter preset.
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: The generated image, or `nil` if generation fails.
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        _context?.ciGenerate(preset, width: width, height: height)
    }
}
