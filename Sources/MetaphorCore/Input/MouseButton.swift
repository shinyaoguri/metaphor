/// マウスのボタン種別。
///
/// Processing の `mouseButton == LEFT` に相当する判定は、metaphor では
/// ``Sketch/mouseButton`` と本 enum の比較で書きます。
///
/// ```swift
/// if mousePressed && mouseButton == .left {
///     // 左ボタンをドラッグ中の処理
/// }
/// ```
///
/// - Note: Processing の `LEFT` / `RIGHT` / `CENTER` は metaphor では
///   **キーコード定数**（`LEFT: UInt16 = 123` は左矢印キー）であり、マウス
///   ボタンではありません。以前 ``Sketch/mouseButton`` は `Int` だったため
///   `mouseButton == LEFT` が異種整数比較として合法になり、コンパイルも警告も
///   通ったうえで常に `false` になっていました（Issue #382）。型を分けたことで
///   この書き間違いはコンパイルエラーになります。
public enum MouseButton: Sendable, Hashable, CaseIterable {
    /// 左ボタン。
    case left
    /// 右ボタン。
    case right
    /// 中ボタン（ホイールクリック等）。
    case middle

    /// `0 = 左` / `1 = 右` / `2 = 中` のインデックス表現から生成します。
    ///
    /// AppKit のイベント種別や、`metaphor-cli` から届く stdin JSON Lines の
    /// `button` フィールド（CONTRACT.md 契約点 3）のように、整数でボタンを
    /// 表現する境界で使います。
    ///
    /// - Parameter index: ボタンインデックス。
    /// - Returns: 対応するボタン。未知のインデックスなら `nil`。
    public init?(index: Int) {
        switch index {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: return nil
        }
    }

    /// `0 = 左` / `1 = 右` / `2 = 中` のインデックス表現。
    public var index: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        }
    }
}
