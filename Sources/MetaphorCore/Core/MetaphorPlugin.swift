import Metal

// MARK: - プラグインイベント型

/// プラグインに配信されるマウスイベントの種類
public enum MouseEventType: Sendable {
    case pressed
    case released
    case moved
    case dragged
    case scrolled
    case clicked
}

/// プラグインに配信されるキーボードイベントの種類
public enum KeyEventType: Sendable {
    case pressed
    case released
}

// MARK: - MetaphorPlugin プロトコル

/// metaphor レンダリングライフサイクルにフックするプラグイン
///
/// プラグインはフレームサイクルの重要なポイントでコールバックを受け取り、
/// Syphon 出力、NDI ストリーミング、カスタム録画などの機能を
/// コアレンダラーを変更せずに実現できます。
///
/// ``Sketch/registerPlugin(_:)`` または ``SketchConfig/plugins`` でプラグインを登録します。
///
/// ```swift
/// final class MyPlugin: MetaphorPlugin {
///     let pluginID = "com.example.myplugin"
///
///     func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
///         // レンダリング済みフレームを処理
///     }
/// }
/// ```
@MainActor
public protocol MetaphorPlugin: AnyObject {
    /// このプラグインの一意な識別子
    var pluginID: String { get }

    // MARK: - ライフサイクル

    /// プラグインがスケッチに登録された時に一度呼ばれます。
    ///
    /// sketch 参照を通じてレンダラー、入力状態、キャンバス、
    /// および全スケッチプロパティ (width, height, mouseX, frameCount 等) にアクセスできます。
    /// - Parameter sketch: このプラグインが接続されるスケッチ
    func onAttach(sketch: any Sketch)

    /// プラグインがレンダラーに登録された時に一度呼ばれます (レガシー)。
    ///
    /// 新しいプラグインでは ``onAttach(sketch:)`` を推奨します。このメソッドは
    /// ``MetaphorRenderer/addPlugin(_:)`` 経由で登録された場合の後方互換性のために呼ばれます。
    /// - Parameter renderer: このプラグインが接続されるレンダラー
    func onAttach(renderer: MetaphorRenderer)

    /// プラグインがレンダラーから削除された時に一度呼ばれます。
    func onDetach()

    // MARK: - フレームフック

    /// 各フレームの開始時、レンダリング前に呼ばれます。
    ///
    /// シミュレーション状態の更新などのプリフレームロジックに使用します。
    /// - Parameters:
    ///   - commandBuffer: 現在のフレームのコマンドバッファ
    ///   - time: スケッチ開始からの経過時間（秒）
    func pre(commandBuffer: MTLCommandBuffer, time: Double)

    /// フレームがオフスクリーンテクスチャにレンダリングされた後に呼ばれます。
    ///
    /// キャプチャやストリーミング出力などのポストフレームロジックに使用します。
    /// - Parameters:
    ///   - texture: 最終レンダリングテクスチャ（ポストプロセス後）
    ///   - commandBuffer: 現在のフレームのコマンドバッファ
    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer)

    /// レンダーループ開始時に呼ばれます。
    func onStart()

    /// レンダーループ停止時に呼ばれます。
    func onStop()

    // MARK: - 入力イベント

    /// マウスイベント発生時に呼ばれます。
    ///
    /// - Parameters:
    ///   - x: スケッチ座標系でのマウス x 位置
    ///   - y: スケッチ座標系でのマウス y 位置
    ///   - button: マウスボタン番号 (0 = 左, 1 = 右, 2 = その他)
    ///   - type: マウスイベントの種類
    func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType)

    /// キーボードイベント発生時に呼ばれます。
    ///
    /// - Parameters:
    ///   - key: 押された文字。非文字キーの場合は `nil`
    ///   - keyCode: 仮想キーコード
    ///   - type: キーボードイベントの種類
    func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType)

    // MARK: - キャンバスイベント

    /// キャンバスがリサイズされた時に呼ばれます。
    /// - Parameters:
    ///   - width: 新しい幅（ピクセル）
    ///   - height: 新しい高さ（ピクセル）
    func onResize(width: Int, height: Int)

    // MARK: - レガシー (非推奨)

    /// 各フレームの開始時、レンダリング前に呼ばれます。
    @available(*, deprecated, renamed: "pre(commandBuffer:time:)")
    func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double)

    /// フレームがオフスクリーンテクスチャにレンダリングされた後に呼ばれます。
    @available(*, deprecated, renamed: "post(texture:commandBuffer:)")
    func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer)
}

// MARK: - デフォルト実装

extension MetaphorPlugin {
    public func onAttach(sketch: any Sketch) {}
    public func onAttach(renderer: MetaphorRenderer) {}
    public func onDetach() {}
    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}
    public func onStart() {}
    public func onStop() {}
    public func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {}
    public func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {}
    public func onResize(width: Int, height: Int) {}
    public func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}
}
