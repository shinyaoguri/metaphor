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

    // MARK: - Processing 原典のクレジット行

    /// `THIRD_PARTY_LICENSES.md` が「外した原典の著者」として名指ししている人たち。
    ///
    /// 表を正本にして走査するので、**表を消すとこの検査ごと落ちる**。著者名をテスト側に
    /// 隠し持つと、記載と検査が別々に育って食い違う。
    private static func removedAuthors() throws -> [String] {
        let notices = try #require(
            CheckedInFiles.readText("THIRD_PARTY_LICENSES.md"),
            "THIRD_PARTY_LICENSES.md が読めない")
        // 見出しの直後に来る `| 著者 | 本数 |` の表を読む。
        let heading = "The authors named by the sketches that were removed:"
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

    /// クレジット行の書式。コメント行の `by <Name>` と `based on (code from) <Name>`。
    ///
    /// 導入句をこの 2 つに絞ったのは実測の結果で、外した 144 本のうち 101 本をこれだけで
    /// 捕まえる。`adapted from` / `ported from` / `derived from` / `modified from` を
    /// 足しても捕捉は 1 本も増えず、`Topics/Shaders/Conway/Conway.pde` の
    /// 「ported from GLSL sandbox:」（人ではなくサイトを指す）を誤検出するだけだった。
    private static let creditLinePattern = #"(?:^|[\s,])(?:by|based on(?: code from)?)[ \t]+[A-Z]"#

    /// ソースの**コメント行**から、クレジット行らしきものを 1 本返す。
    ///
    /// コード行を見ないのは、`MouseFunctions.pde` の `by = height/2.0;` のような
    /// 代入に当たらないため。
    private static func creditLine(in source: String) -> String? {
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*") || line.hasPrefix("//") || line.hasPrefix("/*") else {
                continue
            }
            if line.range(of: Self.creditLinePattern, options: .regularExpression) != nil {
                return line
            }
        }
        return nil
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

    @Test("同梱している `.pde` にクレジット行が 1 本も無い")
    func bundledSketchesCarryNoCreditLine() throws {
        let sketches = try CheckedInFiles.list("Examples").filter { $0.hasSuffix(".pde") }
        // 走査そのものが壊れて 0 件になったら（= 常に緑）気付けないので下限を置く。
        #expect(sketches.count >= 100, "`.pde` の走査が効いていない: \(sketches.count) 件")

        var offenders: [String] = []
        for path in sketches {
            guard let text = CheckedInFiles.readText(path),
                let line = Self.creditLine(in: text)
            else { continue }
            offenders.append("\(path) → \(line)")
        }

        #expect(
            offenders.isEmpty,
            """
            クレジット行のある Processing 原典が Examples 配下にある: \(offenders)
            processing-examples の README が public domain と言うのはクレジット行の **無い**
            ものだけで、クレジット行のあるものは著作権が原著者に残ったままライセンスが
            付与されていない。MIT のこのリポジトリは再頒布できないので、帰属を書き足すのでは
            なく取り除く（Issue #1191）。原典を参照させたいなら、`App.swift` の先頭に
            upstream の URL を書く形にそろえる。
            """)
    }

    @Test("同梱している原典に、外した原典の著者の名前が現れない")
    func bundledOriginalsDoNotNameRemovedAuthors() throws {
        // 導入句を持たない裸の名前（`// Daniel Shiffman`）と、小文字始まりのハンドル
        // （`by hbarragan`）は書式の網を抜ける。名前でしか捕まらないので 2 枚目を張る。
        let authors = try Self.removedAuthors()
        #expect(authors.count >= 20, "著者の表が読めていない: \(authors)")

        let originals = try CheckedInFiles.list("Examples")
            .filter { $0.hasSuffix(".pde") || $0.hasSuffix(".json") }
        var offenders: [String] = []
        for path in originals {
            guard let text = CheckedInFiles.readText(path) else { continue }
            for author in authors where text.localizedCaseInsensitiveContains(author) {
                offenders.append("\(path) → \(author)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            外したはずの原典の著者名が、同梱している原典に残っている: \(offenders)
            その著者のサンプルはライセンスが付与されていないので同梱できない（Issue #1191）。
            """)
    }

    @Test("同梱している `.json` に `author` が残っていない")
    func bundledMetadataDeclaresNoAuthor() throws {
        let metadata = try CheckedInFiles.list("Examples").filter { $0.hasSuffix(".json") }
        let offenders = metadata.filter { path in
            guard let text = CheckedInFiles.readText(path) else { return false }
            return text.range(of: #""author"\s*:\s*"[^"]"#, options: .regularExpression) != nil
        }

        #expect(
            offenders.isEmpty,
            """
            `author` を持つ Processing 原典のメタデータが残っている: \(offenders)
            同梱しているメタデータは metaphor が移植版から書き起こしたもので、原典の
            クレジットを引き継がない（Issue #1191）。索引の生成器が読むのは
            `title` / `name` / `description` / `level` / `featured` / `status` だけで、
            `author` はどこからも読まれない。
            """)
    }

    @Test("同梱している原典の本数が THIRD_PARTY_LICENSES.md の記載と一致する")
    func bundledOriginalCountsMatchTheRecord() throws {
        // 上の 2 枚の網でも、まったく新しい著者の**裸の名前**は構文的には検出できない。
        // 本数を固定しておくと、原典が 1 本増えた時点で赤くなり、人間の判断を必ず経る。
        for suffix in [".pde", ".json"] {
            let actual = try CheckedInFiles.list("Examples").filter { $0.hasSuffix(suffix) }.count
            let recorded = try Self.recordedCounts(forRow: suffix)
            #expect(
                (actual, 0) == (recorded.total, recorded.credited),
                """
                `\(suffix)` の実測 \(actual) 本が THIRD_PARTY_LICENSES.md の記載
                \(recorded.total) 本（クレジットあり \(recorded.credited) 本）と合わない。
                サンプルを足したか消したなら記載を更新する。**原典を足した場合は、それが
                クレジット行を持たない public domain のものか確かめてから**（Issue #1191）。
                """)
        }
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

    @Test("説明文がクレジット行のあるサンプルを public domain と言っていない")
    func theProseDoesNotOverclaimPublicDomain() throws {
        // upstream が public domain と言うのは「クレジット行の無いもの」だけ。特定の著者を
        // 名指しで public domain 側に置く記述は、そこと食い違う（`Examples/NOTICE.md` は
        // かつて「Daniel Shiffman's examples are also in the public domain」と書き、
        // `README.en.md` は「sample sketches (public domain) by ... Daniel Shiffman」と
        // 書いていた。後者は著者名が後ろに来るので、前後どちらの語順も見る）。
        let authors = try Self.removedAuthors()
        for document in ["Examples/NOTICE.md", "README.md", "README.en.md"] {
            let prose = try #require(CheckedInFiles.readText(document), "\(document) が読めない")
            for author in authors {
                for pattern in ["\(author)[^.]*public domain", "public domain[^.]*\(author)"] {
                    #expect(
                        prose.range(of: pattern, options: [.regularExpression, .caseInsensitive])
                            == nil,
                        """
                        \(document) が \(author) のサンプルを public domain と書いている。
                        processing-examples の README が public domain と言うのはクレジット行の
                        無いものだけで、\(author) のサンプルはライセンス未付与として
                        Examples から外してある（Issue #1191）。
                        """)
                }
            }
        }
    }
}
