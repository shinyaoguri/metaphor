import Foundation

/// スケッチのマウス・キーボード入力状態を管理します。
///
/// ``InputManager`` は ``MetaphorMTKView`` からイベントを受信し、
/// 現在のマウス位置（テクスチャ座標空間）、キー状態、
/// および各入力イベントタイプのオプションコールバックを提供します。
///
/// マウス座標はウィンドウ座標系ではなくオフスクリーンテクスチャ座標系で
/// 表現されるため、ウィンドウサイズに関係なく一貫した値を返します。
@MainActor
public final class InputManager {
    // MARK: - Mouse State

    /// テクスチャ座標空間での現在のマウスX座標
    public private(set) var mouseX: Float = 0

    /// テクスチャ座標空間での現在のマウスY座標
    public private(set) var mouseY: Float = 0

    /// 前フレームのマウスX座標
    public private(set) var pmouseX: Float = 0

    /// 前フレームのマウスY座標
    public private(set) var pmouseY: Float = 0

    /// いずれかのマウスボタンが現在押されているかどうか
    public private(set) var isMouseDown: Bool = false

    /// 現在押されているマウスボタンのインデックス（0 = 左、1 = 右、2 = 中）
    public private(set) var mouseButton: Int = 0

    /// 現在のフレームの水平スクロールデルタ
    public private(set) var scrollX: Float = 0

    /// 現在のフレームの垂直スクロールデルタ
    public private(set) var scrollY: Float = 0

    // MARK: - Keyboard State

    /// いずれかのキーが現在押されているかどうか
    public var isKeyPressed: Bool { !pressedKeys.isEmpty }

    /// 最後に押されたキーの文字
    public private(set) var lastKey: Character?

    /// 最後に押されたキーのキーコード
    public private(set) var lastKeyCode: UInt16?

    /// 最新のキーダウンイベントがオートリピートかどうか
    public private(set) var isKeyRepeat: Bool = false

    /// 現在押されているキーコードのセット
    private var pressedKeys: Set<UInt16> = []

    // MARK: - Callbacks

    /// マウスボタン押下時に呼ばれるコールバック (x, y, button)
    public var onMousePressed: ((Float, Float, Int) -> Void)?

    /// マウスボタン解放時に呼ばれるコールバック (x, y, button)
    public var onMouseReleased: ((Float, Float, Int) -> Void)?

    /// ボタン非押下時のマウス移動で呼ばれるコールバック (x, y)
    public var onMouseMoved: ((Float, Float) -> Void)?

    /// ボタン押下中のマウス移動で呼ばれるコールバック (x, y)
    public var onMouseDragged: ((Float, Float) -> Void)?

    /// キー押下時に呼ばれるコールバック (keyCode, characters)
    public var onKeyDown: ((UInt16, String?) -> Void)?

    /// キー解放時に呼ばれるコールバック (keyCode)
    public var onKeyUp: ((UInt16) -> Void)?

    /// 完全なクリック（ドラッグなしの押下＋解放）発生時に呼ばれるコールバック (x, y, button)
    public var onMouseClicked: ((Float, Float, Int) -> Void)?

    /// マウススクロールホイール使用時に呼ばれるコールバック (dx, dy)
    public var onMouseScrolled: ((Float, Float) -> Void)?

    // MARK: - Private State

    // 前フレームのマウス位置追跡用の2フレームバッファ。
    // マウスイベントはランループ上で renderFrame() の前に到着するため、
    // 単純に `pmouseX = mouseX` と代入すると常に同じ値になります。
    // この2フレームバッファにより、前フレームの位置を正しく保持します。
    private var _savedMouseX: Float = 0
    private var _savedMouseY: Float = 0
    private var _isFirstFrame: Bool = true
    private var _didDragSinceMouseDown: Bool = false

    // MARK: - Initialization

    /// デフォルト状態で新しい入力マネージャを作成します。
    public init() {}

    // MARK: - Query

    /// 特定のキーが現在押下中かどうかを確認します。
    ///
    /// - Parameter keyCode: 確認するハードウェアキーコード。
    /// - Returns: キーが現在押されている場合は `true`。
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        pressedKeys.contains(keyCode)
    }

    // MARK: - Frame Update

    /// 新しいフレームの開始時に前フレームのマウス座標を更新します。
    ///
    /// 2フレームバッファ戦略を使用して前フレームのマウス位置を正しく追跡し、
    /// ランループのイベント処理により `pmouseX`/`pmouseY` が
    /// 現在の位置と同一になる問題を回避します。
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

    // MARK: - Event Handlers (called from MetaphorMTKView)

    /// マウスボタン押下イベントの処理
    func handleMouseDown(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = true
        mouseButton = button
        _didDragSinceMouseDown = false
        onMousePressed?(x, y, button)
    }

    /// マウスボタン解放イベントの処理
    func handleMouseUp(x: Float, y: Float, button: Int) {
        mouseX = x
        mouseY = y
        isMouseDown = false
        onMouseReleased?(x, y, button)
        if !_didDragSinceMouseDown {
            onMouseClicked?(x, y, button)
        }
    }

    /// マウス移動イベント（ボタン非押下）の処理
    func handleMouseMoved(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        onMouseMoved?(x, y)
    }

    /// マウスドラッグイベント（ボタン押下中の移動）の処理
    func handleMouseDragged(x: Float, y: Float) {
        mouseX = x
        mouseY = y
        _didDragSinceMouseDown = true
        onMouseDragged?(x, y)
    }

    /// キー押下イベントの処理
    func handleKeyDown(keyCode: UInt16, characters: String?, isRepeat: Bool) {
        isKeyRepeat = isRepeat
        pressedKeys.insert(keyCode)
        lastKeyCode = keyCode
        lastKey = characters?.first
        onKeyDown?(keyCode, characters)
    }

    /// キー解放イベントの処理
    func handleKeyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)
        onKeyUp?(keyCode)
    }

    /// マウススクロールイベントの処理
    ///
    /// スクロールデルタはフレーム内で累積されるため、複数のイベント
    /// （例: トラックパッドの慣性スクロール）が最後の1つだけでなくすべてキャプチャされます。
    /// ``updateFrame()`` が各フレームの開始時に両方の値をゼロにリセットします。
    func handleMouseScrolled(dx: Float, dy: Float) {
        scrollX += dx
        scrollY += dy
        onMouseScrolled?(dx, dy)
    }
}
