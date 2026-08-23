import Foundation

/// ヘッドレス（オフスクリーン）実行中であることを、どこに出すか。
///
/// ヘッドレス起動（`METAPHOR_VIEWER=1`）したスケッチはウィンドウを持たないため、
/// 何も出さないと **走っているのか・何本走っているのか・どう止めるのかが分かりません**
/// （既定では App Nap も抑止するので、見えないまま GPU を回し続けます）。この設定は
/// 「見えないプロセスが必ずどこかに現れ、そこから終了できる」ことを保証します。
///
/// 既定は ``menuBar`` です。バックグラウンドで走り続けるプロセスを表す macOS の
/// 作法に沿い、Dock を占有しません。環境変数 `METAPHOR_HEADLESS_INDICATOR`
/// （`menubar` / `dock` / `both` / `none`）を設定すると、ビルド済みのスケッチを
/// 再コンパイルせずにそちらが優先されます。
///
/// ```swift
/// var config: SketchConfig {
///     SketchConfig(headlessIndicator: .both)   // メニューバーと Dock の両方に出す
/// }
/// ```
///
/// > Note: `metaphor watch` はリビルドのたびに子プロセスを作り直すため、
/// > メニューバーの項目もそのたびに出入りします。気になる場合は ``hidden``
/// > （環境変数なら `METAPHOR_HEADLESS_INDICATOR=none`）で消せます。
///
/// ウィンドウを持つ通常実行には影響しません（Dock アイコンは従来どおり出ます）。
public enum HeadlessIndicator: String, Sendable, CaseIterable {
    /// メニューバーに状態項目を出す（既定）。
    ///
    /// クリックするとスケッチ名・PID・解像度・目標/実測 fps・経過時間・出力先が読め、
    /// そこからプロセスを終了できます。
    case menuBar = "menubar"

    /// Dock にアイコンを出す。
    ///
    /// Cmd+Tab にも現れ、Dock アイコンの右クリックから終了できます。
    case dock = "dock"

    /// メニューバーと Dock の両方に出す。
    case both = "both"

    /// どこにも出さない（従来の挙動）。
    case hidden = "hidden"

    /// メニューバーに状態項目を出すか。
    var showsMenuBarItem: Bool { self == .menuBar || self == .both }

    /// Dock にアイコンを出すか（`NSApplication.ActivationPolicy.regular`）。
    var showsDockIcon: Bool { self == .dock || self == .both }

    /// 環境変数の値を解釈します。
    ///
    /// 前後の空白と大文字小文字は無視し、綴りの揺れ（`menu-bar` / `none` / `off`）も
    /// 受け付けます。解釈できない値は `nil` を返します（呼び出し側が設定値へ
    /// フォールバックします）。
    ///
    /// - Parameter raw: 環境変数から読んだ生の文字列。
    /// - Returns: 対応する指標。解釈できなければ `nil`。
    static func parse(_ raw: String) -> HeadlessIndicator? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "menubar", "menu-bar", "menu", "statusitem": return .menuBar
        case "dock": return .dock
        case "both", "all": return .both
        case "hidden", "none", "off", "0": return .hidden
        default: return nil
        }
    }
}
