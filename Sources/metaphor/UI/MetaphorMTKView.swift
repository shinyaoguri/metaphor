import AppKit
import MetalKit

/// マウス・キーボードイベントをキャプチャするMTKViewサブクラス
///
/// InputManagerにイベントを転送し、テクスチャ座標系に変換する。
public class MetaphorMTKView: MTKView {
    /// レンダラー参照（座標変換用）
    weak var rendererRef: MetaphorRenderer?

    // MARK: - First Responder

    public override var acceptsFirstResponder: Bool { true }

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

    private func textureCoords(from event: NSEvent) -> (Float, Float) {
        MainActor.assumeIsolated {
            guard let renderer = rendererRef else { return (0, 0) }
            let point = convert(event.locationInWindow, from: nil)
            return renderer.viewToTextureCoordinates(
                viewPoint: point,
                viewSize: bounds.size,
                drawableSize: drawableSize
            )
        }
    }

    private func mouseButtonIndex(from event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: return 2
        default: return 0
        }
    }

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseDown(x: x, y: y, button: 0)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseUp(x: x, y: y, button: 0)
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseMoved(x: x, y: y)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseDragged(x: x, y: y)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseDown(x: x, y: y, button: 1)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseUp(x: x, y: y, button: 1)
        }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseDragged(x: x, y: y)
        }
    }

    // MARK: - Scroll Events

    public override func scrollWheel(with event: NSEvent) {
        let dx = Float(event.scrollingDeltaX)
        let dy = Float(event.scrollingDeltaY)
        MainActor.assumeIsolated {
            rendererRef?.input.handleMouseScrolled(dx: dx, dy: dy)
        }
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            rendererRef?.input.handleKeyDown(
                keyCode: event.keyCode,
                characters: event.characters
            )
        }
    }

    public override func keyUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            rendererRef?.input.handleKeyUp(keyCode: event.keyCode)
        }
    }
}
