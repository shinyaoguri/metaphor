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

    /// 同一フレーム内の複数回呼び出し（Issue #762）。
    ///
    /// 保留中の保存先が単一スロットだった頃は、2 回目以降が前の値を無言で上書きし、
    /// 最後の 1 枚しか残らなかった。撮られるのは「呼んだ時点の途中経過」ではなく
    /// **そのフレームの最終出力**なので、複数パスの中身は同一になるのが正しい。
    @Test("同一フレーム内で複数回呼ぶと、すべてのパスに同じ絵が書かれる")
    func multipleCallsInOneFrameAllWritten() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let first = dir.appendingPathComponent("shots/first.png")
            let second = dir.appendingPathComponent("shots/second.png")
            let third = dir.appendingPathComponent("latest.png")

            _ = try OffscreenSketchHarness.render(size: 64) { context in
                context.background(20, 120, 200)
                context.saveFrame(first.path)
                context.saveFrame(second.path)
                context.save(third.path)
            }

            for target in [first, second, third] {
                #expect(waitForFile(at: target), "書き出されていない: \(target.path)")
            }

            // 同じフレームの最終出力なので、3 枚は同一バイト列になる
            // （「最後の 1 枚だけ書いて他は空／別フレーム」を弾く）。
            let contents = try [first, second, third].map { try Data(contentsOf: $0) }
            #expect(contents[0].count > 0, "空のファイルが書かれている")
            #expect(contents[0] == contents[1], "1 枚目と 2 枚目の中身が違う")
            #expect(contents[0] == contents[2], "1 枚目と 3 枚目の中身が違う")
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
