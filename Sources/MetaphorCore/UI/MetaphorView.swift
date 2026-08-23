import SwiftUI
import MetalKit

/// SwiftUI ビュー階層内で Metal レンダリングコンテンツを表示します。
///
/// `NSViewRepresentable` を介して `MetaphorMTKView` をラップし、
/// Metal レンダリングとともにマウス・キーボードイベントを自動的に処理します。
public struct MetaphorView: NSViewRepresentable {
    private let renderer: MetaphorRenderer
    private let preferredFPS: Int

    /// 指定されたレンダラーに基づく新しい MetaphorView を作成します。
    /// - Parameters:
    ///   - renderer: Metal レンダリングを駆動するレンダラー。
    ///   - preferredFPS: 目標フレームレート（デフォルト: 60）。
    public init(renderer: MetaphorRenderer, preferredFPS: Int = 60) {
        self.renderer = renderer
        self.preferredFPS = preferredFPS
    }

    /// 基盤となる MTKView を作成し、レンダラーで設定します。
    /// - Parameter context: SwiftUI の representable コンテキスト。
    /// - Returns: 設定済みの `MetaphorMTKView` インスタンス。
    public func makeNSView(context: Context) -> MetaphorMTKView {
        let view = MetaphorMTKView()
        view.preferredFramesPerSecond = preferredFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        renderer.configure(view: view)
        return view
    }

    /// SwiftUI の状態変更時にビューのフレームレートを更新します。
    /// - Parameters:
    ///   - nsView: 既存の `MetaphorMTKView` インスタンス。
    ///   - context: SwiftUI の representable コンテキスト。
    public func updateNSView(_ nsView: MetaphorMTKView, context: Context) {
        nsView.preferredFramesPerSecond = preferredFPS
    }
}
