import AppKit
import MetalKit

/// Capture mouse and keyboard events as an MTKView subclass.
///
/// Forwards all input events to `InputManager` and converts window coordinates
/// to the offscreen texture coordinate system via the renderer.
@MainActor
public class MetaphorMTKView: MTKView {
    /// Weak reference to the renderer used for coordinate conversion.
    weak var rendererRef: MetaphorRenderer?

    // MARK: - First Responder

    /// Accept first responder status to receive keyboard events.
    public override var acceptsFirstResponder: Bool { true }

    /// Rebuild tracking areas to ensure mouse-moved events are delivered.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Coordinate Conversion

    /// Convert an NSEvent's window location to offscreen texture coordinates.
    /// - Parameter event: The incoming mouse event.
    /// - Returns: A tuple of (x, y) in texture coordinate space.
    private func textureCoords(from event: NSEvent) -> (Float, Float) {
        guard let renderer = rendererRef else { return (0, 0) }
        let point = convert(event.locationInWindow, from: nil)
        return renderer.viewToTextureCoordinates(
            viewPoint: point,
            viewSize: bounds.size,
            drawableSize: drawableSize
        )
    }

    /// Determine the mouse button index from an event type.
    /// - Parameter event: The incoming mouse event.
    /// - Returns: 0 for left, 1 for right, 2 for other buttons.
    private func mouseButtonIndex(from event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: return 2
        default: return 0
        }
    }

    // MARK: - Mouse Events

    /// Handle left mouse button press.
    public override func mouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 0)
    }

    /// Handle left mouse button release.
    public override func mouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 0)
    }

    /// Handle mouse movement without any button pressed.
    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseMoved(x: x, y: y)
    }

    /// Handle mouse movement while the left button is held.
    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    /// Handle right mouse button press.
    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 1)
    }

    /// Handle right mouse button release.
    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 1)
    }

    /// Handle mouse movement while the right button is held.
    public override func rightMouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    /// Handle middle mouse button press.
    public override func otherMouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 2)
    }

    /// Handle middle mouse button release.
    public override func otherMouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 2)
    }

    /// Handle mouse movement while the middle button is held.
    public override func otherMouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    // MARK: - Scroll Events

    /// Handle scroll wheel input for zooming or scrolling.
    public override func scrollWheel(with event: NSEvent) {
        let dx = Float(event.scrollingDeltaX)
        let dy = Float(event.scrollingDeltaY)
        rendererRef?.input.handleMouseScrolled(dx: dx, dy: dy)
    }

    // MARK: - Keyboard Events

    /// Handle key press events.
    public override func keyDown(with event: NSEvent) {
        rendererRef?.input.handleKeyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            isRepeat: event.isARepeat
        )
    }

    /// Handle key release events.
    public override func keyUp(with event: NSEvent) {
        rendererRef?.input.handleKeyUp(keyCode: event.keyCode)
    }
}
