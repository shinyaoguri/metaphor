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
        try context.createComputeKernel(source: source, function: function)
    }

    /// Create a GPU buffer with the specified element count and type.
    ///
    /// - Parameters:
    ///   - count: The number of elements.
    ///   - type: The element type.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        context.createBuffer(count: count, type: type)
    }

    /// Create a GPU buffer initialized with the given data.
    ///
    /// - Parameter data: The initial data array.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        context.createBuffer(data)
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
        context.dispatch(kernel, threads: threads, configure)
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
        context.dispatch(kernel, width: width, height: height, configure)
    }

    /// Insert a barrier in the compute command encoder to synchronize dispatches.
    public func computeBarrier() {
        context.computeBarrier()
    }
}

// MARK: - Particle System

extension Sketch {
    /// Create a GPU particle system.
    ///
    /// - Parameter count: The maximum number of particles.
    /// - Returns: A new ``ParticleSystem`` instance.
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try context.createParticleSystem(count: count)
    }

    /// Update a particle system (call inside ``compute()``).
    ///
    /// - Parameter system: The particle system to update.
    public func updateParticles(_ system: ParticleSystem) {
        context.updateParticles(system)
    }

    /// Draw a particle system (call inside ``draw()``).
    ///
    /// - Parameter system: The particle system to draw.
    public func drawParticles(_ system: ParticleSystem) {
        context.drawParticles(system)
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
        context.tween(from: from, to: to, duration: duration, easing: easing)
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
        try context.reloadShader(key: key, source: source)
    }

    /// Reload a shader from an external file and clear the pipeline cache.
    ///
    /// - Parameters:
    ///   - key: The shader library key to reload.
    ///   - path: The file path to the MSL source file.
    public func reloadShaderFromFile(key: String, path: String) throws {
        try context.reloadShaderFromFile(key: key, path: path)
    }

    /// Create a custom material by loading MSL source from an external file.
    ///
    /// - Parameters:
    ///   - path: The file path to the MSL source file.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The optional name of a custom vertex function.
    /// - Returns: A new ``CustomMaterial`` instance.
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try context.createMaterialFromFile(path: path, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }
}

// MARK: - GUI

extension Sketch {
    /// Access the parameter GUI for creating immediate-mode UI controls.
    public var gui: ParameterGUI? {
        context.gui
    }
}

// MARK: - Performance HUD

extension Sketch {
    /// Enable the performance heads-up display overlay.
    public func enablePerformanceHUD() {
        context.enablePerformanceHUD()
    }

    /// Disable the performance heads-up display overlay.
    public func disablePerformanceHUD() {
        context.disablePerformanceHUD()
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
        try context.createPostEffect(name: name, source: source, fragmentFunction: fragmentFunction)
    }

    /// Add a post-processing effect to the pipeline.
    ///
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: any PostEffect) {
        context.addPostEffect(effect)
    }

    /// Remove a post-processing effect at the specified index.
    ///
    /// - Parameter index: The index of the effect to remove.
    public func removePostEffect(at index: Int) {
        context.removePostEffect(at: index)
    }

    /// Remove all post-processing effects from the pipeline.
    public func clearPostEffects() {
        context.clearPostEffects()
    }

    /// Replace all post-processing effects with the given array.
    ///
    /// - Parameter effects: The new array of post-processing effects.
    public func setPostEffects(_ effects: [any PostEffect]) {
        context.setPostEffects(effects)
    }
}

// MARK: - Cursor Control

extension Sketch {
    /// Show the cursor.
    public func cursor() {
        context.cursor()
    }

    /// Hide the cursor.
    public func noCursor() {
        context.noCursor()
    }
}

// MARK: - GIF Export (D-19)

extension Sketch {
    /// Begin recording frames for GIF export.
    ///
    /// - Parameter fps: The target frames per second for the GIF.
    public func beginGIFRecord(fps: Int = 15) {
        context.beginGIFRecord(fps: fps)
    }

    /// Stop recording and write the GIF to a file.
    ///
    /// - Parameter path: The output file path (auto-generated if `nil`).
    public func endGIFRecord(_ path: String? = nil) throws {
        try context.endGIFRecord(path)
    }

    /// Stop recording and write the GIF to a file asynchronously.
    ///
    /// Performs file writing on a background thread to avoid blocking.
    /// - Parameter path: The output file path (auto-generated if `nil`).
    public func endGIFRecord(_ path: String? = nil) async throws {
        try await context.endGIFRecordAsync(path)
    }
}

// MARK: - Orbit Camera (D-20)

extension Sketch {
    /// Enable orbit camera controls (call inside ``draw()``).
    public func orbitControl() {
        context.orbitControl()
    }

    /// Access the orbit camera for manual configuration.
    public var orbitCamera: OrbitCamera? {
        context.orbitCamera
    }
}

// MARK: - Cache Management

extension Sketch {
    /// Clear all internal caches to reclaim GPU memory.
    public func clearCaches() {
        context.clearCaches()
    }
}
