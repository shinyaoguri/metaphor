import Testing
import Metal
import Foundation
import os
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Test line source

/// テスト用の決定的なイベント供給元。与えた行を順に返し、尽きたら nil を返す
/// （= リーダースレッドは全行消費後に終了する）。
private final class LineFeeder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(_ lines: [String]) {
        lock.withLock { $0 = lines }
    }

    func next() -> String? {
        lock.withLock { lines in
            guard !lines.isEmpty else { return nil }
            return lines.removeFirst()
        }
    }
}

@Suite("InputInjectionPlugin", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct InputInjectionPluginTests {

    /// `pre()` を繰り返しポンプして、リーダースレッドが注入したイベントが
    /// `InputManager` に反映される（条件成立）まで待つ。
    private func pump(
        _ renderer: MetaphorRenderer,
        _ plugin: InputInjectionPlugin,
        until condition: () -> Bool,
        timeout: TimeInterval = 2.0
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let cb = renderer.commandQueue.makeCommandBuffer() {
                plugin.pre(commandBuffer: cb, time: 0)
                cb.commit()
            }
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    @Test("mouseMove event updates InputManager position")
    func mouseMoveInjected() throws {
        let renderer = try MetaphorRenderer(width: 100, height: 100)
        let feeder = LineFeeder([
            #"{"t":"mouseMove","x":42.0,"y":17.0}"#
        ])
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })
        renderer.addPlugin(plugin)

        pump(renderer, plugin, until: { renderer.input.mouseX == 42 })

        #expect(renderer.input.mouseX == 42)
        #expect(renderer.input.mouseY == 17)
    }

    @Test("mouseDown event sets pressed state and button")
    func mouseDownInjected() throws {
        let renderer = try MetaphorRenderer(width: 100, height: 100)
        let feeder = LineFeeder([
            #"{"t":"mouseDown","x":10.0,"y":20.0,"button":1}"#
        ])
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })
        renderer.addPlugin(plugin)

        pump(renderer, plugin, until: { renderer.input.isMouseDown })

        #expect(renderer.input.isMouseDown)
        #expect(renderer.input.mouseButton == 1)
        #expect(renderer.input.mouseX == 10)
        #expect(renderer.input.mouseY == 20)
    }

    @Test("keyDown event registers the key code")
    func keyDownInjected() throws {
        let renderer = try MetaphorRenderer(width: 100, height: 100)
        let feeder = LineFeeder([
            #"{"t":"keyDown","code":53,"chars":"a","repeat":false}"#
        ])
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })
        renderer.addPlugin(plugin)

        pump(renderer, plugin, until: { renderer.input.isKeyDown(53) })

        #expect(renderer.input.isKeyDown(53))
        #expect(renderer.input.isKeyPressed)
    }

    @Test("malformed lines are ignored, valid lines still applied")
    func malformedLinesIgnored() throws {
        let renderer = try MetaphorRenderer(width: 100, height: 100)
        let feeder = LineFeeder([
            "not json at all",
            "{ broken",
            #"{"t":"unknownEvent","x":1.0}"#,
            #"{"t":"mouseMove","x":99.0,"y":88.0}"#
        ])
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })
        renderer.addPlugin(plugin)

        pump(renderer, plugin, until: { renderer.input.mouseX == 99 })

        #expect(renderer.input.mouseX == 99)
        #expect(renderer.input.mouseY == 88)
    }

    @Test("plugin id is stable")
    func pluginID() {
        let plugin = InputInjectionPlugin(lineSource: { nil })
        #expect(plugin.pluginID == InputInjectionPlugin.id)
    }
}
