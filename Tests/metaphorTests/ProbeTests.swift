import Foundation
import ImageIO
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
        // frames/every が無いリクエストは単一フレーム扱い（nil）。
        #expect(request.frames == nil)
        #expect(request.every == nil)
    }

    @Test("decode sequence request fields")
    func decodeSequenceFields() throws {
        let json = #"{"id":"abc","frames":8,"every":2}"#
        let request = try JSONDecoder().decode(
            ProbeRequest.self, from: Data(json.utf8)
        )
        #expect(request.id == "abc")
        #expect(request.frames == 8)
        #expect(request.every == 2)
    }
}

// MARK: - Plugin behavior (GPU-gated)

@Suite("MetaphorProbe snapshot capture", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MetaphorProbePluginTests {

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

    /// 指定 id・label・scale のリクエストファイルを書き込みます。
    private func writeRequest(
        id: String, label: String? = nil, scale: Double? = nil, to path: URL
    ) throws {
        var dict: [String: Any] = ["id": id]
        if let label { dict["label"] = label }
        if let scale { dict["scale"] = scale }
        let data = try JSONSerialization.data(withJSONObject: dict)
        try data.write(to: path)
    }

    /// 任意ファイルの出現をポーリングします。
    private func waitForFile(_ url: URL, timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// PNG ファイルのピクセルサイズを返します。
    private func pngSize(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (w, h)
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
                    plugin.recordValue(name: "test.pos", value: .vec2(1, 2))
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
            #expect(json?["schemaVersion"] as? Int == 4)
            // sourceStamp 未設定（config も env も無し）なら additive キーは省略される。
            #expect(json?["sourceStamp"] == nil)
            let size = json?["size"] as? [String: Int]
            #expect(size?["width"] == 128)
            #expect(size?["height"] == 96)
            let custom = json?["custom"] as? [String: Any]
            #expect(custom?["test.count"] as? Int == 42)
            #expect(custom?["test.label"] as? String == "hello")

            // schemaVersion 3: custom の各キーに型タグが併記される。
            // vec2 は値だけだと 2 要素配列と区別できないため型タグで判別する。
            #expect((custom?["test.pos"] as? [Double])?.count == 2)
            let customTypes = json?["customTypes"] as? [String: String]
            #expect(customTypes?["test.count"] == "int")
            #expect(customTypes?["test.label"] == "string")
            #expect(customTypes?["test.pos"] == "vec2")

            // schemaVersion 2: stats ブロックが書き出される。
            let stats = json?["stats"] as? [String: Any]
            #expect(stats != nil)
            #expect(stats?["sampleGrid"] as? Int == 32)
            let meanColor = stats?["meanColor"] as? [Double]
            #expect(meanColor?.count == 3)
            #expect(stats?["meanLuminance"] != nil)
            #expect(stats?["contentFraction"] != nil)

        }
    }

    @Test("sourceStamp from config appears in frame.json (schemaVersion 4)")
    func sourceStampIsWritten() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path,
                    sourceStamp: "build-abc123"
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            try writeRequest(id: "stamp-1", to: requestPath)
            renderer.renderFrame()

            _ = waitForFrame(in: outputDir)
            let jsonPath = outputDir.appendingPathComponent("frame.json")
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline,
                  !FileManager.default.fileExists(atPath: jsonPath.path) {
                Thread.sleep(forTimeInterval: 0.05)
            }

            let data = try Data(contentsOf: jsonPath)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["schemaVersion"] as? Int == 4)
            #expect(json?["sourceStamp"] as? String == "build-abc123")

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

            // 単色フレームはコンテンツ無し: contentFraction 0、contentBounds は省略（nil）。
            let stats = json?["stats"] as? [String: Any]
            #expect((stats?["contentFraction"] as? Double) == 0)
            #expect(stats?["contentBounds"] == nil)

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

        }
    }

    @Test("an unreadable request.json is retried on the next frame")
    func unreadableRequestRetried() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 32, height: 32)
            renderer.addPlugin(plugin)

            try writeRequest(id: "retry-1", to: requestPath)
            // 読み取り不可にして 1 フレーム回す（mtime は変わらない）
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: requestPath.path
            )
            renderer.renderFrame()

            // 読めるようにして再度回すと、同じ mtime のまま再試行されて処理される。
            // 修正前は読み取り失敗の時点で mtime を消費し、永久に無視されていた
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: requestPath.path
            )
            renderer.renderFrame()

            #expect(waitForFrame(in: outputDir) != nil)
        }
    }

    @Test("a request arriving during a sequence is processed afterwards")
    func requestDuringSequenceNotLost() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 32, height: 32)
            renderer.addPlugin(plugin)

            // frames=2 のシーケンスを開始
            let seqRequest = try JSONSerialization.data(
                withJSONObject: ["id": "seq-A", "frames": 2]
            )
            try seqRequest.write(to: requestPath)
            renderer.renderFrame()  // シーケンス受理 + frame 0 採取

            // シーケンス進行中に新しい単一リクエストが届く
            try writeRequest(id: "single-B", to: requestPath)
            renderer.renderFrame()  // frame 1 採取 → シーケンス完了
            renderer.renderFrame()  // 完了後の pre() で single-B が処理される
            renderer.renderFrame()

            // 修正前はシーケンス中に mtime が消費され、single-B は永久に無視された
            #expect(waitForFrame(in: outputDir) != nil)
            let jsonURL = outputDir.appendingPathComponent("frame.json")
            #expect(waitForFile(jsonURL))
            let json = try JSONSerialization.jsonObject(
                with: Data(contentsOf: jsonURL)
            ) as? [String: Any]
            #expect(json?["id"] as? String == "single-B")

        }
    }

    @Test("request scale 0.5 halves the PNG and frame.json size (contract point 4)")
    func scaleHalvesOutput() throws {
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

            try writeRequest(id: "scale-1", scale: 0.5, to: requestPath)
            renderer.renderFrame()

            let png = waitForFrame(in: outputDir)
            #expect(png != nil)
            if let png {
                let size = pngSize(of: png)
                #expect(size?.width == 32)
                #expect(size?.height == 32)
            }

            // frame.json の size もスケール後の値になる
            let jsonURL = outputDir.appendingPathComponent("frame.json")
            #expect(waitForFile(jsonURL))
            let json = try JSONSerialization.jsonObject(
                with: Data(contentsOf: jsonURL)
            ) as? [String: Any]
            let size = json?["size"] as? [String: Any]
            #expect(size?["width"] as? Int == 32)
            #expect(size?["height"] as? Int == 32)

        }
    }

    @Test("defaultScale applies when the request omits scale")
    func defaultScaleApplies() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path,
                    defaultScale: 0.25
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            try writeRequest(id: "scale-default", to: requestPath)
            renderer.renderFrame()

            let png = waitForFrame(in: outputDir)
            #expect(png != nil)
            if let png {
                let size = pngSize(of: png)
                #expect(size?.width == 16)
                #expect(size?.height == 16)
            }

        }
    }

    @Test("invalid scale values fall back to full size")
    func invalidScaleFallsBack() throws {
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

            // 0 以下は無効 → フルサイズ
            try writeRequest(id: "scale-invalid", scale: -1.0, to: requestPath)
            renderer.renderFrame()

            let png = waitForFrame(in: outputDir)
            #expect(png != nil)
            if let png {
                let size = pngSize(of: png)
                #expect(size?.width == 64)
                #expect(size?.height == 64)
            }

        }
    }
}

