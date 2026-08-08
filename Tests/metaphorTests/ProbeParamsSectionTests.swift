import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

/// `@Param` を宣言したスケッチ（`frame.json` の `params` 節の被写体）。
@MainActor
private final class ParamProbeSketch: Sketch {
    @Param(min: 10, max: 200) var radius: Float = 50
    @Param var showGrid: Bool = true
    @Param var tint: Color = Color(r: 1, g: 0.5, b: 0.25, a: 1)
}

/// 宣言ゼロのスケッチ（キーが省略されることの確認用）。
@MainActor
private final class BareProbeSketch: Sketch {}

/// `frame.json` の `params` 節（Issue #424 / 契約点 4 の additive 追加）。
///
/// 「画像 + それを生んだパラメータ」が 1 回の書き出しで揃うことが要点なので、
/// スナップショット経路・連続キャプチャ経路の**実際に書かれたファイル**を読んで検証します。
@Suite("Probe frame.json params section", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ProbeParamsSectionTests {

    /// Probe プラグイン付きのレンダラーと、`@Param` を発見済みのスケッチを結線する。
    private func makeHarness(
        sketch: any Sketch,
        outputDir: URL,
        requestPath: URL,
        width: Int = 64,
        height: Int = 48
    ) throws -> (MetaphorRenderer, MetaphorProbePlugin, SketchContext) {
        let plugin = MetaphorProbePlugin(
            config: MetaphorProbeConfig(
                outputDirectory: outputDir.path,
                requestFilePath: requestPath.path
            )
        )
        let renderer = try MetaphorRenderer(width: width, height: height)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        sketch._context = context
        context.params.discover(in: sketch)
        renderer.addPlugin(plugin)
        plugin.onAttach(sketch: sketch)
        return (renderer, plugin, context)
    }

    private func writeRequest(id: String, frames: Int? = nil, to path: URL) throws {
        var dict: [String: Any] = ["id": id]
        if let frames { dict["frames"] = frames }
        try JSONSerialization.data(withJSONObject: dict).write(to: path)
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func readJSON(_ url: URL) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    }

    @Test("宣言した @Param の値と revision が frame.json に載る")
    func paramsAppearInFrameJSON() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let sketch = ParamProbeSketch()
            let (renderer, _, context) = try makeHarness(
                sketch: sketch, outputDir: outputDir, requestPath: requestPath
            )

            try writeRequest(id: "params-1", to: requestPath)
            renderer.renderFrame()

            let jsonURL = outputDir.appendingPathComponent("frame.json")
            #expect(waitForFile(jsonURL))
            let json = try readJSON(jsonURL)

            let params = json?["params"] as? [String: Any]
            #expect(params?["revision"] as? Int == context.params.revision)

            let values = params?["values"] as? [String: Any]
            #expect(values?["radius"] as? Double == 50)
            #expect(values?["showGrid"] as? Bool == true)
            // color は 4 要素の裸配列（型の正典は params.json 側）。
            #expect((values?["tint"] as? [Double])?.count == 4)
            #expect(values?.count == 3)
        }
    }

    @Test("外部が書き換えた値は同じフレームの画像と揃って出る（revision も進む）")
    func paramsReflectExternalWrite() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let sketch = ParamProbeSketch()
            let (renderer, _, context) = try makeHarness(
                sketch: sketch, outputDir: outputDir, requestPath: requestPath
            )

            // AI 側の経路と同じくストアへ書く（set-request の適用結果と同じ状態）。
            context.params.setValue(.float(120), for: "radius")
            let revisionAfterWrite = context.params.revision

            try writeRequest(id: "params-2", to: requestPath)
            renderer.renderFrame()

            let jsonURL = outputDir.appendingPathComponent("frame.json")
            #expect(waitForFile(jsonURL))
            let params = try readJSON(jsonURL)?["params"] as? [String: Any]
            let values = params?["values"] as? [String: Any]
            #expect(values?["radius"] as? Double == 120)
            #expect(params?["revision"] as? Int == revisionAfterWrite)
            #expect(sketch.radius == 120)
        }
    }

    @Test("@Param が無いスケッチでは params キーごと省略される")
    func paramsOmittedWithoutDeclarations() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let sketch = BareProbeSketch()
            let (renderer, _, _) = try makeHarness(
                sketch: sketch, outputDir: outputDir, requestPath: requestPath
            )

            try writeRequest(id: "params-3", to: requestPath)
            renderer.renderFrame()

            let jsonURL = outputDir.appendingPathComponent("frame.json")
            #expect(waitForFile(jsonURL))
            let json = try readJSON(jsonURL)
            #expect(json?["params"] == nil)
            #expect(json?["schemaVersion"] as? Int == 4)   // additive なので版は据え置き
        }
    }

    @Test("連続キャプチャの各フレームにも params が載る（performance とは扱いが違う）")
    func paramsAppearInSequenceFrames() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let sketch = ParamProbeSketch()
            let (renderer, _, _) = try makeHarness(
                sketch: sketch, outputDir: outputDir, requestPath: requestPath
            )

            try writeRequest(id: "params-seq", frames: 3, to: requestPath)
            for _ in 0..<3 { renderer.renderFrame() }

            let seqDir = outputDir.appendingPathComponent("sequence")
            #expect(waitForFile(seqDir.appendingPathComponent("sequence.json"), timeout: 5))

            let first = try readJSON(seqDir.appendingPathComponent("frame.0000.json"))
            let params = first?["params"] as? [String: Any]
            #expect((params?["values"] as? [String: Any])?["radius"] as? Double == 50)
            // performance は単一フレーム経路のみ（#271）。params は per-frame で載る。
            #expect(first?["performance"] == nil)
        }
    }
}
