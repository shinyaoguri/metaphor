import Testing
import Metal
@testable import MetaphorCore

/// `AutoSubsystemManager` が登録サブシステムのライフサイクルと毎フレーム更新を
/// 正しく駆動することを確認する。
@Suite("AutoSubsystemManager")
@MainActor
struct SubsystemTests {

    final class RecordingSubsystem: SketchSubsystem {
        private(set) var started = 0
        private(set) var stopped = 0
        private(set) var deltas: [Float] = []
        func onStart() { started += 1 }
        func onStop() { stopped += 1 }
        func update(deltaTime: Float) { deltas.append(deltaTime) }
    }

    @Test("onStart/onStop forward to all subsystems")
    func lifecycleForwards() {
        let a = RecordingSubsystem()
        let b = RecordingSubsystem()
        let manager = AutoSubsystemManager([a, b])

        manager.onStart()
        manager.onStop()

        #expect(a.started == 1 && a.stopped == 1)
        #expect(b.started == 1 && b.stopped == 1)
    }

    @Test("pre() drives update with computed deltaTime",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func updateDeltaTime() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let sub = RecordingSubsystem()
        let manager = AutoSubsystemManager([sub])

        manager.onStart()
        let cb1 = try #require(queue.makeCommandBuffer())
        manager.pre(commandBuffer: cb1, time: 0.0)   // 初回は delta 0
        let cb2 = try #require(queue.makeCommandBuffer())
        manager.pre(commandBuffer: cb2, time: 0.5)   // 0.5 秒経過

        #expect(sub.deltas.count == 2)
        #expect(sub.deltas[0] == 0)
        #expect(abs(sub.deltas[1] - 0.5) < 0.0001)
    }
}
