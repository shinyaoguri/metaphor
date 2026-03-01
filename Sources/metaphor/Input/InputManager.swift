import Foundation

/// マウス・キーボード入力を管理するクラス
///
/// MetaphorMTKViewからイベントを受け取り、テクスチャ座標系での
/// マウス位置やキー状態を提供する。
@MainActor
public final class InputManager {
    // MARK: - Mouse State

    /// マウスX座標（テクスチャ座標系）
    public private(set) var mouseX: Float = 0

    /// マウスY座標（テクスチャ座標系）
    public private(set) var mouseY: Float = 0

    /// 前フレームのマウスX座標
    public private(set) var pmouseX: Float = 0

    /// 前フレームのマウスY座標
    public private(set) var pmouseY: Float = 0

    /// マウスボタンが押されているか
    public private(set) var isMouseDown: Bool = false

    /// 押されているマウスボタン（0=左, 1=右, 2=中央）
    public private(set) var mouseButton: Int = 0

    /// 現フレームのスクロールX量
    public private(set) var scrollX: Float = 0

    /// 現フレームのスクロールY量
    public private(set) var scrollY: Float = 0

    // MARK: - Keyboard State

    /// いずれかのキーが押されているか
    public var isKeyPressed: Bool { !pressedKeys.isEmpty }

    /// 最後に押されたキーの文字
    public private(set) var lastKey: Character?

    /// 最後に押されたキーコード
    public private(set) var lastKeyCode: UInt16?

    private var pressedKeys: Set<UInt16> = []

    // MARK: - Callbacks

    /// マウス押下コールバック (x, y, button)
    public var onMousePressed: ((Float, Float, Int) -> Void)?

    /// マウス解放コールバック (x, y, button)
    public var onMouseReleased: ((Float, Float, Int) -> Void)?

    /// マウス移動コールバック (x, y)
    public var onMouseMoved: ((Float, Float) -> Void)?

    /// マウスドラッグコールバック (x, y)
    public var onMouseDragged: ((Float, Float) -> Void)?

    /// キー押下コールバック (keyCode, characters)
    public var onKeyDown: ((UInt16, String?) -> Void)?

    /// キー解放コールバック (keyCode)
    public var onKeyUp: ((UInt16) -> Void)?

    /// マウススクロールコールバック (dx, dy)
    public var onMouseScrolled: ((Float, Float) -> Void)?

    // MARK: - Private State

    /// 前フレーム開始時のマウス位置（2フレームバッファ）
    private var _savedMouseX: Float = 0
    private var _savedMouseY: Float = 0
    private var _isFirstFrame: Bool = true

    // MARK: - Initialization

    public init() {}

    // MARK: - Query

    /// 指定したキーコードが押されているか
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        pressedKeys.contains(keyCode)
    }

    // MARK: - Frame Update

    /// フレーム開始時に呼ばれる（前フレーム座標を更新）
    ///
    /// RunLoop上でマウスイベントは renderFrame() の前に処理されるため、
    /// 単純に `pmouseX = mouseX` とすると常に同じ値になる。
    /// 2フレームバッファ方式で前フレームの位置を正しく保持する。
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

    // MARK: - Event Handlers (MetaphorMTKViewから呼ばれる)

    func handleMouseDown(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = true
        mouseButton = button
        onMousePressed?(x, y, button)
    }

    func handleMouseUp(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = false
        onMouseReleased?(x, y, button)
    }

    func handleMouseMoved(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        onMouseMoved?(x, y)
    }

    func handleMouseDragged(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        onMouseDragged?(x, y)
    }

    func handleKeyDown(keyCode: UInt16, characters: String?) {
        pressedKeys.insert(keyCode)
        lastKeyCode = keyCode
        lastKey = characters?.first
        onKeyDown?(keyCode, characters)
    }

    func handleKeyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)
        onKeyUp?(keyCode)
    }

    func handleMouseScrolled(dx: Float, dy: Float) {
        scrollX = dx
        scrollY = dy
        onMouseScrolled?(dx, dy)
    }
}
