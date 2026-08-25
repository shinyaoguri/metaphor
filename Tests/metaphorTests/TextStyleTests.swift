import CoreText
import Foundation
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

// MARK: - フォント解決

/// `textStyle()` がフォント名をどう解決するかを固定する（Issue #816）。
///
/// ## なぜこのテストがあるか
///
/// スタイル解決は**外したときに黙って別のフォントで描かれる**種類の機能で、
/// コンパイルエラーにも実行時エラーにもならない。素朴な実装（ファミリー名に
/// `" Bold"` を継ぎ足して `CTFontCreateWithName` へ渡す）は、スタイル名を持たない
/// フォントで `Papyrus Bold` → `Helvetica` のように**要求したファミリーごと**
/// 失われるのに、成功したように見える。
///
/// そのため「効いたこと」だけでなく **「効かなかったと分かること」** を assert する。
///
/// ## フォントの選び方
///
/// システムフォントは環境依存なので、CI で確実にあるものだけを使う:
///
/// - `Helvetica` / `Menlo` — bold / italic / boldItalic の 3 面が揃っている
///   （既存の `TextWidthMetricsTests` も同じ 2 つを使っている）
/// - `Tests/metaphorTests/Fixtures/SpaceMono-Regular.ttf` — **1 面しか持たない**
///   ので、失敗系はシステムフォントの品揃えに頼らず決定論的に作れる
@Suite("Text style resolution", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextStyleResolutionTests {

    private static let styleMask: CTFontSymbolicTraits = [.traitBold, .traitItalic]

    /// 名前からフォントを引き直して、太字・斜体のトレイトを読む。
    ///
    /// 下流（`GlyphAtlas` / advance キャッシュ / アウトライン）は名前しか受け取らず、
    /// そこから `CTFontCreateWithName` で引き直す。つまりこの引き直しこそが本番の経路。
    private func traits(of name: String) -> CTFontSymbolicTraits {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        return CTFontGetSymbolicTraits(font).intersection(Self.styleMask)
    }

    // MARK: - 正常系

    @Test(
        "解決した名前は要求どおりのトレイトで引き直せる",
        arguments: [
            ("Helvetica", TextStyle.bold, CTFontSymbolicTraits.traitBold),
            ("Helvetica", .italic, .traitItalic),
            ("Helvetica", .boldItalic, [.traitBold, .traitItalic]),
            ("Menlo", .bold, .traitBold),
            ("Menlo", .italic, .traitItalic),
            ("Menlo", .boldItalic, [.traitBold, .traitItalic]),
        ] as [(String, TextStyle, CTFontSymbolicTraits)])
    func resolvesRequestedTraits(
        family: String, style: TextStyle, wanted: CTFontSymbolicTraits
    ) {
        let resolved = TextFontResolver.resolve(family: family, style: style)

        #expect(resolved.styleApplied, "\(family) の \(style) が当たらなかった")
        #expect(
            resolved.name != family,
            "\(family) の \(style) で名前が変わっていない（\(resolved.name)）")
        #expect(
            traits(of: resolved.name) == wanted,
            "\(resolved.name) を引き直すと \(traits(of: resolved.name))（要求は \(wanted)）")
    }

    // MARK: - `.normal` は素通し（後方互換の要）

    @Test("normal はファミリー名をそのまま返す")
    func normalPassesFamilyThrough() {
        let resolved = TextFontResolver.resolve(family: "Helvetica", style: .normal)

        #expect(resolved.name == "Helvetica")
        #expect(resolved.styleApplied)
    }

    /// `.normal` が「トレイトを剥がす」実装だと、`textStyle` が既定の `.normal` である以上、
    /// **いままで太字が出ていた既存スケッチがこの変更で細字になる**。実測では
    /// `HelveticaNeue-Bold` にトレイト合成で NORMAL を要求すると `HelveticaNeue` へ落ちる。
    @Test("normal はスタイル込みの名前から太字を剥がさない")
    func normalDoesNotStripStyleFromQualifiedName() {
        let qualified = "Helvetica-Bold"
        let resolved = TextFontResolver.resolve(family: qualified, style: .normal)

        #expect(resolved.name == qualified, "スタイル込みの名前が書き換えられた")
        #expect(
            traits(of: resolved.name).contains(.traitBold),
            "\(qualified) が太字でなくなった — 既存スケッチが細字に化ける")
    }

    // MARK: - 失敗系

    /// 1 面しか持たないフォントで、要求したスタイルが**得られなかったと分かる**こと。
    ///
    /// システムフォントの品揃えに依存しないよう、リポジトリ同梱の
    /// `SpaceMono-Regular.ttf`（Regular のみ）をプロセスへ登録して使う。
    @Test(
        "字面の無いスタイルは styleApplied == false で返り、名前は変わらない",
        arguments: [TextStyle.bold, .italic, .boldItalic])
    func missingStyleIsReported(style: TextStyle) throws {
        let name = try Self.registerSingleFaceFixture()

        let resolved = TextFontResolver.resolve(family: name, style: style)

        #expect(!resolved.styleApplied, "\(style) が当たったことになっている（\(resolved.name)）")
        #expect(
            resolved.name == name,
            "当たらなかったのに名前が \(resolved.name) へ差し替わった — 黙って別フォントで描かれる")
    }

    /// 存在しないフォント名を渡しても、`textStyle()` は落ちない。
    ///
    /// Core Text は解決できない名前を `Helvetica` へ落とすため、この経路で
    /// 「ファミリーが無い」ことは検出できない（`textFont()` の既知の挙動で、doc に書いてある）。
    /// ここで固定したいのは**クラッシュしないこと**と、名前が握り潰されないこと。
    @Test("存在しないフォント名でもクラッシュしない")
    func unknownFamilyDoesNotCrash() {
        let resolved = TextFontResolver.resolve(family: "NoSuchFontAtAll816", style: .bold)

        #expect(!resolved.name.isEmpty)
    }

    // MARK: - フィクスチャ

    /// Regular しか持たないテスト用フォントを登録し、その PostScript 名を返す。
    ///
    /// `FontLoadingTests` と同じフィクスチャ・同じ「ソースツリーを直接見る」流儀。
    /// 二重登録は既に登録済みとして失敗しうるので、引けたかどうかで判定する。
    static func registerSingleFaceFixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SpaceMono-Regular.ttf")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        let name = "SpaceMono-Regular"
        let resolved = CTFontCreateWithName(name as CFString, 12, nil)
        try #require(
            CTFontCopyPostScriptName(resolved) as String == name,
            "テスト用フォントを登録できていない")
        return name
    }
}

