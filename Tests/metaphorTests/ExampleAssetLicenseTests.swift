import Foundation
import Testing

/// `Examples/` に持ち込んだ第三者素材のライセンスを機械的に守る（Issue #1190）。
///
/// リポジトリ全体は MIT だが、Processing のサンプルから移植する過程で、原典の
/// アセットがそのまま `Examples/**/data/` へ入ってくる。素材を 1 本足す操作は
/// ビルドにもテストにも現れないため、`THIRD_PARTY_LICENSES.md` への追記漏れも、
/// MIT と両立しないライセンスの混入も、誰にも気付かれないまま出荷されてしまう。
/// 実際 GPLv2 / LGPL-2.1 / CC BY-NC-SA を名乗る 8 ファイルがそうなっていた。
///
/// `FontLicenseTests` と同じ方針で、`git ls-files` が返す再頒布対象を走査する。
@Suite("Bundled example asset licenses")
struct ExampleAssetLicenseTests {

    // MARK: - 非互換ライセンスの混入

    /// MIT が吸収できないライセンスの名乗り。
    ///
    /// 語境界まで見るのは、本文中の無関係な語に当たるのを避けるため
    /// （`dracula.txt` の "gangplank" が素の `GPL` に引っかかった）。
    private static let incompatibleDeclarations: [(name: String, pattern: String)] = [
        ("GNU General Public License", #"GNU\s+General\s+Public\s+License"#),
        ("GNU Lesser General Public License", #"GNU\s+Lesser\s+General\s+Public\s+License"#),
        ("GPL / LGPL の短縮表記", #"\b(?:L?GPL)(?:v?[23])?\b"#),
        ("Creative Commons NonCommercial", #"NonCommercial"#),
    ]

    /// 検査から外すパス。**ライセンスの例外ではなく、検査対象そのものではないもの**に限る。
    ///
    /// ここに素材を足して緑に戻す使い方をしない。非互換ライセンスの素材は、
    /// 例外を書くのではなく取り除くのが唯一の対処になる。
    private static func isOutOfScope(_ path: String) -> Bool {
        // OFL.txt はフォントのライセンス全文そのもの。第 5 条が GPL に言及する。
        if path.hasSuffix("/OFL.txt") { return true }
        // `Examples/**/*.md` は metaphor 自身が書いた解説文で、再頒布している素材ではない。
        // ライセンスを **名乗る** のではなく **説明する** ので当たってしまう
        // （`Topics/Shaders/README.md` は GPLv2 / LGPL の GLSL を外した経緯を書いている）。
        // 素材そのものは対象に残るので、非互換ファイルの混入は従来どおり捕まる。
        if path.hasSuffix(".md") { return true }
        return false
    }

    @Test("Examples 配下に MIT 非互換ライセンスを名乗るファイルが無い")
    func noIncompatibleLicenseDeclarations() throws {
        let files = try CheckedInFiles.list("Examples")
        // 走査そのものが壊れて 0 件になったら（= 常に緑）気付けないので下限を置く。
        #expect(files.count >= 1000, "Examples の走査が効いていない: \(files.count) 件")

        var offenders: [String] = []
        for path in files where !Self.isOutOfScope(path) {
            guard let text = CheckedInFiles.readText(path) else { continue }
            for declaration in Self.incompatibleDeclarations
            where text.range(of: declaration.pattern, options: .regularExpression) != nil {
                offenders.append("\(path) → \(declaration.name)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            MIT と両立しないライセンスを名乗るファイルが Examples 配下にある: \(offenders)
            この検査に例外は置かない。GPL / LGPL / CC BY-NC の素材は MIT のリポジトリでは
            再頒布できないので、記載を足すのではなくファイルごと取り除く（Issue #1190）。
            移植の参考にしたいだけなら、原典の upstream URL をコメントで指せば足りる。
            """)
    }

    // MARK: - Processing 原典の帰属

    /// `THIRD_PARTY_LICENSES.md` が名指ししている原著者。
    ///
    /// 表を正本にして走査するので、**表に無い著者のファイルが増えると本数が合わずに赤くなる**。
    /// 著者名リストをテスト側に隠し持つと、記載と検査が別々に育って食い違う。
    private static func creditedAuthors() throws -> [String] {
        let notices = try #require(
            CheckedInFiles.readText("THIRD_PARTY_LICENSES.md"),
            "THIRD_PARTY_LICENSES.md が読めない")
        // 「The credited `.pde` authors」の直後に来る `| 著者 | 本数 |` の表を読む。
        let heading = "The credited `.pde` authors, as their own headers name them:"
        let table = try #require(
            notices.range(of: heading).map { notices[$0.upperBound...] },
            "著者の表が見つからない（見出しを変えたなら、この検査の見出しも合わせる）")

        var authors: [String] = []
        for line in table.split(separator: "\n") {
            guard line.hasPrefix("|") else {
                // 表が終わったら止める（先頭の区切り行 2 本は空振りして通過する）。
                if !authors.isEmpty { break } else { continue }
            }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3, !cells[1].isEmpty, Int(cells[2]) != nil else { continue }
            authors.append(cells[1])
        }
        return authors
    }

    /// `THIRD_PARTY_LICENSES.md` の本文から `| ラベル | 総数 | クレジットあり |` を読む。
    private static func recordedCounts(forRow label: String) throws -> (total: Int, credited: Int) {
        let notices = try #require(
            CheckedInFiles.readText("THIRD_PARTY_LICENSES.md"),
            "THIRD_PARTY_LICENSES.md が読めない")
        for line in notices.split(separator: "\n") where line.hasPrefix("| `\(label)` |") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count >= 4, let total = Int(cells[2]), let credited = Int(cells[3]) {
                return (total, credited)
            }
        }
        Issue.record("THIRD_PARTY_LICENSES.md に `\(label)` の件数の行が無い")
        return (-1, -1)
    }

    @Test("`.pde` の本数とクレジットありの内訳が THIRD_PARTY_LICENSES.md と一致する")
    func pdeCountsMatchTheRecord() throws {
        let authors = try Self.creditedAuthors()
        #expect(authors.count >= 10, "著者の表が読めていない: \(authors)")

        let sketches = try CheckedInFiles.list("Examples").filter { $0.hasSuffix(".pde") }
        let credited = sketches.filter { path in
            guard let text = CheckedInFiles.readText(path) else { return false }
            return authors.contains { text.localizedCaseInsensitiveContains($0) }
        }

        let recorded = try Self.recordedCounts(forRow: ".pde")
        #expect(
            (sketches.count, credited.count) == (recorded.total, recorded.credited),
            """
            `.pde` の実測 \(sketches.count) 本（うちクレジットあり \(credited.count) 本）が
            THIRD_PARTY_LICENSES.md の記載 \(recorded.total) / \(recorded.credited) と合わない。
            サンプルを足したか消したなら記載を更新する。クレジット行に**表に無い著者**が
            現れた場合も合わなくなるので、その著者を表へ足す（Issue #1191）。
            """)
    }

    @Test("`.json` の本数と author ありの内訳が THIRD_PARTY_LICENSES.md と一致する")
    func jsonCountsMatchTheRecord() throws {
        let metadata = try CheckedInFiles.list("Examples").filter { $0.hasSuffix(".json") }
        let credited = metadata.filter { path in
            guard let text = CheckedInFiles.readText(path) else { return false }
            return text.range(of: #""author"\s*:\s*"[^"]"#, options: .regularExpression) != nil
        }

        let recorded = try Self.recordedCounts(forRow: ".json")
        #expect(
            (metadata.count, credited.count) == (recorded.total, recorded.credited),
            """
            `.json` の実測 \(metadata.count) 本（うち author が非空 \(credited.count) 本）が
            THIRD_PARTY_LICENSES.md の記載 \(recorded.total) / \(recorded.credited) と合わない。
            """)
    }

    // MARK: - 適用範囲の宣言

    @Test("THIRD_PARTY_LICENSES.md が『フォント 3 本だけ』へ戻っていない")
    func theNoticeDoesNotUnderstateItsScope() throws {
        let notices = try #require(CheckedInFiles.readText("THIRD_PARTY_LICENSES.md"))
        #expect(
            !notices.contains("in one place"),
            """
            冒頭が「metaphor が再頒布する第三者素材は 1 か所（フォント 3 本）だけ」に戻っている。
            実際にはフォント・Processing 原典・example のメディア・PD テキストの 4 系統がある
            （Issue #1190）。
            """)
        for section in ["## Processing example originals", "## Public-domain texts"] {
            #expect(notices.contains(section), "\(section) の節が失われている")
        }
    }

    @Test("Examples/NOTICE.md がクレジット行のあるサンプルを public domain と言っていない")
    func theExamplesNoticeDoesNotOverclaimPublicDomain() throws {
        let notice = try #require(CheckedInFiles.readText("Examples/NOTICE.md"))
        // upstream が public domain と言うのは「クレジット行の無いもの」だけ。
        // 特定の著者を名指しで public domain 側に置く記述は、そこと食い違う
        // （かつて「Daniel Shiffman's examples are also in the public domain」と書いていた）。
        let authors = try Self.creditedAuthors()
        for author in authors {
            let overclaims = notice.range(
                of: "\(author)[^.]*public domain", options: [.regularExpression, .caseInsensitive])
            #expect(
                overclaims == nil,
                """
                Examples/NOTICE.md が \(author) のサンプルを public domain と書いている。
                processing-examples の README が public domain と言うのはクレジット行の無い
                ものだけで、\(author) は THIRD_PARTY_LICENSES.md の credited 側にいる。
                """)
        }
    }
}
