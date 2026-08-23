import Foundation
import Testing
@testable import MetaphorCore

/// ヘッドレス実行中であることを示すメニューバー項目の**表示内容**を検証します。
///
/// `NSStatusItem` の生成そのものはウィンドウサーバのセッションに依存するため
/// 自動テストせず（実機確認で担保）、ここでは文字列を組み立てる純関数だけを固定します。
@Suite("Headless status item text")
struct HeadlessStatusItemTests {

    /// 検証しやすい既定値のスナップショット。
    private func snapshot(
        title: String = "Test Sketch",
        location: String = "/Users/example/sketches/test",
        measuredFPS: Double? = 59.84,
        frameCount: Int = 12345,
        elapsed: Double = 201,
        outputs: [String] = []
    ) -> HeadlessStatusSnapshot {
        HeadlessStatusSnapshot(
            title: title,
            location: location,
            version: "0.13.0",
            pid: 4242,
            width: 1920,
            height: 1080,
            targetFPS: 60,
            measuredFPS: measuredFPS,
            frameCount: frameCount,
            elapsed: elapsed,
            outputs: outputs
        )
    }

    @Test("menu lines carry identity, resolution, progress and outputs")
    func menuLines() {
        let lines = HeadlessStatusSnapshot.menuLines(snapshot(outputs: ["live viewer (connected)"]))
        #expect(
            lines == [
                "metaphor 0.13.0 · headless · PID 4242",
                "1920×1080 @ 60 fps (measured 59.8)",
                "frame 12345 · 03:21 elapsed",
                "Output: live viewer (connected)",
            ])
    }

    @Test("measured fps is -- when it cannot be computed")
    func measuredUnavailable() {
        // noLoop() で止まっている作品に「0 fps」と出すと誤情報になる（PerformanceHUD と同じ規則）。
        #expect(HeadlessStatusSnapshot.measuredText(nil) == "--")
        #expect(HeadlessStatusSnapshot.measuredText(59.84) == "59.8")
        #expect(
            HeadlessStatusSnapshot.menuLines(snapshot(measuredFPS: nil))[1]
                == "1920×1080 @ 60 fps (measured --)")
    }

    @Test("elapsed time is mm:ss, and h:mm:ss past an hour")
    func elapsedFormatting() {
        #expect(HeadlessStatusSnapshot.elapsedText(0) == "00:00")
        #expect(HeadlessStatusSnapshot.elapsedText(9.9) == "00:09")
        #expect(HeadlessStatusSnapshot.elapsedText(201) == "03:21")
        #expect(HeadlessStatusSnapshot.elapsedText(3599) == "59:59")
        #expect(HeadlessStatusSnapshot.elapsedText(3723) == "1:02:03")
        // 起点より前（時計の巻き戻し）でも負の表示にしない。
        #expect(HeadlessStatusSnapshot.elapsedText(-5) == "00:00")
    }

    @Test("no output says so in words")
    func noOutput() {
        // 孤児になったヘッドレスプロセスを、メニューを開くだけで見分けられるようにする。
        #expect(
            HeadlessStatusSnapshot.outputsText([])
                == "Output: none — nobody is watching these frames")
    }

    @Test("multiple outputs are listed in order")
    func multipleOutputs() {
        #expect(
            HeadlessStatusSnapshot.outputsText(["live viewer (connected)", "Probe"])
                == "Output: live viewer (connected), Probe")
    }

    @Test("live viewer label shows the connection state")
    func viewerLabel() {
        #expect(
            HeadlessStatusSnapshot.outputLabel(
                pluginID: ViewerOutputPlugin.id, viewerConnected: true
            ) == "live viewer (connected)")
        // 親が落ちた後も子は回り続ける。切れたことが読めるのがこの表示の要点。
        #expect(
            HeadlessStatusSnapshot.outputLabel(
                pluginID: ViewerOutputPlugin.id, viewerConnected: false
            ) == "live viewer (disconnected)")
        #expect(
            HeadlessStatusSnapshot.outputLabel(
                pluginID: ViewerOutputPlugin.id, viewerConnected: nil
            ) == "live viewer (disconnected)")
    }

    @Test("external output ids are shortened for reading")
    func externalOutputLabel() {
        #expect(
            HeadlessStatusSnapshot.outputLabel(
                pluginID: "org.metaphor.syphon-output", viewerConnected: nil
            ) == "syphon")
        #expect(
            HeadlessStatusSnapshot.outputLabel(
                pluginID: "com.example.recorder", viewerConnected: nil
            ) == "com.example.recorder")
    }

    @Test("location folds the home directory, and says so when there is no project")
    func locationFormatting() {
        #expect(
            HeadlessStatusSnapshot.locationText("/Users/example/sketches/test")
                == "/Users/example/sketches/test")
        #expect(
            HeadlessStatusSnapshot.locationText("\(NSHomeDirectory())/sketches/test")
                == "~/sketches/test")
        // `.app` を LaunchServices から起動すると cwd が `/` になる（CONTRACT.md）。
        // そこで動いていると読めてしまうので、素の `/` とは書かない。
        #expect(HeadlessStatusSnapshot.locationText("/") == "/ (no project directory)")
    }

    @Test("a long location is shortened from the front, keeping the telling end")
    func locationTruncation() {
        // この 1 行がメニュー幅の下限を決めてしまうので畳む。区別が付くのは末尾側。
        #expect(
            HeadlessStatusSnapshot.locationText(
                "/Users/example/very/deeply/nested/place/for/sketches/test", maxLength: 24
            ) == "…/for/sketches/test")
        // 上限ちょうどは畳まない。
        #expect(
            HeadlessStatusSnapshot.locationText("/Users/example/test", maxLength: 19)
                == "/Users/example/test")
        // 末尾 1 つでも収まらないときは、それでも末尾を出す（何も出ないよりよい）。
        #expect(
            HeadlessStatusSnapshot.locationText("/Users/example/very-long-name", maxLength: 8)
                == "…/very-long-name")
    }

    @Test("the saved path is written relative to where the process lives")
    func savedTextFormatting() {
        // 場所はすぐ上の行に出ている。絶対パスを繰り返すとメニュー幅の下限になる。
        #expect(
            HeadlessStatusSnapshot.savedText(
                path: "/Users/example/sketches/test/output/metaphor_1.png",
                base: "/Users/example/sketches/test"
            ) == "Saved to output/metaphor_1.png")
        // 外へ逃がしたときは、どこへ行ったかが分からないと困るので全体を出す。
        #expect(
            HeadlessStatusSnapshot.savedText(
                path: "\(NSHomeDirectory())/Desktop/metaphor_1.png", base: "/"
            ) == "Saved to ~/Desktop/metaphor_1.png")
    }

    @Test("the item hides only while the live viewer is watching")
    func visibilityRule() {
        // 親のウィンドウが無い実行（mcp / Syphon / 素のヘッドレス）は常に出す。
        #expect(
            HeadlessStatusItem.shouldShow(viewerSocketConfigured: false, viewerConnected: false))
        #expect(
            HeadlessStatusItem.shouldShow(viewerSocketConfigured: false, viewerConnected: true))
        // watch 中は親のウィンドウが同じものを出しているので引っ込む。
        #expect(
            !HeadlessStatusItem.shouldShow(viewerSocketConfigured: true, viewerConnected: true))
        // 親が落ちたら（＝孤児になったら）出る。ここがこの面の存在意義。
        #expect(
            HeadlessStatusItem.shouldShow(viewerSocketConfigured: true, viewerConnected: false))
    }

    @Test("saving falls back to the Desktop when the project directory is not writable")
    func saveDestinationFallback() {
        #expect(
            HeadlessStatusItem.saveDestination(
                base: "/Users/example/sketches/test",
                timestamp: "20260823_120000",
                isWritable: { _ in true }
            ) == "/Users/example/sketches/test/output/metaphor_20260823_120000.png")

        // `.app` 起動で基準が `/` になる経路。黙って保存されないのがいちばん悪い。
        let desktop = NSString(string: "~/Desktop").expandingTildeInPath
        #expect(
            HeadlessStatusItem.saveDestination(
                base: "/", timestamp: "20260823_120000", isWritable: { _ in false }
            ) == "\(desktop)/metaphor_20260823_120000.png")
    }
}
