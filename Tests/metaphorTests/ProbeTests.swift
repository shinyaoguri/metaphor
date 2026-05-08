import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Request parsing

@Suite("MetaphorProbe request decoding")
struct ProbeRequestTests {

    @Test("decode minimal request")
    func decodeMinimal() throws {
        let json = #"{"id":"abc"}"#
        let request = try JSONDecoder().decode(
            ProbeRequest.self, from: Data(json.utf8)
        )
        #expect(request.id == "abc")
        #expect(request.label == nil)
        #expect(request.scale == nil)
    }

    @Test("decode full request")
    func decodeFull() throws {
        let json = #"{"id":"abc","label":"baseline","scale":0.5}"#
        let request = try JSONDecoder().decode(
            ProbeRequest.self, from: Data(json.utf8)
        )
        #expect(request.id == "abc")
        #expect(request.label == "baseline")
        #expect(request.scale == 0.5)
    }
}

// MARK: - Plugin behavior (GPU-gated)

@Suite("MetaphorProbe snapshot capture", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MetaphorProbePluginTests {

    /// `MetaphorRenderer` の `inflightSemaphore` が GPU completion 前に dispose される
    /// クラッシュを避けるため、各テスト末尾で in-flight ワークの完了を少し待ちます。
    private func drainGPUWork() {
        Thread.sleep(forTimeInterval: 0.2)
    }

    /// 完了ハンドラ駆動の書き出しが終わるまで `frame.png` の出現をポーリングします。
    private func waitForFrame(in directory: URL, timeout: TimeInterval = 3.0) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        let target = directory.appendingPathComponent("frame.png")
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: target.path) {
                return target
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    /// 指定 id・label のリクエストファイルを書き込みます。
    private func writeRequest(id: String, label: String? = nil, to path: URL) throws {
        var dict: [String: Any] = ["id": id]
        if let label { dict["label"] = label }
        let data = try JSONSerialization.data(withJSONObject: dict)
        try data.write(to: path)
    }

    @Test("idle plugin does not produce output")
    func idlePluginNoOp() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            renderer.renderFrame()
            renderer.renderFrame()

            // リクエストが無ければ frame.png は作られない
            #expect(!FileManager.default.fileExists(
                atPath: outputDir.appendingPathComponent("frame.png").path
            ))

            drainGPUWork()
        }
    }

    @Test("request file triggers frame.png snapshot")
    func requestProducesPNG() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            try writeRequest(id: "snap-1", label: "first", to: requestPath)
            renderer.renderFrame()

            let png = waitForFrame(in: outputDir)
            #expect(png != nil)

            if let png {
                let data = try Data(contentsOf: png)
                // PNG magic number 0x89 'P' 'N' 'G'
                #expect(data.count > 8)
                #expect(data[0] == 0x89)
                #expect(data[1] == 0x50)
                #expect(data[2] == 0x4E)
                #expect(data[3] == 0x47)
            }

            drainGPUWork()
        }
    }

    @Test("frame.json is written alongside frame.png")
    func metadataIsWritten() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 128, height: 96)
            renderer.addPlugin(plugin)

            // 実運用では Sketch.draw() の中で probe(...) が呼ばれる。
            // テストでは onDraw に同等の処理を仕込む（pre と post の間で実行される）。
            renderer.onDraw = { _, _ in
                MainActor.assumeIsolated {
                    plugin.recordValue(name: "test.count", value: .int(42))
                    plugin.recordValue(name: "test.label", value: .string("hello"))
                }
            }

            try writeRequest(id: "meta-1", label: "metadata-test", to: requestPath)
            renderer.renderFrame()

            _ = waitForFrame(in: outputDir)
            let jsonPath = outputDir.appendingPathComponent("frame.json")

            // frame.json が出るのを少し待つ
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline,
                  !FileManager.default.fileExists(atPath: jsonPath.path) {
                Thread.sleep(forTimeInterval: 0.05)
            }

            #expect(FileManager.default.fileExists(atPath: jsonPath.path))

            let data = try Data(contentsOf: jsonPath)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["id"] as? String == "meta-1")
            #expect(json?["label"] as? String == "metadata-test")
            #expect(json?["schemaVersion"] as? Int == 1)
            let size = json?["size"] as? [String: Int]
            #expect(size?["width"] == 128)
            #expect(size?["height"] == 96)
            let custom = json?["custom"] as? [String: Any]
            #expect(custom?["test.count"] as? Int == 42)
            #expect(custom?["test.label"] as? String == "hello")

            drainGPUWork()
        }
    }

    @Test("blank frame produces a warning")
    func blankFrameWarning() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            // 何も描画しない → クリアカラーで埋まる → blank として検出されるはず
            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            try writeRequest(id: "blank-1", to: requestPath)
            renderer.renderFrame()

            let jsonPath = outputDir.appendingPathComponent("frame.json")
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline,
                  !FileManager.default.fileExists(atPath: jsonPath.path) {
                Thread.sleep(forTimeInterval: 0.05)
            }

            #expect(FileManager.default.fileExists(atPath: jsonPath.path))
            let data = try Data(contentsOf: jsonPath)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let warnings = json?["warnings"] as? [String] ?? []
            #expect(warnings.contains(where: { $0.hasPrefix("frame appears nearly blank") }))

            drainGPUWork()
        }
    }

    @Test("probe values reset each frame")
    func probeValuesResetPerFrame() throws {
        let plugin = MetaphorProbePlugin()
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        renderer.addPlugin(plugin)

        plugin.recordValue(name: "stale", value: .int(99))
        renderer.renderFrame()
        // pre() がリセットしたあとは値が消えている
        #expect(plugin.stateBuffer.snapshot().isEmpty)

        drainGPUWork()
    }

    @Test("same request id is processed only once")
    func duplicateRequestIgnored() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            try writeRequest(id: "same-id", to: requestPath)
            renderer.renderFrame()
            _ = waitForFrame(in: outputDir)

            let firstPath = outputDir.appendingPathComponent("frame.png")
            let firstAttrs = try FileManager.default.attributesOfItem(atPath: firstPath.path)
            let firstMtime = firstAttrs[.modificationDate] as? Date

            // 同じ id のリクエストファイルを再書き込み（mtime だけ更新）
            // → id 重複検出により 2 度目はスキップされ、frame.png は更新されない
            try writeRequest(id: "same-id", to: requestPath)
            renderer.renderFrame()
            renderer.renderFrame()
            Thread.sleep(forTimeInterval: 0.2)

            let secondAttrs = try FileManager.default.attributesOfItem(atPath: firstPath.path)
            let secondMtime = secondAttrs[.modificationDate] as? Date

            #expect(firstMtime == secondMtime)

            drainGPUWork()
        }
    }
}
