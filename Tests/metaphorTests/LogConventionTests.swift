import Foundation
import Testing
import metaphor

/// 診断ログ（`metaphorWarning` / `metaphorAlert` / `metaphorDiagnostic`）の
/// 「どこからでも同じ口を使う」という規約を機械的に守る（Issue #805）。
///
/// 以前は 3 関数が `MetaphorCore` の internal だったため、アンブレラ
/// （`Sources/metaphor/`）や Tier 1 モジュールからは物理的に呼べず、
/// 同種の入口ガードでも `print("[metaphor] Warning: …")` の直書きに割れていた。
@Suite("Log conventions")
struct LogConventionTests {

    @Test("診断ログ 3 種は MetaphorCore の外からも呼べる")
    func logFunctionsAreVisibleOutsideCore() {
        // 「別モジュールから呼べる」ことの検証はコンパイルが通ること自体。
        // `metaphorWarning`（DEBUG）と `metaphorAlert`（常時）は必ず出力するので、
        // テストログを汚さないよう参照だけして実行はしない
        // （Swift Testing は並列実行のため、出力の捕捉でも代用できない）。
        let emitters: [() -> Void] = [
            { metaphorWarning("unused") },
            { metaphorAlert("unused") },
        ]
        #expect(emitters.count == 2)

        // `metaphorDiagnostic` は `METAPHOR_DEBUG=1` のときだけ出力するので、
        // 未設定の CI / ローカルでは無出力のまま経路を実際に通せる。
        metaphorDiagnostic("#805 cross-module visibility check")
    }

    @Test("MetaphorCore の外に print(\"[metaphor] …\") の直書きが残っていない")
    func noRawMetaphorPrintOutsideCore() throws {
        // テストリソース経由ではなくソースツリーを直接見る（GoldenImageTests と同じ方針）。
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/metaphorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // リポジトリルート
            .appendingPathComponent("Sources", isDirectory: true)
        try #require(FileManager.default.fileExists(atPath: sourcesRoot.path))

        // 除外は 2 つだけ。
        // - `MetaphorLog`: 3 関数の実体そのもの（ここでしか print を書かない）。
        // - `MetaphorCore`: Release でも見えるべき診断（Probe の書き出し失敗など）が
        //   残っており一括変換できない。ここで守るのは「Core の外は共通の口を使う」。
        let exempt = ["MetaphorLog", "MetaphorCore"].map {
            sourcesRoot.appendingPathComponent($0, isDirectory: true).path + "/"
        }

        var offenders: [String] = []
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !exempt.contains(where: { url.path.hasPrefix($0) }) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() where line.contains("print(\"[metaphor]") {
                // 規約そのものを説明するコメント（`print("[metaphor] …") は使わない` 等）は
                // 違反ではないので数えない。
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") else { continue }
                let relative = url.path.replacingOccurrences(of: sourcesRoot.path + "/", with: "")
                offenders.append("\(relative):\(index + 1)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            MetaphorCore 外で print("[metaphor] …") を直書きしています。
            metaphorWarning / metaphorAlert / metaphorDiagnostic を使ってください（#805）:
            \(offenders.sorted().joined(separator: "\n"))
            """)
    }
}
