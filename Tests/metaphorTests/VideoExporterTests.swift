import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - VideoExportConfig Tests

@Suite("VideoExportConfig")
struct VideoExportConfigTests {

    @Test("default values are correct")
    func defaultValues() {
        let config = VideoExportConfig()
        #expect(config.fps == 60)
        #expect(config.bitrate == 10_000_000)
    }

    @Test("custom values are preserved")
    func customValues() {
        let config = VideoExportConfig(
            codec: .h265,
            format: .mov,
            fps: 30,
            bitrate: 20_000_000
        )
        #expect(config.fps == 30)
        #expect(config.bitrate == 20_000_000)
    }
}

// MARK: - VideoCodec Tests

@Suite("VideoCodec")
struct VideoCodecTests {

    @Test("h264 codec")
    func h264() {
        let codec = VideoCodec.h264
        #expect(codec == .h264)
    }

    @Test("h265 codec")
    func h265() {
        let codec = VideoCodec.h265
        #expect(codec == .h265)
    }
}

// MARK: - VideoFormat Tests

@Suite("VideoFormat")
struct VideoFormatTests {

    @Test("mp4 file extension")
    func mp4Extension() {
        let format = VideoFormat.mp4
        #expect(format.fileExtension == "mp4")
    }

    @Test("mov file extension")
    func movExtension() {
        let format = VideoFormat.mov
        #expect(format.fileExtension == "mov")
    }
}

// MARK: - VideoExporter State Tests

@Suite("VideoExporter State")
@MainActor
struct VideoExporterStateTests {

    @Test("initial state is not recording")
    func initialState() {
        let exporter = VideoExporter()
        #expect(exporter.isRecording == false)
    }

    @Test("beginRecord transitions to recording state")
    func beginRecordState() throws {
        let exporter = VideoExporter()
        let tempDir = NSTemporaryDirectory()
        let path = tempDir + "test_video_\(ProcessInfo.processInfo.globallyUniqueString).mp4"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try exporter.beginRecord(path: path, width: 320, height: 240)
        #expect(exporter.isRecording == true)

        // Clean up
        exporter.endRecord()
    }

    @Test("endRecord transitions back to not recording")
    func endRecordState() throws {
        let exporter = VideoExporter()
        let tempDir = NSTemporaryDirectory()
        let path = tempDir + "test_video_\(ProcessInfo.processInfo.globallyUniqueString).mp4"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try exporter.beginRecord(path: path, width: 320, height: 240)
        #expect(exporter.isRecording == true)

        exporter.endRecord()
        #expect(exporter.isRecording == false)
    }

    @Test("beginRecord while already recording is ignored")
    func doubleBeginRecord() throws {
        let exporter = VideoExporter()
        let tempDir = NSTemporaryDirectory()
        let path1 = tempDir + "test_video1_\(ProcessInfo.processInfo.globallyUniqueString).mp4"
        let path2 = tempDir + "test_video2_\(ProcessInfo.processInfo.globallyUniqueString).mp4"
        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }

        try exporter.beginRecord(path: path1, width: 320, height: 240)
        #expect(exporter.isRecording == true)

        // Second begin should be silently ignored
        try exporter.beginRecord(path: path2, width: 320, height: 240)
        #expect(exporter.isRecording == true)

        exporter.endRecord()
    }

    @Test("endRecord when not recording calls completion immediately")
    func endRecordWhenNotRecording() {
        let exporter = VideoExporter()
        nonisolated(unsafe) var completionCalled = false

        exporter.endRecord {
            completionCalled = true
        }

        #expect(completionCalled == true)
    }

    @Test("beginRecord clamps non-positive fps instead of producing invalid CMTime")
    func fpsClamped() throws {
        let exporter = VideoExporter()
        let path = NSTemporaryDirectory() + "test_video_fps0_\(ProcessInfo.processInfo.globallyUniqueString).mp4"
        defer { try? FileManager.default.removeItem(atPath: path) }

        // fps 0 は timescale 0 の不正 CMTime を作っていた。クランプされて begin が成功する
        try exporter.beginRecord(
            path: path, width: 320, height: 240,
            config: VideoExportConfig(fps: 0)
        )
        #expect(exporter.isRecording == true)
        exporter.endRecord()
    }
}

// MARK: - VideoExporter End-to-End Tests

@Suite("VideoExporter EndToEnd", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct VideoExporterEndToEndTests {

    @Test("recorded file finalizes without error and exists on disk")
    func endToEndRecording() async throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        renderer.useExternalRenderLoop = true

        let path = NSTemporaryDirectory() + "metaphor_video_e2e_\(UUID().uuidString).mp4"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try renderer.videoExporter.beginRecord(path: path, width: 64, height: 64)
        for i in 0..<5 {
            renderer.setClearColor(Double(i) * 0.2, 0.5, 1.0)
            renderer.renderFrame()
        }
        await renderer.videoExporter.endRecord()

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(renderer.videoExporter.lastError == nil,
                "finalize error: \(String(describing: renderer.videoExporter.lastError))")
        #expect(renderer.videoExporter.droppedFrameCount == 0)

        // 空でない mp4 が書かれていること
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int) ?? 0
        #expect(size > 0)
    }
}

// MARK: - FrameExporter Pattern Validation Tests

@Suite("FrameExporter Pattern")
@MainActor
struct FrameExporterPatternTests {

    @Test("valid patterns", arguments: [
        "frame_%05d.png", "%d.png", "img%03u.png", "f_%x.png", "cap %04d.png", "100%%_%d.png"
    ])
    func validPatterns(pattern: String) {
        #expect(FrameExporter.isValidPattern(pattern) == true)
    }

    @Test("invalid patterns", arguments: [
        "frame.png",        // 指定子なし: 全フレームが同名で上書きされる
        "frame_%@.png",     // %@: String(format:) でクラッシュ
        "frame_%s.png",     // %s: 未サポート
        "a%d_b%d.png",      // 指定子 2 個
        "frame_%f.png",     // 浮動小数
        "trailing%"         // 不完全な指定子
    ])
    func invalidPatterns(pattern: String) {
        #expect(FrameExporter.isValidPattern(pattern) == false)
    }

    @Test("invalid pattern falls back to default without crashing")
    func invalidPatternFallback() {
        let exporter = FrameExporter()
        let dir = NSTemporaryDirectory() + "metaphor_frames_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        exporter.beginSequence(directory: dir, pattern: "frame_%@.png")
        #expect(exporter.isRecording == true)
        exporter.endSequence()
    }
}
