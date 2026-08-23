import Foundation
import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - loadFont (#649)

@Suite("FontLoading", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct FontLoadingTests {

    /// テスト用フォント（SIL Open Font License 1.1）の置き場。
    ///
    /// ゴールデン PNG（`GoldenImageTests.goldenDirectory`）と同じくソースツリーを
    /// 直接見る。バンドルリソースにすると `swift test` 以外の経路から辿りにくくなる。
    private static let fixtureFont = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/SpaceMono-Regular.ttf")
        .path

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    // MARK: - 読み込み

    @Test("loads a font file and resolves its names")
    func loadsFontFile() throws {
        let context = try makeContext()
        let font = try context.loadFont(Self.fixtureFont)
        #expect(font.postScriptName == "SpaceMono-Regular")
        #expect(font.familyName == "Space Mono")
        #expect(font.path == Self.fixtureFont)
    }

    @Test("registered font is resolvable by Core Text")
    func registeredFontIsResolvable() throws {
        let context = try makeContext()
        let font = try context.loadFont(Self.fixtureFont)
        // 登録できていれば PostScript 名でフォントが引ける。引けない場合、Core Text は
        // 名前をそのままファミリーとして扱いシステムフォントへフォールバックするため、
        // 「戻ってきたフォントの名前が要求した名前と一致するか」で判定する。
        let resolved = CTFontCreateWithName(font.postScriptName as CFString, 32, nil)
        #expect(CTFontCopyPostScriptName(resolved) as String == font.postScriptName)
    }

    @Test("loading the same file twice is idempotent")
    func idempotentLoad() throws {
        let context = try makeContext()
        let first = try context.loadFont(Self.fixtureFont)
        // 2 回目は Core Text が「登録済み」を返すが、これは正常系として成功させる
        let second = try context.loadFont(Self.fixtureFont, cache: false)
        #expect(first == second)
    }

    // MARK: - キャッシュ

    @Test("same path is cached")
    func cachesByPath() throws {
        let context = try makeContext()
        _ = try context.loadFont(Self.fixtureFont)
        _ = try context.loadFont(Self.fixtureFont)
        #expect(context.assetCache.fontCount == 1)
    }

    @Test("clearCaches empties the font cache")
    func clearCaches() throws {
        let context = try makeContext()
        _ = try context.loadFont(Self.fixtureFont)
        #expect(context.assetCache.fontCount == 1)
        context.assetCache.clear()
        #expect(context.assetCache.fontCount == 0)
    }

    // MARK: - 失敗系

    @Test("missing file throws fileNotFound")
    func missingFile() throws {
        let context = try makeContext()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-no-such-font-\(UUID().uuidString).ttf").path
        #expect(throws: MetaphorError.self) {
            _ = try context.loadFont(path)
        }
        do {
            _ = try context.loadFont(path)
            Issue.record("expected loadFont to throw")
        } catch MetaphorError.font(.fileNotFound(let thrownPath)) {
            #expect(thrownPath == path)
        }
    }

    @Test("non-font file throws noFontsInFile")
    func notAFont() throws {
        let context = try makeContext()
        try TempFileHelper.withTemporaryFile(extension: "ttf") { url in
            try Data("this is not a font".utf8).write(to: url)
            do {
                _ = try context.loadFont(url.path)
                Issue.record("expected loadFont to throw")
            } catch MetaphorError.font(.noFontsInFile) {
                // 期待どおり
            }
        }
    }

    // MARK: - 描画への反映

    @Test("textFont(MFont) actually switches the measured font")
    func textFontChangesMeasurement() throws {
        let context = try makeContext()
        let font = try context.loadFont(Self.fixtureFont)
        let sample = "metaphor"

        context.textSize(32)
        context.textFont("Helvetica")
        let helvetica = context.canvas.textWidth(sample)

        context.textFont(font)
        let spaceMono = context.canvas.textWidth(sample)

        // Space Mono は等幅、Helvetica はプロポーショナル。同じ文字列で幅が一致したら
        // フォントが切り替わっていない（= どちらもフォールバックで測っている）。
        #expect(helvetica > 0)
        #expect(spaceMono > 0)
        #expect(helvetica != spaceMono)
    }

    @Test("textFont(MFont) survives push/pop")
    func textFontSurvivesPushPop() throws {
        let context = try makeContext()
        let font = try context.loadFont(Self.fixtureFont)
        context.textFont(font)
        context.canvas.push()
        context.textFont("Helvetica")
        context.canvas.pop()
        #expect(context.canvas.currentFontFamily == font.postScriptName)
    }
}
