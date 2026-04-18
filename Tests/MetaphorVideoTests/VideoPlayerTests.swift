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
}
