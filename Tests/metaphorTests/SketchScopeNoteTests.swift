import Foundation
import Testing

/// ADR-0005 の「2D/3D の作用先を Sketch 層 doc に明記する」規約を機械的に守る（Issue #677）。
///
/// この規約は長らく散文だけで担保されていたため、#379（33 本）と #677（27 本）の
/// 2 回に分けて後追いで埋める羽目になった。埋め終えた面をテストで凍結して、
/// **新しい 3D API を足す人が ADR を読んでいなくても規約から外れない**ようにする。
///
/// 検査するのは `Sketch+3D.swift` だけ。ここは 2026-08-18 Amendment の時点で
/// public メンバ全数が注記を持つ唯一のファイルで、床として意味がある。
/// `Sketch+Style.swift` / `Sketch+Shapes.swift` の 2D 系はまだ部分的なので対象外
/// （広げるならそのファイルを埋めてから）。
///
/// `SketchContext+*.swift` は 2026-08-18 Amendment §1 が「注記を置かない」と決めた層なので、
/// 何も要求しない（正本は Sketch 層のみ）。
@Suite("Sketch layer 2D/3D scope notes")
struct SketchScopeNoteTests {

    /// ADR-0005 の作用先区分に対応する doc 上の目印。
    ///
    /// 強調記号ごと突き合わせるのは、「3D のみ」が散文の中でたまたま出てくるのを
    /// 注記と誤認しないため。
    private static let scopeMarkers = [
        "**3D のみ**",  // 3D にだけ作用する（大多数）
        "**2D と 3D の両方**",  // pushMatrix / popMatrix
        "**記録中のシェイプ**",  // 3 引数以上の vertex / endShape3D（Amendment 2026-08-18 §2）
    ]

    /// 上の目印を使わないが同義の注記を持つ例外。増やすなら理由を必ず書くこと。
    ///
    /// - `toneMapping(_:)`: 「掛かるのは **3D のライティング結果だけ**です。2D の描画の色は
    ///   変わりません」と、3D の中でもさらに狭い作用先まで書いている。一般区分の文言へ
    ///   丸めると情報が減るので、そのまま残す。
    private static let documentedExceptions = ["func toneMapping("]

    @Test("Sketch+3D.swift の public メンバは全て 2D/3D の作用先注記を持つ")
    func everyPublicMemberDeclaresItsCanvas() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/metaphorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // リポジトリルート
            .appendingPathComponent("Sources/MetaphorCore/Sketch/Sketch+3D.swift")
        try #require(FileManager.default.fileExists(atPath: source.path))

        let lines = try String(contentsOf: source, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var checked = 0
        var offenders: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard Self.isPublicDeclaration(trimmed) else { continue }
            checked += 1

            if Self.documentedExceptions.contains(where: { trimmed.contains($0) }) { continue }

            // 宣言の直前から連続する `///` 行を集める（間に挟まる属性行は読み飛ばす）。
            var doc = ""
            var cursor = index - 1
            while cursor >= 0 {
                let above = lines[cursor].trimmingCharacters(in: .whitespaces)
                if above.hasPrefix("///") {
                    doc = above + "\n" + doc
                } else if above.hasPrefix("@") {
                    // @available などの属性は doc とみなさず、そのまま遡る
                } else {
                    break
                }
                cursor -= 1
            }

            if !Self.scopeMarkers.contains(where: { doc.contains($0) }) {
                offenders.append("Sketch+3D.swift:\(index + 1)  \(trimmed)")
            }
        }

        // スキャナが宣言を拾えなくなった（= 常に緑になる）状態を検出する保険。
        #expect(checked >= 60, "public 宣言を \(checked) 件しか拾えていません。スキャナが壊れています")

        #expect(
            offenders.isEmpty,
            """
            2D/3D の作用先注記が無い public メンバがあります（ADR-0005 / #677）。
            次のどれかを doc に書いてください:
              - Note: **3D のみ**に作用します（ADR-0005）。
              - Note: **2D と 3D の両方**に作用します。
              - Note: 作用先は**記録中のシェイプ**が決めます。…
            該当:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// `public func` / `public var` などの宣言行か（`public` を含むコメント行は除く）。
    private static func isPublicDeclaration(_ trimmed: String) -> Bool {
        guard !trimmed.hasPrefix("//") else { return false }
        for keyword in ["func ", "var ", "let ", "subscript", "init"] where
            trimmed.hasPrefix("public " + keyword)
        {
            return true
        }
        return false
    }
}
