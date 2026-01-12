import Foundation

/// マウスボタンの種類
public enum MouseButton: Sendable {
    case none
    case left
    case right
    case center
}

/// 入力状態のスナップショット（Sendable）
/// GraphicsContextに渡されて描画中に参照される
public struct InputSnapshot: Sendable {
    public let mouseX: Float
    public let mouseY: Float
    public let pmouseX: Float
    public let pmouseY: Float
    public let isMousePressed: Bool
    public let mouseButton: MouseButton
    public let isKeyPressed: Bool
    public let key: Character
    public let keyCode: UInt16

    public static let empty = InputSnapshot(
        mouseX: 0, mouseY: 0,
        pmouseX: 0, pmouseY: 0,
        isMousePressed: false,
        mouseButton: .none,
        isKeyPressed: false,
        key: "\0",
        keyCode: 0
    )
}

/// 入力状態を管理するクラス
/// Processing互換のマウス・キーボード状態を提供
@MainActor
public final class InputState: ObservableObject {
    // MARK: - Mouse State

    /// 現在のマウスX座標
    @Published public private(set) var mouseX: Float = 0

    /// 現在のマウスY座標
    @Published public private(set) var mouseY: Float = 0

    /// 前フレームのマウスX座標
    @Published public private(set) var pmouseX: Float = 0

    /// 前フレームのマウスY座標
    @Published public private(set) var pmouseY: Float = 0

    /// マウスボタンが押されているか
    @Published public private(set) var isMousePressed: Bool = false

    /// 押されているマウスボタン
    @Published public private(set) var mouseButton: MouseButton = .none

    // MARK: - Keyboard State

    /// キーが押されているか
    @Published public private(set) var isKeyPressed: Bool = false

    /// 最後に押されたキー（文字）
    @Published public private(set) var key: Character = "\0"

    /// 最後に押されたキーコード
    @Published public private(set) var keyCode: UInt16 = 0

    // MARK: - Canvas Info

    /// キャンバスの幅
    public let canvasWidth: Float

    /// キャンバスの高さ
    public let canvasHeight: Float

    public init(canvasWidth: Float, canvasHeight: Float) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    // MARK: - Snapshot

    /// 現在の入力状態のスナップショットを取得
    public func snapshot() -> InputSnapshot {
        InputSnapshot(
            mouseX: mouseX,
            mouseY: mouseY,
            pmouseX: pmouseX,
            pmouseY: pmouseY,
            isMousePressed: isMousePressed,
            mouseButton: mouseButton,
            isKeyPressed: isKeyPressed,
            key: key,
            keyCode: keyCode
        )
    }

    // MARK: - Mouse Update Methods

    /// マウス位置を更新（ビュー座標からキャンバス座標に変換）
    public func updateMousePosition(viewX: CGFloat, viewY: CGFloat, viewWidth: CGFloat, viewHeight: CGFloat) {
        // 前フレームの位置を保存
        pmouseX = mouseX
        pmouseY = mouseY

        // ビュー座標をキャンバス座標に変換
        // アスペクト比を考慮した変換
        let canvasAspect = canvasWidth / canvasHeight
        let viewAspect = Float(viewWidth / viewHeight)

        let scaleX: Float
        let scaleY: Float
        let offsetX: Float
        let offsetY: Float

        if viewAspect > canvasAspect {
            // ピラーボックス（左右に黒帯）
            let displayWidth = Float(viewHeight) * canvasAspect
            scaleX = canvasWidth / displayWidth
            scaleY = canvasHeight / Float(viewHeight)
            offsetX = (Float(viewWidth) - displayWidth) / 2
            offsetY = 0
        } else {
            // レターボックス（上下に黒帯）
            let displayHeight = Float(viewWidth) / canvasAspect
            scaleX = canvasWidth / Float(viewWidth)
            scaleY = canvasHeight / displayHeight
            offsetX = 0
            offsetY = (Float(viewHeight) - displayHeight) / 2
        }

        mouseX = (Float(viewX) - offsetX) * scaleX
        mouseY = (Float(viewY) - offsetY) * scaleY

        // キャンバス範囲内にクランプ
        mouseX = max(0, min(canvasWidth, mouseX))
        mouseY = max(0, min(canvasHeight, mouseY))
    }

    /// マウスボタンが押された
    public func mouseDown(button: MouseButton) {
        isMousePressed = true
        mouseButton = button
    }

    /// マウスボタンが離された
    public func mouseUp() {
        isMousePressed = false
        mouseButton = .none
    }

    // MARK: - Keyboard Update Methods

    /// キーが押された
    public func keyDown(character: Character, keyCode: UInt16) {
        isKeyPressed = true
        self.key = character
        self.keyCode = keyCode
    }

    /// キーが離された
    public func keyUp() {
        isKeyPressed = false
    }

    // MARK: - Frame Update

    /// フレーム開始時に呼ばれる（前フレームの値を更新）
    public func beginFrame() {
        // pmouseX/pmouseYは既にupdateMousePositionで更新されているので
        // ここでは特に何もしない
    }
}
