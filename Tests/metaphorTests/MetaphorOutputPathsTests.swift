import Foundation
import Testing

@testable import MetaphorCore

/// 書き出し先の解決（Issue #757）。
///
/// `saveFrame(_:)` は渡された名前に無条件で `~/Desktop/` を前置していたため、
/// 保存先を選べず、絶対パスを渡すと `~/Desktop/tmp/…` という別の場所に落ちていた
/// （親ディレクトリが作られるので失敗すらしない）。既定はプロジェクトの中
/// （`<base>/output/`）へ移し、明示した相対パスはプロジェクト直下相対、
/// 絶対パスと `~` はそのまま使う。
@Suite("書き出し先の解決")
struct MetaphorOutputPathsTests {

    private let base = "/Users/someone/sketches/strata"
    private let timestamp = "20260816_120000"

    // MARK: - 既定の置き場

    @Test("既定の出力ディレクトリは基準の直下 output/")
    func defaultDirectoryIsInsideProject() {
        #expect(MetaphorOutputPaths.defaultDirectory(base: base) == "\(base)/output")
    }

    @Test("既定のスクリーンショットは output/ にフレーム番号付きで置かれる")
    func defaultScreenshotGoesToOutput() {
        #expect(
            MetaphorOutputPaths.screenshot(filename: nil, frameCount: 1, base: base)
                == "\(base)/output/screen-0001.png")
    }

    @Test("既定のタイムスタンプ付きスクリーンショットも output/ に置かれる")
    func timestampedScreenshotGoesToOutput() {
        #expect(
            MetaphorOutputPaths.timestampedScreenshot(timestamp: timestamp, base: base)
                == "\(base)/output/metaphor_20260816_120000.png")
    }

    @Test("既定の連番ディレクトリ・動画・GIF も output/ に置かれる")
    func defaultRecordingsGoToOutput() {
        #expect(
            MetaphorOutputPaths.frameSequenceDirectory(nil, timestamp: timestamp, base: base)
                == "\(base)/output/metaphor_frames_20260816_120000")
        #expect(
            MetaphorOutputPaths.recording(
                nil, fileExtension: "mp4", timestamp: timestamp, base: base)
                == "\(base)/output/metaphor_20260816_120000.mp4")
        #expect(
            MetaphorOutputPaths.recording(
                nil, fileExtension: "gif", timestamp: timestamp, base: base)
                == "\(base)/output/metaphor_20260816_120000.gif")
    }

    // MARK: - 明示した指定

    @Test("相対パスはプロジェクト直下からの相対として解決される")
    func relativePathsResolveAgainstProject() {
        #expect(
            MetaphorOutputPaths.screenshot(filename: "shots/a.png", frameCount: 1, base: base)
                == "\(base)/shots/a.png")
        #expect(
            MetaphorOutputPaths.frameSequenceDirectory("shots", timestamp: timestamp, base: base)
                == "\(base)/shots")
        #expect(
            MetaphorOutputPaths.recording(
                "shots/clip.mp4", fileExtension: "mp4", timestamp: timestamp, base: base)
                == "\(base)/shots/clip.mp4")
    }

    @Test("絶対パスはそのまま使われる（Issue #757 の再現ケース）")
    func absolutePathsAreUntouched() {
        #expect(
            MetaphorOutputPaths.screenshot(
                filename: "/tmp/shots/chain.png", frameCount: 1, base: base)
                == "/tmp/shots/chain.png")
        #expect(
            MetaphorOutputPaths.recording(
                "/tmp/clip.mp4", fileExtension: "mp4", timestamp: timestamp, base: base)
                == "/tmp/clip.mp4")
    }

    @Test("~ 始まりは展開して使う")
    func tildeIsExpanded() {
        let path = MetaphorOutputPaths.screenshot(
            filename: "~/Pictures/a.png", frameCount: 1, base: base)
        #expect(path.hasPrefix("/"))
        #expect(!path.contains("~"))
        #expect(path.hasSuffix("/Pictures/a.png"))
    }

    // MARK: - 回帰

    @Test("指定していない限り Desktop へは書かない")
    func neverFallsBackToDesktop() {
        let paths = [
            MetaphorOutputPaths.screenshot(filename: nil, frameCount: 1, base: base),
            MetaphorOutputPaths.screenshot(filename: "shots/a.png", frameCount: 1, base: base),
            MetaphorOutputPaths.screenshot(
                filename: "/tmp/shots/chain.png", frameCount: 1, base: base),
            MetaphorOutputPaths.timestampedScreenshot(timestamp: timestamp, base: base),
            MetaphorOutputPaths.frameSequenceDirectory(nil, timestamp: timestamp, base: base),
            MetaphorOutputPaths.recording(
                nil, fileExtension: "mp4", timestamp: timestamp, base: base),
        ]
        for path in paths {
            #expect(!path.contains("/Desktop/"), "Desktop へ落ちている: \(path)")
        }
    }

    @Test("フレーム番号は 4 桁ゼロ詰め（Processing 互換）")
    func frameNumberIsZeroPadded() {
        #expect(
            MetaphorOutputPaths.screenshot(filename: nil, frameCount: 42, base: base)
                == "\(base)/output/screen-0042.png")
        #expect(
            MetaphorOutputPaths.screenshot(filename: nil, frameCount: 12345, base: base)
                == "\(base)/output/screen-12345.png")
    }
}
