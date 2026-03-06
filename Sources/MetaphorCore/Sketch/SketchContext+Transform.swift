import Metal

extension SketchContext {

    // MARK: - Post Process

    /// Creates a custom post-processing effect from MSL fragment shader source.
    ///
    /// The shader source should include `PostProcessShaders.commonStructs` as a prefix.
    /// - Parameters:
    ///   - name: The effect name (used as the library key).
    ///   - source: The MSL shader source code.
    ///   - fragmentFunction: The fragment shader function name.
    /// - Returns: A `CustomPostEffect` instance.
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunction)
        }
        return CustomPostEffect(name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
    }

    /// Adds a post-processing effect to the pipeline.
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: any PostEffect) {
        renderer.addPostEffect(effect)
    }

    /// Removes a post-processing effect at the specified index.
    /// - Parameter index: The index of the effect to remove.
    public func removePostEffect(at index: Int) {
        renderer.removePostEffect(at: index)
    }

    /// Removes all post-processing effects from the pipeline.
    public func clearPostEffects() {
        renderer.clearPostEffects()
    }

    /// Replaces all post-processing effects with the given array.
    /// - Parameter effects: The new array of post-processing effects.
    public func setPostEffects(_ effects: [any PostEffect]) {
        renderer.setPostEffects(effects)
    }

    // MARK: - Unified Transform Stack

    /// Saves both 2D and 3D transform and style state onto the stack.
    public func push() {
        canvas.push()
        canvas3D.pushState()
    }

    /// Restores both 2D and 3D transform and style state from the stack.
    public func pop() {
        canvas.pop()
        canvas3D.popState()
    }

    /// Saves only the 2D style state onto the stack.
    public func pushStyle() {
        canvas.pushStyle()
    }

    /// Restores only the 2D style state from the stack.
    public func popStyle() {
        canvas.popStyle()
    }

    /// Applies a 2D translation.
    /// - Parameters:
    ///   - x: The horizontal translation.
    ///   - y: The vertical translation.
    public func translate(_ x: Float, _ y: Float) {
        canvas.translate(x, y)
    }

    /// Applies a 2D rotation.
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) {
        canvas.rotate(angle)
    }

    /// Applies a 2D scale.
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) {
        canvas.scale(sx, sy)
    }

    /// Applies a uniform scale to both the 2D and 3D canvases.
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) {
        canvas.scale(s)
        canvas3D.scale(s, s, s)
    }
}
