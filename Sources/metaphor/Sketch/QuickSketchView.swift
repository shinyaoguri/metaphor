import SwiftUI
import MetalKit

/// QuickSketchを表示するSwiftUIビュー
/// マウス・キーボードイベントを処理する
public struct QuickSketchView: View {
    @StateObject private var runner: QuickSketchRunner
    private let preferredFPS: Int

    /// QuickSketchConfigから初期化
    @MainActor
    public init(_ config: QuickSketchConfig, fps: Int = 60) {
        _runner = StateObject(wrappedValue: QuickSketchRunner(config: config))
        self.preferredFPS = fps
    }

    public var body: some View {
        GeometryReader { geometry in
            InteractiveMetaphorView(
                runner: runner,
                preferredFPS: preferredFPS,
                viewSize: geometry.size
            )
        }
    }
}

/// マウス・キーボードイベントを処理するMetaphorViewラッパー
struct InteractiveMetaphorView: NSViewRepresentable {
    let runner: QuickSketchRunner
    let preferredFPS: Int
    let viewSize: CGSize

    func makeNSView(context: Context) -> InputCapturingMTKView {
        let view = InputCapturingMTKView()
        view.preferredFramesPerSecond = preferredFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.runner = runner
        runner.renderer.configure(view: view)
        return view
    }

    func updateNSView(_ nsView: InputCapturingMTKView, context: Context) {
        nsView.preferredFramesPerSecond = preferredFPS
        nsView.viewSize = viewSize
    }
}

/// 入力イベントをキャプチャするMTKView
class InputCapturingMTKView: MTKView {
    weak var runner: QuickSketchRunner?
    var viewSize: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // 既存のトラッキングエリアを削除
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        // 新しいトラッキングエリアを追加
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
            viewY: bounds.height - location.y,  // Y軸を反転（上が0）
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

    // ESCキー等のシステムキーも受け取る
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}

// MARK: - Convenience Functions

/// Processing風のスケッチを作成（描画のみ）
/// - Parameters:
///   - width: キャンバス幅（デフォルト: 1920）
///   - height: キャンバス高さ（デフォルト: 1080）
///   - fps: フレームレート（デフォルト: 60）
///   - draw: 描画クロージャ
/// - Returns: SwiftUIビュー
@MainActor
public func sketch(
    width: Int = 1920,
    height: Int = 1080,
    fps: Int = 60,
    draw: @escaping (Graphics) -> Void
) -> some View {
    QuickSketchView(
        QuickSketchConfig(width: width, height: height).draw(draw),
        fps: fps
    )
}

/// Processing風のスケッチを作成（セットアップと描画）
/// - Parameters:
///   - width: キャンバス幅（デフォルト: 1920）
///   - height: キャンバス高さ（デフォルト: 1080）
///   - fps: フレームレート（デフォルト: 60）
///   - setup: セットアップクロージャ（初回のみ実行）
///   - draw: 描画クロージャ
/// - Returns: SwiftUIビュー
@MainActor
public func sketch(
    width: Int = 1920,
    height: Int = 1080,
    fps: Int = 60,
    setup: @escaping () -> Void,
    draw: @escaping (Graphics) -> Void
) -> some View {
    QuickSketchView(
        QuickSketchConfig(width: width, height: height)
            .setup(setup)
            .draw(draw),
        fps: fps
    )
}
