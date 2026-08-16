import Foundation
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// `saveFrame(_:)` が指定した場所へ実際に書けること（Issue #757 の end-to-end）。
///
/// パスの決め方そのものは ``MetaphorOutputPathsTests`` が純関数として押さえている。
/// ここは「決めたパスがレンダラまで届き、そこにファイルができる」ところまでを通す。
/// 以前は `~/Desktop/` を前置していたため、絶対パスを渡すと `~/Desktop/tmp/…` に
/// 落ちていた（親ディレクトリごと作られるので失敗にも気付けなかった）。
@Suite("saveFrame の書き出し先")
@MainActor
struct SaveFrameDestinationTests {

    @Test("絶対パスを渡すとそこに書かれ、Desktop には何も残らない")
    func absolutePathIsHonored() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let target = dir.appendingPathComponent("shots/chain.png")
            // 旧実装が作っていた場所（`~/Desktop/` + 渡されたパス、そのままの連結）。
            let desktopLeak = NSHomeDirectory() + "/Desktop/" + target.path

            _ = try OffscreenSketchHarness.render(size: 64) { context in
                context.background(0, 0, 0)
                context.saveFrame(target.path)
            }

            #expect(waitForFile(at: target), "書き出されていない: \(target.path)")
            #expect(
                !FileManager.default.fileExists(atPath: desktopLeak),
                "Desktop 配下に落ちている: \(desktopLeak)")
        }
    }

    /// PNG の書き出しは GPU の完了ハンドラ内で走るため、少しだけ待つ。
    private func waitForFile(at url: URL, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }
}
