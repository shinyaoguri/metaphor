import SwiftUI
import MetalKit

/// Display Metal rendering content within a SwiftUI view hierarchy.
///
/// Wraps a `MetaphorMTKView` via `NSViewRepresentable` to automatically handle
/// mouse and keyboard events alongside Metal rendering.
public struct MetaphorView: NSViewRepresentable {
    private let renderer: MetaphorRenderer
    private let preferredFPS: Int

    /// Create a new MetaphorView backed by the given renderer.
    /// - Parameters:
    ///   - renderer: The renderer that drives Metal rendering.
    ///   - preferredFPS: The desired frame rate (default: 60).
    public init(renderer: MetaphorRenderer, preferredFPS: Int = 60) {
        self.renderer = renderer
        self.preferredFPS = preferredFPS
    }

    /// Create the underlying MTKView and configure it with the renderer.
    /// - Parameter context: The SwiftUI representable context.
    /// - Returns: A configured `MetaphorMTKView` instance.
    public func makeNSView(context: Context) -> MetaphorMTKView {
        let view = MetaphorMTKView()
        view.preferredFramesPerSecond = preferredFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        renderer.configure(view: view)
        return view
    }

    /// Update the view's frame rate when SwiftUI state changes.
    /// - Parameters:
    ///   - nsView: The existing `MetaphorMTKView` instance.
    ///   - context: The SwiftUI representable context.
    public func updateNSView(_ nsView: MetaphorMTKView, context: Context) {
        nsView.preferredFramesPerSecond = preferredFPS
    }
}
