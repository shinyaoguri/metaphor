import Foundation

/// `.metaphor/` 配下のファイル契約（Probe / Parameter Store / State）の
/// **基準ディレクトリ**を解決します（Issue #688・CONTRACT.md 契約点 2）。
///
/// これらは従来プロセスの cwd 相対で解決されていました。`swift run` ならプロジェクト
/// 直下が cwd になるので問題になりませんが、**`.app` を LaunchServices から起動すると
/// cwd が `/`** になり、Probe も Parameter Store も書けない場所を向きます。常設運用に
/// 近い形（`open` で起動 / ログイン項目 / Dock から起動）では、リクエストを置いても
/// 永遠に応答が来ない・パラメータの永続化が効かない、という壊れ方をします。
///
/// `METAPHOR_STATE_DIR` に基準ディレクトリを与えると、相対パスはそこから解決されます。
/// **未設定なら従来どおり cwd 相対**なので、既存の契約は変わりません（additive）。
///
/// ```bash
/// open -n .build/strata.app --env METAPHOR_PROBE=1 --env "METAPHOR_STATE_DIR=$PWD"
/// ```
enum MetaphorPaths {
    /// 基準ディレクトリを与える環境変数の名前（契約点 2）。
    static let stateDirectoryEnvironmentKey = "METAPHOR_STATE_DIR"

    /// `.metaphor/` を解決する基準ディレクトリ。
    ///
    /// `METAPHOR_STATE_DIR` があればそれ（相対なら cwd 基準で絶対化、`~` は展開）、
    /// 無ければ cwd。プロセス起動時に 1 度だけ評価します（起動後に cwd を変える
    /// スケッチがあっても、契約ファイルの置き場が途中で動かないように）。
    static let baseDirectory: String = resolveBaseDirectory(
        environment: ProcessInfo.processInfo.environment,
        currentDirectory: FileManager.default.currentDirectoryPath
    )

    /// 契約ファイルのパスを解決します。絶対パスはそのまま、相対パスは
    /// ``baseDirectory`` からの相対として絶対化します。
    static func resolve(_ path: String) -> String {
        resolve(path, base: baseDirectory)
    }

    // MARK: - 純粋な実装（テスト用に環境から切り離してある）

    /// 環境変数と cwd から基準ディレクトリを決めます。
    static func resolveBaseDirectory(
        environment: [String: String], currentDirectory: String
    ) -> String {
        guard let raw = environment[stateDirectoryEnvironmentKey],
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return currentDirectory
        }
        let expanded = NSString(string: raw).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            // 相対指定は cwd 基準で絶対化する（consumer 側が cwd を変えても揺れない）。
            return URL(fileURLWithPath: currentDirectory)
                .appendingPathComponent(expanded).standardized.path
        }
        return URL(fileURLWithPath: expanded).standardized.path
    }

    /// 与えた基準でパスを解決します。
    static func resolve(_ path: String, base: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return expanded }
        return URL(fileURLWithPath: base)
            .appendingPathComponent(expanded).standardized.path
    }
}
