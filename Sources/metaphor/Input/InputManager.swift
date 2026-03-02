import Foundation

/// Manage mouse and keyboard input state for the sketch.
///
/// ``InputManager`` receives events from ``MetaphorMTKView`` and provides
/// the current mouse position (in texture coordinate space), key states,
/// and optional callbacks for each input event type.
///
/// Mouse coordinates are expressed in the offscreen texture coordinate system,
/// not the window coordinate system, so they remain consistent regardless of
/// window size.
@MainActor
public final class InputManager {
    // MARK: - Mouse State

    /// The current mouse x-coordinate in texture coordinate space.
    public private(set) var mouseX: Float = 0

    /// The current mouse y-coordinate in texture coordinate space.
    public private(set) var mouseY: Float = 0

    /// The mouse x-coordinate from the previous frame.
    public private(set) var pmouseX: Float = 0

    /// The mouse y-coordinate from the previous frame.
    public private(set) var pmouseY: Float = 0

    /// Indicate whether any mouse button is currently pressed.
    public private(set) var isMouseDown: Bool = false

    /// The index of the currently pressed mouse button (0 = left, 1 = right, 2 = middle).
    public private(set) var mouseButton: Int = 0

    /// The horizontal scroll delta for the current frame.
    public private(set) var scrollX: Float = 0

    /// The vertical scroll delta for the current frame.
    public private(set) var scrollY: Float = 0

    // MARK: - Keyboard State

    /// Indicate whether any key is currently pressed.
    public var isKeyPressed: Bool { !pressedKeys.isEmpty }

    /// The character of the most recently pressed key.
    public private(set) var lastKey: Character?

    /// The key code of the most recently pressed key.
    public private(set) var lastKeyCode: UInt16?

    /// The set of currently pressed key codes.
    private var pressedKeys: Set<UInt16> = []

    // MARK: - Callbacks

    /// The callback invoked when a mouse button is pressed (x, y, button).
    public var onMousePressed: ((Float, Float, Int) -> Void)?

    /// The callback invoked when a mouse button is released (x, y, button).
    public var onMouseReleased: ((Float, Float, Int) -> Void)?

    /// The callback invoked when the mouse moves without any button pressed (x, y).
    public var onMouseMoved: ((Float, Float) -> Void)?

    /// The callback invoked when the mouse moves while a button is pressed (x, y).
    public var onMouseDragged: ((Float, Float) -> Void)?

    /// The callback invoked when a key is pressed (keyCode, characters).
    public var onKeyDown: ((UInt16, String?) -> Void)?

    /// The callback invoked when a key is released (keyCode).
    public var onKeyUp: ((UInt16) -> Void)?

    /// The callback invoked when the mouse scroll wheel is used (dx, dy).
    public var onMouseScrolled: ((Float, Float) -> Void)?

    // MARK: - Private State

    // Two-frame buffer for previous mouse position tracking.
    // Because mouse events arrive on the run loop before renderFrame(), simply
    // assigning `pmouseX = mouseX` would always yield the same value. This
    // two-frame buffer correctly preserves the position from the prior frame.
    private var _savedMouseX: Float = 0
    private var _savedMouseY: Float = 0
    private var _isFirstFrame: Bool = true

    // MARK: - Initialization

    /// Create a new input manager with default state.
    public init() {}

    // MARK: - Query

    /// Check whether a specific key is currently held down.
    ///
    /// - Parameter keyCode: The hardware key code to check.
    /// - Returns: `true` if the key is currently pressed.
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        pressedKeys.contains(keyCode)
    }

    // MARK: - Frame Update

    /// Update the previous-frame mouse coordinates at the start of a new frame.
    ///
    /// This uses a two-frame buffer strategy to correctly track the mouse
    /// position from the prior frame, avoiding the issue where run-loop
    /// event processing would make `pmouseX`/`pmouseY` identical to the
    /// current position.
    func updateFrame() {
        scrollX = 0
        scrollY = 0

        if _isFirstFrame {
            _savedMouseX = mouseX
            _savedMouseY = mouseY
            pmouseX = mouseX
            pmouseY = mouseY
            _isFirstFrame = false
        } else {
            pmouseX = _savedMouseX
            pmouseY = _savedMouseY
            _savedMouseX = mouseX
            _savedMouseY = mouseY
        }
    }

    // MARK: - Event Handlers (called from MetaphorMTKView)

    /// Handle a mouse button press event.
    func handleMouseDown(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = true
        mouseButton = button
        onMousePressed?(x, y, button)
    }

    /// Handle a mouse button release event.
    func handleMouseUp(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = false
        onMouseReleased?(x, y, button)
    }

    /// Handle a mouse movement event (no button pressed).
    func handleMouseMoved(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        onMouseMoved?(x, y)
    }

    /// Handle a mouse drag event (button held while moving).
    func handleMouseDragged(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        onMouseDragged?(x, y)
    }

    /// Handle a key press event.
    func handleKeyDown(keyCode: UInt16, characters: String?) {
        pressedKeys.insert(keyCode)
        lastKeyCode = keyCode
        lastKey = characters?.first
        onKeyDown?(keyCode, characters)
    }

    /// Handle a key release event.
    func handleKeyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)
        onKeyUp?(keyCode)
    }

    /// Handle a mouse scroll event.
    func handleMouseScrolled(dx: Float, dy: Float) {
        scrollX = dx
        scrollY = dy
        onMouseScrolled?(dx, dy)
    }
}