// MARK: - ProbeWriter scale helpers

@Suite("ProbeWriter scale")
struct ProbeWriterScaleTests {

    @Test("normalizeScale clamps invalid values to 1.0")
    func normalizeScale() {
        #expect(ProbeWriter.normalizeScale(0.5) == 0.5)
        #expect(ProbeWriter.normalizeScale(1.0) == 1.0)
        #expect(ProbeWriter.normalizeScale(0) == 1.0)
        #expect(ProbeWriter.normalizeScale(-0.5) == 1.0)
        #expect(ProbeWriter.normalizeScale(2.0) == 1.0)
        #expect(ProbeWriter.normalizeScale(.nan) == 1.0)
        #expect(ProbeWriter.normalizeScale(.infinity) == 1.0)
    }

    @Test("scaledSize rounds and clamps to at least 1px")
    func scaledSize() {
        let half = ProbeWriter.scaledSize(width: 64, height: 64, scale: 0.5)
        #expect(half.width == 32 && half.height == 32)

        let tiny = ProbeWriter.scaledSize(width: 10, height: 10, scale: 0.01)
        #expect(tiny.width == 1 && tiny.height == 1)

        let full = ProbeWriter.scaledSize(width: 64, height: 48, scale: 1.0)
        #expect(full.width == 64 && full.height == 48)

        let odd = ProbeWriter.scaledSize(width: 65, height: 65, scale: 0.5)
        #expect(odd.width == 33 && odd.height == 33)
    }
}

// MARK: - ProbeWriter failure response

@Suite("ProbeWriter failure response")
struct ProbeWriterFailureResponseTests {

    @Test("writeFailureResponse writes frame.json with warnings and no PNG")
    func failureResponseWritesJSONOnly() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            // 前回応答の frame.png が残っているケース: 失敗応答はこれを削除する
            // （consumer が新しい id の frame.json と古い画像を組にしないため）。
            try Data([0x89, 0x50, 0x4E, 0x47]).write(
                to: dir.appendingPathComponent("frame.png")
            )
            let metadata = ProbeFrameMetadata(
                schemaVersion: 4,
                id: "fail-1",
                label: nil,
                sourceStamp: nil,
                frame: 3,
                time: 0.5,
                size: ProbeFrameMetadata.Size(width: 64, height: 64),
                custom: [:],
                customTypes: [:],
                warnings: ["failed to allocate staging texture; frame.png was not written"],
                stats: nil,
                performance: nil
            )
            ProbeWriter.writeFailureResponse(directory: dir.path, metadata: metadata)

