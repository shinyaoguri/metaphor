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

    // MARK: - Initialization

    public init() {}

    // MARK: - Query

    /// 指定したキーコードが押されているか
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        pressedKeys.contains(keyCode)
    }

    // MARK: - Frame Update

    /// フレーム開始時に呼ばれる（前フレーム座標を更新）
    func updateFrame() {
        pmouseX = mouseX
        pmouseY = mouseY
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
}
