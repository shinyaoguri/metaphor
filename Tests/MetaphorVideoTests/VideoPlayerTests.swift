import Testing
import Foundation
import Metal
import os
@testable import MetaphorVideo

@Suite("VideoPlayer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct VideoPlayerTests {

    @Test("Non-existent file throws fileNotFound")
    func fileNotFound() {
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!

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

// MARK: - NotificationObserverToken

/// `VideoPlayer` relies on releasing the token (rather than a `deinit` that touches
/// `@MainActor` state) to unregister its `AVPlayerItemDidPlayToEndTime` observer.
/// If that ever regresses, a released player keeps receiving notifications.
@Suite("NotificationObserverToken")
struct NotificationObserverTokenTests {

    @Test("releasing the token stops delivery")
    func releasingTokenUnregisters() {
        let name = Notification.Name("metaphor.test.\(UUID().uuidString)")
        let hits = Counter()
        let center = NotificationCenter()

        var token: NotificationObserverToken? = NotificationObserverToken(
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                hits.increment()
            },
            center: center
        )
        #expect(token != nil)

        center.post(name: name, object: nil)
        #expect(hits.value == 1)

        // 解放 = 解除。ここで removeObserver されないと次の post も届いてしまう。
        token = nil
        center.post(name: name, object: nil)
        #expect(hits.value == 1)
    }

    @Test("the token keeps delivery alive while it is retained")
    func retainedTokenKeepsDelivering() {
        let name = Notification.Name("metaphor.test.\(UUID().uuidString)")
        let hits = Counter()
        let center = NotificationCenter()

        let token = NotificationObserverToken(
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                hits.increment()
            },
            center: center
        )

        center.post(name: name, object: nil)
        center.post(name: name, object: nil)
        #expect(hits.value == 2)
        withExtendedLifetime(token) {}
    }
}

/// Counts synchronous notification deliveries. The observer block is `@Sendable`,
/// so the counter has to be safe to capture.
private final class Counter: Sendable {
    private let box = OSAllocatedUnfairLock(initialState: 0)
    func increment() { box.withLock { $0 += 1 } }
    var value: Int { box.withLock { $0 } }
}
