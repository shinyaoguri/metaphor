import Foundation

/// リポジトリに checked in されたファイルの一覧を `git ls-files` から取る。
///
/// ワーキングツリーを `FileManager.enumerator` で舐めるのではなく git に聞く。
/// 「このリポジトリが再頒布しているもの」を数えたいのであって、手元に落ちている
/// ビルド生成物やキャッシュを数えたいわけではないからで、こうしておけば
/// gitignore 済みのものが将来どこに増えても除外リストを育て続けずに済む
/// （Issue #957）。`FontLicenseTests` と `ExampleAssetLicenseTests` が共有する。
enum CheckedInFiles {

    /// リポジトリルート。`Tests/metaphorTests/` から 3 つ上。
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/metaphorTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // リポジトリルート

    /// `git ls-files` の起動・実行に失敗したことを表す。
    ///
    /// 走査できなかったときに「0 件 = 全部きれい」と読めてしまうのが最悪なので、
    /// 黙って空配列を返さずテストを失敗させる。
    struct GitListingFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// checked in された全ファイルを、ルートからの相対パスで返す。
    ///
    /// - Parameter pathspec: `git ls-files` に渡す絞り込み（省略時はリポジトリ全体）。
    static func list(_ pathspec: String? = nil) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // `-z` は NUL 区切り。`Examples/Topics/Advanced Data/` のように空白を含むパスがある。
        var arguments = ["git", "ls-files", "-z"]
        if let pathspec { arguments.append(pathspec) }
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot.standardizedFileURL

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw GitListingFailure(description: "git ls-files を起動できなかった: \(error)")
        }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitListingFailure(
                description: """
                    git ls-files が失敗した（終了コード \(process.terminationStatus)）: \(message)
                    このテストは git の管理対象を正本にするので、走査できないときは緑にしない。
                    """)
        }

        return
            String(decoding: stdout, as: UTF8.self)
            .split(separator: "\0")
            .map(String.init)
            .sorted()
    }

    /// ルートからの相対パスをテキストとして読む。読めなければ `nil`。
    ///
    /// バイナリ（画像・フォント・動画）を走査対象に含めたまま本文を検査したいので、
    /// UTF-8 として読めないファイルは「検査対象外」として素通りさせる。
    static func readText(_ relativePath: String) -> String? {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
