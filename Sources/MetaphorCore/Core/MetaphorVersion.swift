import Foundation

/// metaphor ライブラリのランタイム情報。
///
/// スケッチが「いまどの metaphor 版で動いているか」を実行時に知るための情報を提供する。
/// 後からログを見たときにバージョンの取り違えを防ぐのが目的。
public enum Metaphor {
    /// metaphor ライブラリのバージョン文字列（例: `0.2.4`、プレリリースは `0.3.0-beta.1`）。
    ///
    /// この値は Release ワークフローがリリースのたびに書き換える（`release.yml` の
    /// version-bump コミット）。手で編集しないこと。リリース間の `main` では直近の
    /// リリース版を指す。
    public static let version = "0.5.3"

    /// バージョンを1行で表す表記（例: `metaphor 0.2.4`）。
    public static var identifier: String {
        "metaphor \(version)"
    }
}
