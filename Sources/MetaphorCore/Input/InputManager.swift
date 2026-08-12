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

    /// 最後に押されたマウスボタン。まだ一度も押されていなければ `nil`
    ///
    /// Processing と同じく、ボタンを離しても値は保持される（`mouseReleased()`
    /// の中でどのボタンが離されたかを判定できるようにするため）。「いま押されて
    /// いるか」は ``isMouseDown`` で判定する。
    public private(set) var mouseButton: MouseButton?

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
    public var onMousePressed: ((Float, Float, MouseButton) -> Void)?

    /// マウスボタン解放時に呼ばれるコールバック (x, y, button)
    public var onMouseReleased: ((Float, Float, MouseButton) -> Void)?

    /// ボタン非押下時のマウス移動で呼ばれるコールバック (x, y)
    public var onMouseMoved: ((Float, Float) -> Void)?

    /// ボタン押下中のマウス移動で呼ばれるコールバック (x, y)
    public var onMouseDragged: ((Float, Float) -> Void)?

    /// キー押下時に呼ばれるコールバック (keyCode, characters)
    public var onKeyDown: ((UInt16, String?) -> Void)?

    /// キー解放時に呼ばれるコールバック (keyCode)
    public var onKeyUp: ((UInt16) -> Void)?

    /// 完全なクリック（ドラッグなしの押下＋解放）発生時に呼ばれるコールバック (x, y, button)
    public var onMouseClicked: ((Float, Float, MouseButton) -> Void)?

    /// マウススクロールホイール使用時に呼ばれるコールバック (dx, dy)
    public var onMouseScrolled: ((Float, Float) -> Void)?

    /// ファイルがウィンドウにドロップされた時に呼ばれるコールバック (ファイルパスの配列)
    public var onFileDrop: (([String]) -> Void)?

    /// `Sketch.fileDropped(_:)` へ転送するランナー用の内部コールバック。
    /// ユーザーが ``onFileDrop`` を直接設定しても衝突しないよう独立させている。
    var onFileDropInternal: (([String]) -> Void)?

    // MARK: - Private State

    // 「前フレームの draw が見ていたマウス位置」。フレーム末の endFrame() で保存し、
    // 次フレーム頭の updateFrame() で pmouseX/pmouseY へ渡します。
    // イベントの到着がフレームのどこであっても（AppKit はフレーム間、ヘッドレスの
    // InputInjectionPlugin は updateFrame() の後の pre()）、ちょうど 1 フレーム前を指します。
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

    /// 新しいフレームの開始時に、前フレームのマウス座標とスクロールデルタを更新します。
    ///
    /// ``endFrame()`` が前フレーム末に保存した位置を `pmouseX`/`pmouseY` へ渡します。
    /// この 2 つが対になって「`draw()` から見える `pmouse` はちょうど 1 フレーム前」を保ちます。
    func updateFrame() {
        scrollX = 0
        scrollY = 0

        if _isFirstFrame {
            // 起動直後は「前フレーム」が無い。原点から現在位置への線が引かれないよう
            // 現在位置を入れる（Processing の 1 フレーム目と同じ扱い）。
            pmouseX = mouseX
            pmouseY = mouseY
            _isFirstFrame = false
        } else {
            pmouseX = _savedMouseX
            pmouseY = _savedMouseY
        }
    }

    /// フレームの終わりに、`draw()` が見ていたマウス座標を次フレームの `pmouse` 用に保存します。
    ///
    /// ``updateFrame()`` の側（フレーム頭）で保存すると、イベントがフレームのどこで
    /// 処理されるかによって 1 フレームぶん余計にずれます（`pmouse` が 2 フレーム前になる）。
    /// 保存を `draw()` の後に置くことで、イベントの到着位置に依存しなくなります。
    func endFrame() {
        _savedMouseX = mouseX
        _savedMouseY = mouseY
    }

    // MARK: - Event Handlers (called from MetaphorMTKView)

    /// マウスボタン押下イベントの処理
    func handleMouseDown(x: Float, y: Float, button: MouseButton) {
        mouseX = x
        mouseY = y
        isMouseDown = true
        mouseButton = button
        _didDragSinceMouseDown = false
        onMousePressed?(x, y, button)
    }

    /// マウスボタン解放イベントの処理
    func handleMouseUp(x: Float, y: Float, button: MouseButton) {
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
        // 最後に押されたキーの解放（または全キー解放）でリピートフラグを戻す
        if keyCode == lastKeyCode || pressedKeys.isEmpty {
            isKeyRepeat = false
        }
        onKeyUp?(keyCode)
    }

    /// 修飾キー状態変化イベントの処理。
    ///
    /// 修飾キーは `keyDown`/`keyUp` を発生させないため、`flagsChanged` から
    /// 各修飾キーの押下状態を `pressedKeys` に同期します（`isKeyDown(SHIFT)` 等を
    /// 機能させる）。左右どちらのキーでも `SHIFT`/`CONTROL`/`OPTION`/`COMMAND` の
    /// 正規キーコードで報告されます。コールバック（onKeyDown/onKeyUp）は
    /// 文字キー用のため発火しません。
    func handleFlagsChanged(shift: Bool, control: Bool, option: Bool, command: Bool) {
        syncModifier(keyCode: SHIFT, isDown: shift)
        syncModifier(keyCode: CONTROL, isDown: control)
        syncModifier(keyCode: OPTION, isDown: option)
        syncModifier(keyCode: COMMAND, isDown: command)
    }

    /// 修飾キー 1 つの押下状態を `pressedKeys` に反映します。
    private func syncModifier(keyCode: UInt16, isDown: Bool) {
        if isDown {
            pressedKeys.insert(keyCode)
        } else {
            pressedKeys.remove(keyCode)
        }
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

    /// ファイルドロップイベントを処理します。
    func handleFileDrop(paths: [String]) {
        onFileDrop?(paths)
        onFileDropInternal?(paths)
    }
}
