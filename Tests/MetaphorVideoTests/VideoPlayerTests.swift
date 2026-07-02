import Testing
import Foundation
import Metal
@testable import MetaphorVideo

@Suite("VideoPlayer")
@MainActor
struct VideoPlayerTests {

    @Test("Non-existent file throws fileNotFound")
    func fileNotFound() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        #expect(throws: VideoPlayerError.self) {
            _ = try VideoPlayer(path: "/nonexistent/video.mp4", device: device)
        }
    }

    @Test("VideoPlayerError description contains path")
    func errorDescription() {
        let error = VideoPlayerError.fileNotFound("/test/path.mp4")
        #expect(error.errorDescription?.contains("/test/path.mp4") == true)
    }

    @Test("VideoPlayerError description contains prefix")
    func errorPrefix() {
        let error = VideoPlayerError.fileNotFound("/test/path.mp4")
        #expect(error.errorDescription?.contains("Video file not found") == true)
    }

    @Test("playbackFailed error has description")
    func playbackFailedDescription() {
        let error = VideoPlayerError.playbackFailed("unsupported codec")
        #expect(error.errorDescription?.contains("unsupported codec") == true)
    }

    @Test("corrupt file surfaces an error via lastError")
    func corruptFileSurfacesError() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        // 中身がゴミの .mp4（存在チェックは通るが AVPlayerItem が失敗する）
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-corrupt-\(UUID().uuidString).mp4")
        try Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let player = try VideoPlayer(path: url.path, device: device)
        // 修正前は duration 0・フレーム無しの silent failure だった
        #expect(player.duration == 0)

        // AVPlayerItem.status == .failed は非同期に確定するためポーリングする
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline, player.lastError == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        #expect(player.lastError != nil)
    }
}
