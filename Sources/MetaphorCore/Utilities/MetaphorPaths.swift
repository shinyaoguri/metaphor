import Foundation

/// Resolves the **base directory** for the file contracts under `.metaphor/`
/// (Probe / Parameter Store / State) (Issue #688, CONTRACT.md contract point 2).
///
/// These used to be resolved relative to the process's current working directory. With
/// `swift run` the cwd is the project root, so nothing goes wrong, but **launching a
/// `.app` from LaunchServices makes the cwd `/`**, which points both Probe and the
/// Parameter Store at a location they cannot write to. In setups closer to permanent
/// operation (launched with `open`, as a login item, or from the Dock), this breaks as a
/// request that never receives a response and parameters that never persist.
///
/// Setting a base directory in `METAPHOR_STATE_DIR` resolves relative paths from there.
/// **When it is unset the behavior stays relative to the cwd**, so the existing contract
/// is unchanged (additive).
///
/// ```bash
/// open -n .build/strata.app --env METAPHOR_PROBE=1 --env "METAPHOR_STATE_DIR=$PWD"
/// ```
enum MetaphorPaths {
    /// The name of the environment variable that supplies the base directory (contract point 2).
    static let stateDirectoryEnvironmentKey = "METAPHOR_STATE_DIR"

    /// The base directory against which `.metaphor/` is resolved.
    ///
    /// `METAPHOR_STATE_DIR` when it is set (a relative value is made absolute against the
    /// cwd, and `~` is expanded), otherwise the cwd. Evaluated once when the process
    /// starts, so that the location of the contract files never moves mid-run even if a
    /// sketch changes the cwd after launch.
    static let baseDirectory: String = resolveBaseDirectory(
        environment: ProcessInfo.processInfo.environment,
        currentDirectory: FileManager.default.currentDirectoryPath
    )

    /// Resolves the path of a contract file. An absolute path is returned as is; a
    /// relative path is made absolute against ``baseDirectory``.
    static func resolve(_ path: String) -> String {
        resolve(path, base: baseDirectory)
    }

    // MARK: - 純粋な実装（テスト用に環境から切り離してある）

    /// Determines the base directory from the environment and the cwd.
    static func resolveBaseDirectory(
        environment: [String: String], currentDirectory: String
    ) -> String {
        guard let raw = environment[stateDirectoryEnvironmentKey],
            !raw.trimmingCharacters(in: .whitespaces).isEmpty
        else {
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

    /// Resolves a path against the given base.
    static func resolve(_ path: String, base: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return expanded }
        return URL(fileURLWithPath: base)
            .appendingPathComponent(expanded).standardized.path
    }
}
