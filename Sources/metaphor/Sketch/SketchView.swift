import SwiftUI
import MetalKit

/// Sketchプロトコル準拠のスケッチを表示するSwiftUIビュー
public struct SketchView<S: Sketch>: View {
    @StateObject private var runner: SketchRunner<S>
    private let preferredFPS: Int

    /// Sketchから初期化
    @MainActor
    public init(_ sketch: S, fps: Int = 60) {
        _runner = StateObject(wrappedValue: SketchRunner(sketch: sketch))
        self.preferredFPS = fps
    }

    public var body: some View {
        GeometryReader { geometry in
            SketchMetalView(
                runner: runner,
                preferredFPS: preferredFPS,
                viewSize: geometry.size
            )
        }
    }
}

/// Sketch用のMetal View
struct SketchMetalView<S: Sketch>: NSViewRepresentable {
    let runner: SketchRunner<S>
    let preferredFPS: Int
    let viewSize: CGSize

    func makeNSView(context: Context) -> SketchInputView<S> {
        let view = SketchInputView<S>()
        view.preferredFramesPerSecond = preferredFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.runner = runner
        runner.renderer.configure(view: view)
        return view
    }

    func updateNSView(_ nsView: SketchInputView<S>, context: Context) {
        nsView.preferredFramesPerSecond = preferredFPS
        nsView.viewSize = viewSize
    }
}

/// Sketch用の入力キャプチャビュー
class SketchInputView<S: Sketch>: MTKView {
    weak var runner: SketchRunner<S>?
    var viewSize: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - Mouse Events

    private func updateMousePosition(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        runner?.updateMousePosition(
            viewX: location.x,
            viewY: bounds.height - location.y,
            viewWidth: bounds.width,
            viewHeight: bounds.height
        )
    }

    override func mouseMoved(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseDown(button: .left)
    }

    override func mouseUp(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseUp()
    }

    override func rightMouseDown(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseDown(button: .right)
    }

    override func rightMouseUp(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseUp()
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseDown(button: .center)
    }

    override func otherMouseUp(with event: NSEvent) {
        updateMousePosition(with: event)
        runner?.mouseUp()
    }

    override func otherMouseDragged(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let char = event.characters?.first ?? "\0"
        runner?.keyDown(character: char, keyCode: event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        runner?.keyUp()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}