// MARK: - キャンバスの状態としての textStyle

/// `textStyle()` が Canvas2D の状態としてどう振る舞うかを固定する（Issue #816）。
@Suite("Text style state", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextStyleStateTests {

    private func canvas() throws -> Canvas2D {
        let canvas = try MetalTestHelper.canvas2D(width: 64, height: 64)
        canvas.textFont("Helvetica")
        canvas.textSize(32)
        return canvas
    }

    @Test("textStyle(.bold) は解決済みフォント名を太字面へ差し替える")
    func boldSwitchesResolvedName() throws {
        let canvas = try canvas()
        #expect(canvas.resolvedFontName == "Helvetica")

        canvas.textStyle(.bold)

        #expect(canvas.resolvedFontName == "Helvetica-Bold")
        #expect(canvas.currentFontFamily == "Helvetica", "要求したファミリーまで書き換えている")
    }

    /// 描画と計測が同じ物差しを使う（#802）以上、スタイルは**測る側にも**届いていないといけない。
    /// 届いていなければ、太字で描いた行が `textAlign` でずれる。
    @Test("textWidth() は太字面の advance で測る")
    func textWidthFollowsStyle() throws {
        let canvas = try canvas()
        let sample = "Hamburgefonstiv"
        let regular = canvas.textWidth(sample)

        canvas.textStyle(.bold)
        let bold = canvas.textWidth(sample)

        #expect(regular > 0)
        #expect(
            bold != regular,
            "太字にしても幅が \(regular) のまま — 計測が解決前のフォントを見ている")
    }

    @Test("textStyle のあとに textFont を変えてもスタイルは残る")
    func styleSurvivesFontChange() throws {
        let canvas = try canvas()
        canvas.textStyle(.bold)

        canvas.textFont("Menlo")

        #expect(canvas.resolvedFontName == "Menlo-Bold")
        #expect(canvas.currentTextStyle == .bold)
    }

    @Test("textStyle(.normal) はスタイル込みの名前を素通しする")
    func normalKeepsQualifiedName() throws {
        let canvas = try canvas()
        canvas.textFont("Helvetica-Bold")

        canvas.textStyle(.normal)

        #expect(canvas.resolvedFontName == "Helvetica-Bold")
    }

    @Test("字面の無いスタイルは元のフォントのまま描く")
    func missingStyleKeepsFont() throws {
        let canvas = try canvas()
        let name = try TextStyleResolutionTests.registerSingleFaceFixture()
        canvas.textFont(name)

        canvas.textStyle(.italic)

        #expect(canvas.resolvedFontName == name, "黙って別のフォントへ差し替わっている")
    }

    // MARK: - push / pop

    @Test("push() / pop() は textStyle を保存・復元する")
    func pushPopRestoresStyle() throws {
        let canvas = try canvas()
        canvas.textStyle(.bold)

        canvas.push()
        canvas.textStyle(.italic)
        #expect(canvas.resolvedFontName == "Helvetica-Oblique")
        canvas.pop()

        #expect(canvas.currentTextStyle == .bold)
        #expect(canvas.resolvedFontName == "Helvetica-Bold", "pop() で解決済み名が戻っていない")
    }

    @Test("pushStyle() / popStyle() は textStyle を保存・復元する")
    func pushStylePopStyleRestoresStyle() throws {
        let canvas = try canvas()
        canvas.textStyle(.italic)

        canvas.pushStyle()
        canvas.textStyle(.normal)
        #expect(canvas.resolvedFontName == "Helvetica")
        canvas.popStyle()

        #expect(canvas.currentTextStyle == .italic)
        #expect(canvas.resolvedFontName == "Helvetica-Oblique")
    }
}
