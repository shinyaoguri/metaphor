import Foundation

/// Processing風スケッチのプロトコル
/// クラスベースでsetup()/draw()パターンを実現する
///
/// 使用例:
/// ```swift
/// class MySketch: Sketch {
///     var size: (width: Int, height: Int) { (800, 600) }
///
///     var angle: Float = 0
///
///     func setup() {
///         // 初期化処理
///     }
///
///     func draw(_ g: Graphics) {
///         g.background(51)
///         g.translate(g.width / 2, g.height / 2)
///         g.rotate(angle)
///         g.fill(255, 0, 0)
///         g.rect(-50, -50, 100, 100)
///         angle += 0.02
///     }
/// }
/// ```
public protocol Sketch: AnyObject {
    /// キャンバスサイズ
    var size: (width: Int, height: Int) { get }

    /// 初期化処理（1回だけ呼ばれる）
    func setup()

    /// 描画処理（毎フレーム呼ばれる）
    func draw(_ g: Graphics)

    // MARK: - Optional Mouse Callbacks

    /// マウスが押されたときに呼ばれる
    func mousePressed(_ g: Graphics)

    /// マウスが離されたときに呼ばれる
    func mouseReleased(_ g: Graphics)

    /// マウスがドラッグされたときに呼ばれる
    func mouseDragged(_ g: Graphics)

    /// マウスが移動したときに呼ばれる
    func mouseMoved(_ g: Graphics)

    // MARK: - Optional Keyboard Callbacks

    /// キーが押されたときに呼ばれる
    func keyPressed(_ g: Graphics)

    /// キーが離されたときに呼ばれる
    func keyReleased(_ g: Graphics)
}

// MARK: - Default Implementations

public extension Sketch {
    /// デフォルトのキャンバスサイズ
    var size: (width: Int, height: Int) { (1920, 1080) }

    /// デフォルトのsetup（何もしない）
    func setup() {}

    /// デフォルトのマウスコールバック（何もしない）
    func mousePressed(_ g: Graphics) {}
    func mouseReleased(_ g: Graphics) {}
    func mouseDragged(_ g: Graphics) {}
    func mouseMoved(_ g: Graphics) {}

    /// デフォルトのキーボードコールバック（何もしない）
    func keyPressed(_ g: Graphics) {}
    func keyReleased(_ g: Graphics) {}
}
