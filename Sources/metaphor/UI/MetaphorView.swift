import SwiftUI
import MetalKit

/// SwiftUIでMetalレンダリングを表示するためのビュー
///
/// MetaphorMTKViewを使用してマウス・キーボードイベントも自動的に処理する。
public struct MetaphorView: NSViewRepresentable {
    private let renderer: MetaphorRenderer
    private let preferredFPS: Int

    /// 初期化
    /// - Parameters:
    ///   - renderer: MetaphorRenderer
    ///   - preferredFPS: 希望するフレームレート（デフォルト: 60）
    public init(renderer: MetaphorRenderer, preferredFPS: Int = 60) {
        self.renderer = renderer
        self.preferredFPS = preferredFPS
    }

    public func makeNSView(context: Context) -> MetaphorMTKView {
        let view = MetaphorMTKView()
        view.preferredFramesPerSecond = preferredFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        renderer.configure(view: view)
        return view
    }

    public func updateNSView(_ nsView: MetaphorMTKView, context: Context) {
        nsView.preferredFramesPerSecond = preferredFPS
    }
}
