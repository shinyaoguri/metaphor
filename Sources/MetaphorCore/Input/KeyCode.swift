/// macOS の仮想キーコード定数の名前空間。
///
/// ``Sketch/keyCode`` との比較に使います。値はモジュール直下のグローバル定数
/// （`LEFT` / `RETURN` など Processing 互換の大文字名）と同じで、書き方が違うだけです。
///
/// ```swift
/// if keyCode == KeyCode.space {
///     // スペースキーが押された
/// }
/// ```
///
/// - Important: `import Foundation` を併用するスケッチでは、グローバル定数のうち
///   `RETURN` / `TAB` / `BACKSPACE` / `CONTROL` の 4 つが Darwin の `sys/tty.h` にある
///   同名マクロと衝突して `ambiguous use of 'RETURN'` になります。`metaphor` は Foundation を
///   `@_exported import` しているため `metaphor.RETURN` と修飾しても絞れません
///   （効くのは `let r: UInt16 = RETURN` のような型注釈だけ）。
///   `KeyCode.return` のように本名前空間を経由すれば衝突は起きません（Issue #794）。
///
/// - Note: `Sketch` の `saveState()` / `restoreState(_:)` は `Data` を取るので、
///   状態保持リロードを使うスケッチは Foundation を避けられません。キー入力と状態保存を
///   両方使うときは本名前空間を使ってください。
public enum KeyCode {
    // MARK: - 矢印キー

    /// 左矢印キー。
    public static let left: UInt16 = 123
    /// 右矢印キー。
    public static let right: UInt16 = 124
    /// 下矢印キー。
    public static let down: UInt16 = 125
    /// 上矢印キー。
    public static let up: UInt16 = 126

    // MARK: - 編集・空白キー

    /// Return キー。
    ///
    /// グローバル定数 `RETURN` は `import Foundation` 併用時に曖昧になります。
    public static let `return`: UInt16 = 36
    /// テンキーの Enter キー。
    public static let enter: UInt16 = 76
    /// Tab キー。
    ///
    /// グローバル定数 `TAB` は `import Foundation` 併用時に曖昧になります。
    public static let tab: UInt16 = 48
    /// Space キー。
    public static let space: UInt16 = 49
    /// Backspace (Delete) キー。カーソルの手前を消す方。
    ///
    /// グローバル定数 `BACKSPACE` は `import Foundation` 併用時に曖昧になります。
    public static let backspace: UInt16 = 51
    /// Forward Delete キー。カーソルの後ろを消す方。
    public static let delete: UInt16 = 117
    /// Escape キー。
    public static let escape: UInt16 = 53

    // MARK: - 修飾キー

    /// Shift キー。
    public static let shift: UInt16 = 56
    /// Control キー。
    ///
    /// グローバル定数 `CONTROL` は `import Foundation` 併用時に曖昧になります。
    public static let control: UInt16 = 59
    /// Option キー。
    public static let option: UInt16 = 58
    /// Alt キー（``option`` のエイリアス。同じ仮想キーコードを指します）。
    public static let alt: UInt16 = option
    /// Command キー。
    public static let command: UInt16 = 55
}