            // 書き出しは専用キューで非同期に行われるためポーリングで待つ
            let jsonURL = dir.appendingPathComponent("frame.json")
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline,
                  !FileManager.default.fileExists(atPath: jsonURL.path) {
                Thread.sleep(forTimeInterval: 0.05)
            }

            #expect(FileManager.default.fileExists(atPath: jsonURL.path))
            #expect(!FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("frame.png").path
            ))

            let json = try JSONSerialization.jsonObject(
                with: Data(contentsOf: jsonURL)
            ) as? [String: Any]
            #expect(json?["id"] as? String == "fail-1")
            let warnings = json?["warnings"] as? [String]
            #expect(warnings?.count == 1)
            #expect(warnings?.first?.contains("staging") == true)
        }
    }
}

// MARK: - Sequence capture (GPU-gated)

@Suite("MetaphorProbe sequence capture", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MetaphorProbeSequenceTests {

    private func waitForFile(_ url: URL, timeout: TimeInterval = 5.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func writeSequenceRequest(
        id: String, frames: Int, every: Int? = nil, label: String? = nil, to path: URL
    ) throws {
        var dict: [String: Any] = ["id": id, "frames": frames]
        if let every { dict["every"] = every }
        if let label { dict["label"] = label }
        let data = try JSONSerialization.data(withJSONObject: dict)
        try data.write(to: path)
    }

    @Test("sequence request produces frames, contact sheet, and manifest")
    func sequenceProducesOutputs() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 64, height: 48)
            renderer.addPlugin(plugin)

            try writeSequenceRequest(id: "seq-1", frames: 4, label: "motion", to: requestPath)
            // frames=4, every=1 → 4 renderFrame で 4 枚採取。
            for _ in 0..<4 { renderer.renderFrame() }

            let seqDir = outputDir.appendingPathComponent("sequence")
            let manifestURL = seqDir.appendingPathComponent("sequence.json")
            // manifest は最後に書かれる完了シグナル。出れば全 PNG が出揃っている。
            #expect(waitForFile(manifestURL))

            for i in 0..<4 {
                let name = String(format: "frame.%04d.png", i)
                #expect(FileManager.default.fileExists(
                    atPath: seqDir.appendingPathComponent(name).path
                ))
            }
            #expect(FileManager.default.fileExists(
                atPath: seqDir.appendingPathComponent("contact_sheet.png").path
            ))

            let data = try Data(contentsOf: manifestURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["id"] as? String == "seq-1")
            #expect(json?["label"] as? String == "motion")
            #expect(json?["frameCount"] as? Int == 4)
            #expect(json?["schemaVersion"] as? Int == 1)
            #expect(json?["contactSheet"] as? String == "contact_sheet.png")
            let frames = json?["frames"] as? [[String: Any]]
            #expect(frames?.count == 4)
            #expect(frames?.first?["file"] as? String == "frame.0000.png")
            let size = json?["size"] as? [String: Int]
            #expect(size?["width"] == 64)
            #expect(size?["height"] == 48)

        }
    }

    @Test("every stride captures fewer frames")
    func strideCapturesFewer() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 32, height: 32)
            renderer.addPlugin(plugin)

            // frames=2, every=2 → tick0 採取 / tick1 skip / tick2 採取 → 3 renderFrame で 2 枚。
            try writeSequenceRequest(id: "seq-stride", frames: 2, every: 2, to: requestPath)
            for _ in 0..<3 { renderer.renderFrame() }

            let seqDir = outputDir.appendingPathComponent("sequence")
            let manifestURL = seqDir.appendingPathComponent("sequence.json")
            #expect(waitForFile(manifestURL))

            let data = try Data(contentsOf: manifestURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["frameCount"] as? Int == 2)
            #expect(json?["every"] as? Int == 2)
            // 採取されたのは index 0,1 の 2 枚だけ（スキップされた tick はファイルにならない）。
            #expect(FileManager.default.fileExists(
                atPath: seqDir.appendingPathComponent("frame.0001.png").path
            ))
            #expect(!FileManager.default.fileExists(
                atPath: seqDir.appendingPathComponent("frame.0002.png").path
            ))

        }
    }

    @Test("single-frame request does not create a sequence directory")
    func singleFrameNoSequenceDir() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let requestPath = dir.appendingPathComponent("request.json")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    requestFilePath: requestPath.path
                )
            )

            let renderer = try MetaphorRenderer(width: 32, height: 32)
            renderer.addPlugin(plugin)

            // frames 無し（単一フレーム）。
            let data = try JSONSerialization.data(withJSONObject: ["id": "single-1"])
            try data.write(to: requestPath)
            renderer.renderFrame()

            #expect(waitForFile(outputDir.appendingPathComponent("frame.png")))
            // sequence/ は作られない。
            #expect(!FileManager.default.fileExists(
                atPath: outputDir.appendingPathComponent("sequence").path
            ))

        }
    }
}
