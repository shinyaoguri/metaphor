// MARK: - Convenience Properties

extension Sketch {
    /// Return the canvas width in pixels.
    public var width: Float {
        _context?.width ?? 0
    }

    /// Return the canvas height in pixels.
    public var height: Float {
        _context?.height ?? 0
    }

    /// Access the input manager (use inside event handlers).
    public var input: InputManager? {
        _context?.input
    }

    /// Return the current mouse x-coordinate.
    public var mouseX: Float {
        _context?.input.mouseX ?? 0
    }

    /// Return the current mouse y-coordinate.
    public var mouseY: Float {
        _context?.input.mouseY ?? 0
    }

    /// Return the mouse x-coordinate from the previous frame.
    public var pmouseX: Float {
        _context?.input.pmouseX ?? 0
    }

    /// Return the mouse y-coordinate from the previous frame.
    public var pmouseY: Float {
        _context?.input.pmouseY ?? 0
    }

    /// Indicate whether a mouse button is currently pressed.
    public var isMousePressed: Bool {
        _context?.input.isMouseDown ?? false
    }

    /// Return the horizontal scroll amount for the current frame.
    public var scrollX: Float {
        _context?.input.scrollX ?? 0
    }

    /// Return the vertical scroll amount for the current frame.
    public var scrollY: Float {
        _context?.input.scrollY ?? 0
    }

    /// Return the currently pressed mouse button (0 = left, 1 = right, 2 = middle).
    public var mouseButton: Int {
        _context?.input.mouseButton ?? 0
    }

    /// Indicate whether a key is currently pressed.
    public var isKeyPressed: Bool {
        _context?.input.isKeyPressed ?? false
    }

    /// Return the last key that was pressed.
    public var key: Character? {
        _context?.input.lastKey
    }

    /// Return the key code of the last key that was pressed.
    public var keyCode: UInt16? {
        _context?.input.lastKeyCode
    }

    /// Check whether a specific key is currently held down.
    ///
    /// - Parameter keyCode: The hardware key code to check.
    /// - Returns: `true` if the key is currently pressed.
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        _context?.input.isKeyDown(keyCode) ?? false
    }

    /// Return the elapsed time in seconds since the sketch started.
    public var time: Float {
        _context?.time ?? 0
    }

    /// Return the time elapsed since the previous frame in seconds.
    public var deltaTime: Float {
        _context?.deltaTime ?? 0
    }

    /// Return the total number of frames rendered so far.
    public var frameCount: Int {
        _context?.frameCount ?? 0
    }
}

// MARK: - Canvas Setup

extension Sketch {
    /// Set the canvas size (call inside `setup()`, p5.js-style).
    ///
    /// - Parameters:
    ///   - width: The canvas width in pixels.
    ///   - height: The canvas height in pixels.
    public func createCanvas(width: Int, height: Int) {
        _context?.createCanvas(width: width, height: height)
    }
}

// MARK: - Vector Factory

extension Sketch {
    /// Create a 2D vector (Processing PVector compatible).
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    /// - Returns: A new ``Vec2`` with the given components.
    public func createVector(_ x: Float = 0, _ y: Float = 0) -> Vec2 {
        Vec2(x, y)
    }

    /// Create a 3D vector (Processing PVector compatible).
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    ///   - z: The z component.
    /// - Returns: A new ``Vec3`` with the given components.
    public func createVector(_ x: Float, _ y: Float, _ z: Float) -> Vec3 {
        Vec3(x, y, z)
    }
}

// MARK: - Animation Control

extension Sketch {
    /// Indicate whether the animation loop is currently running.
    public var isLooping: Bool {
        _context?.isLooping ?? true
    }

    /// Resume the animation loop.
    public func loop() {
        _context?.loop()
    }

    /// Stop the animation loop.
    public func noLoop() {
        _context?.noLoop()
    }

    /// Render a single frame (use after calling ``noLoop()``).
    public func redraw() {
        _context?.redraw()
    }

    /// Change the frame rate dynamically.
    ///
    /// - Parameter fps: The target frames per second.
    public func frameRate(_ fps: Int) {
        _context?.frameRate(fps)
    }
}
