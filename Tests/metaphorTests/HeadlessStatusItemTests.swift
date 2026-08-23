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
        measuredFPS: Double? = 59.84,
        frameCount: Int = 12345,
        elapsed: Double = 201,
        outputs: [String] = []
    ) -> HeadlessStatusSnapshot {
        HeadlessStatusSnapshot(
            title: title,
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
        #expect(lines == [
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
        #expect(HeadlessStatusSnapshot.menuLines(snapshot(measuredFPS: nil))[1]
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
        #expect(HeadlessStatusSnapshot.outputsText([])
            == "Output: none — nobody is watching these frames")
    }

    @Test("multiple outputs are listed in order")
    func multipleOutputs() {
        #expect(HeadlessStatusSnapshot.outputsText(["live viewer (connected)", "Probe"])
            == "Output: live viewer (connected), Probe")
    }

    @Test("live viewer label shows the connection state")
    func viewerLabel() {
        #expect(HeadlessStatusSnapshot.outputLabel(
            pluginID: ViewerOutputPlugin.id, viewerConnected: true
        ) == "live viewer (connected)")
        // 親が落ちた後も子は回り続ける。切れたことが読めるのがこの表示の要点。
        #expect(HeadlessStatusSnapshot.outputLabel(
            pluginID: ViewerOutputPlugin.id, viewerConnected: false
        ) == "live viewer (disconnected)")
        #expect(HeadlessStatusSnapshot.outputLabel(
            pluginID: ViewerOutputPlugin.id, viewerConnected: nil
        ) == "live viewer (disconnected)")
    }

    @Test("external output ids are shortened for reading")
    func externalOutputLabel() {
        #expect(HeadlessStatusSnapshot.outputLabel(
            pluginID: "org.metaphor.syphon-output", viewerConnected: nil
        ) == "syphon")
        #expect(HeadlessStatusSnapshot.outputLabel(
            pluginID: "com.example.recorder", viewerConnected: nil
        ) == "com.example.recorder")
    }
}
