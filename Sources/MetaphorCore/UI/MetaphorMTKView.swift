import AppKit
import MetalKit

/// MTKView のサブクラスとしてマウス・キーボードイベントをキャプチャします。
///
/// すべての入力イベントを `InputManager` に転送し、レンダラーを介して
/// ウィンドウ座標をオフスクリーンテクスチャ座標系に変換します。
@MainActor
public class MetaphorMTKView: MTKView {
    /// 座標変換に使用するレンダラーへの弱参照
    weak var rendererRef: MetaphorRenderer?

    // MARK: - First Responder

    /// キーボードイベントを受信するためにファーストレスポンダを受け入れ
    public override var acceptsFirstResponder: Bool { true }

    /// マウス移動イベントが配信されるようにトラッキングエリアを再構築します。
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

    /// NSEvent のウィンドウ位置をオフスクリーンテクスチャ座標に変換します。
    /// - Parameter event: 受信したマウスイベント。
    /// - Returns: テクスチャ座標空間での (x, y) タプル。
    private func textureCoords(from event: NSEvent) -> (Float, Float) {
        guard let renderer = rendererRef else { return (0, 0) }
        let point = convert(event.locationInWindow, from: nil)
        return renderer.viewToTextureCoordinates(
            viewPoint: point,
            viewSize: bounds.size,
            drawableSize: drawableSize
        )
    }

    /// イベントタイプからマウスボタンインデックスを判定します。
    /// - Parameter event: 受信したマウスイベント。
    /// - Returns: 左は0、右は1、その他は2。
    private func mouseButtonIndex(from event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: return 2
        default: return 0
        }
    }

    // MARK: - Mouse Events

    /// 左マウスボタン押下の処理
    public override func mouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 0)
    }

    /// 左マウスボタン解放の処理
    public override func mouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 0)
    }

    /// ボタン非押下時のマウス移動の処理
    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseMoved(x: x, y: y)
    }

    /// 左ボタン押下中のマウス移動の処理
    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    /// 右マウスボタン押下の処理
    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 1)
    }

    /// 右マウスボタン解放の処理
    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 1)
    }

    /// 右ボタン押下中のマウス移動の処理
    public override func rightMouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    /// 中マウスボタン押下の処理
    public override func otherMouseDown(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDown(x: x, y: y, button: 2)
    }

    /// 中マウスボタン解放の処理
    public override func otherMouseUp(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseUp(x: x, y: y, button: 2)
    }

    /// 中ボタン押下中のマウス移動の処理
    public override func otherMouseDragged(with event: NSEvent) {
        let (x, y) = textureCoords(from: event)
        rendererRef?.input.handleMouseDragged(x: x, y: y)
    }

    // MARK: - Scroll Events

    /// ズームまたはスクロール用のスクロールホイール入力の処理
    public override func scrollWheel(with event: NSEvent) {
        let dx = Float(event.scrollingDeltaX)
        let dy = Float(event.scrollingDeltaY)
        rendererRef?.input.handleMouseScrolled(dx: dx, dy: dy)
    }

    // MARK: - Keyboard Events

    /// キー押下イベントの処理
    public override func keyDown(with event: NSEvent) {
        rendererRef?.input.handleKeyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            isRepeat: event.isARepeat
        )
    }

    /// キー解放イベントの処理
    public override func keyUp(with event: NSEvent) {
        rendererRef?.input.handleKeyUp(keyCode: event.keyCode)
    }
}
