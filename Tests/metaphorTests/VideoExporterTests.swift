import Testing
@testable import metaphor

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
}
