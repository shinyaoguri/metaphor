import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - テスト用の宣言ホスト

/// 型ごとのウィジェット選択とレイアウトを見るための全部入りホスト。
@MainActor
private final class MixedHost {
    @Param(min: 10, max: 200) var radius: Float = 50
    @Param(min: 1, max: 512) var count: Int = 4
    @Param var showGrid: Bool = true
    @Param var tint: Color = Color(r: 1, g: 1, b: 1, a: 1)
    @Param var origin: Vec2 = Vec2(0, 0)
    @Param var axis: Vec3 = Vec3(0, 1, 0)
    @Param(choices: ["add", "multiply"]) var blend: String = "add"
    @Param var title: String = "free text"
}

@MainActor
private final class FloatHost {
    @Param(min: 10, max: 200) var radius: Float = 50
}

@MainActor
private final class BoolHost {
    @Param var showGrid: Bool = false
}

@MainActor
private final class ChoiceHost {
    @Param(choices: ["add", "multiply", "screen"]) var blend: String = "add"
}

@MainActor
private final class RangelessHost {
    @Param var speed: Float = 30
}

// MARK: - テスト

/// `gui.params()`（Parameter Store D2）の store 束縛と自動レイアウト。
///
/// GUI は自前の値を持たず ``ParameterStore`` を唯一の真実とします。ここでは
/// 「レイアウト表と実際の描画が一致すること」「操作がストア経由で反映されること」
/// 「操作していないフレームでは `revision` が動かないこと」を確認します。
@Suite("Parameter GUI (store-backed)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ParameterGUIStoreTests {

    /// オフスクリーン 1 フレームを回すハーネス（実スケッチと同じ結線）。
    private func makeHarness(
        draw: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: 320, height: 320)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        return (renderer, context)
    }

    // MARK: - レイアウト

    @Test("レイアウト表の行高と実際のウィジェットの進み方が一致する")
    func layoutTableMatchesWidgets() throws {
        let host = MixedHost()
        var deltas: [String: (actual: Float, table: Float)] = [:]
        let (renderer, context) = try makeHarness { c in
            let gui = c.gui
            gui.begin()
            for name in c.params.names {
                guard let descriptor = c.params.descriptor(name) else { continue }
                let top = gui.currentY
                gui.drawRow(
                    name, descriptor, store: c.params, canvas: c.canvas, input: c.input
                )
                deltas[name] = (gui.currentY - top, gui.rowHeight(for: descriptor))
            }
        }
        context.params.discover(in: host)
        renderer.renderFrame()

        #expect(deltas.count == context.params.names.count)
        for (name, d) in deltas {
            #expect(d.actual == d.table, "\(name): 実測 \(d.actual) ≠ 表 \(d.table)")
        }
    }

    @Test("パネル高は 1 フレーム目から全行を覆う（背景が遅れて出ない）")
    func panelHeightCoversAllRowsOnFirstFrame() throws {
        let host = MixedHost()
        var rect: (Float, Float, Float, Float) = (0, 0, 0, 0)
        var expected: Float = 0
        let (renderer, context) = try makeHarness { c in
            rect = c.gui.params()
            expected = c.params.names
                .compactMap { c.params.descriptor($0) }
                .reduce(c.gui.padding * 2) { $0 + c.gui.rowHeight(for: $1) }
        }
        context.params.discover(in: host)
        renderer.renderFrame()

        #expect(rect.3 == expected)
        #expect(rect.3 > 0)
    }

    @Test("パラメータが無ければ何も描かない")
    func emptyStoreDrawsNothing() throws {
        var rect: (Float, Float, Float, Float) = (0, 0, 1, 1)
        let (renderer, _) = try makeHarness { c in
            rect = c.gui.params()
        }
        renderer.renderFrame()
        #expect(rect.2 == 0)
        #expect(rect.3 == 0)
    }

    @Test("宣言されていない名前は何も描かずレイアウトを進めない")
    func unknownNameIsIgnored() throws {
        var before: Float = -1
        var after: Float = -2
        let (renderer, _) = try makeHarness { c in
            c.gui.begin()
            before = c.gui.currentY
            c.gui.param("nope")
            after = c.gui.currentY
        }
        renderer.renderFrame()
        #expect(before == after)
    }

    // MARK: - 操作 → ストア

    @Test("スライダーのドラッグはストア経由で値を書く（クランプ込み）")
    func sliderDragWritesThroughStore() throws {
        let host = FloatHost()
        let (renderer, context) = try makeHarness { c in
            c.gui.params()
        }
        context.params.discover(in: host)

        // 1 行目のトラック: x = 14…214, y = 28…44。中央を掴む。
        context.input.handleMouseDown(x: 114, y: 34, button: .left)
        renderer.renderFrame()

        #expect(host.radius == 105)                     // 10 + 190 * 0.5
        #expect(context.params.value("radius") == .float(105))
        #expect(context.params.revision > 0)

        // トラック右端の外へドラッグしても宣言レンジを超えない。
        context.input.handleMouseDragged(x: 400, y: 34)
        renderer.renderFrame()
        #expect(host.radius == 200)
    }

    @Test("操作していないフレームでは revision が動かない（毎フレーム書き出さない）")
    func idleFramesDoNotBumpRevision() throws {
        let host = MixedHost()
        let (renderer, context) = try makeHarness { c in
            c.gui.params()
        }
        context.params.discover(in: host)

        renderer.renderFrame()
        let after1 = context.params.revision
        renderer.renderFrame()
        renderer.renderFrame()
        #expect(context.params.revision == after1)
    }

    @Test("トグルのクリックはストア経由で真偽値を反転する")
    func toggleClickFlipsThroughStore() throws {
        let host = BoolHost()
        let (renderer, context) = try makeHarness { c in
            c.gui.params()
        }
        context.params.discover(in: host)

        // チェックボックス: x = 14…214, y = 16…34。
        context.input.handleMouseDown(x: 20, y: 24, button: .left)
        renderer.renderFrame()
        #expect(host.showGrid == true)
        #expect(context.params.value("showGrid") == .bool(true))

        // 押しっぱなしのフレームでは再発火しない（エッジ検出）。
        renderer.renderFrame()
        #expect(host.showGrid == true)
    }

    @Test("choices 付き string はクリックで次の候補へ回り、末尾で先頭へ戻る")
    func choiceClickCyclesAndWraps() throws {
        let host = ChoiceHost()
        let (renderer, context) = try makeHarness { c in
            c.gui.params()
        }
        context.params.discover(in: host)

        // 候補ボックス: x = 14…214, y = 28…44。
        for expected in ["multiply", "screen", "add"] {
            context.input.handleMouseUp(x: 100, y: 34, button: .left)
            renderer.renderFrame()
            context.input.handleMouseDown(x: 100, y: 34, button: .left)
            renderer.renderFrame()
            #expect(host.blend == expected)
        }
    }

    // MARK: - 自動レンジ

    @Test("レンジ未宣言のパラメータは初回表示のレンジを固定して使う")
    func autoRangeIsStableAcrossFrames() throws {
        let host = RangelessHost()
        var ranges: [(min: Float, max: Float)] = []
        let (renderer, context) = try makeHarness { c in
            guard let descriptor = c.params.descriptor("speed") else { return }
            ranges.append(
                c.gui.range(for: "speed", descriptor: descriptor, magnitude: host.speed)
            )
        }
        context.params.discover(in: host)

        renderer.renderFrame()                 // 30 → 0…100
        host.speed = 3
        renderer.renderFrame()                 // 値が動いてもレンジは固定
        #expect(ranges.count == 2)
        #expect(ranges[0] == ranges[1])
        #expect(ranges[0].min == 0)
        #expect(ranges[0].max == 100)
    }

    @Test("自動レンジの上限はキリの良い 1 / 2 / 5 × 10^n になる")
    func niceCeilRoundsToNiceNumbers() {
        func isClose(_ a: Float, _ b: Float) -> Bool { abs(a - b) <= abs(b) * 1e-5 + 1e-7 }
        #expect(isClose(ParameterGUI.niceCeil(0.03), 0.05))
        #expect(isClose(ParameterGUI.niceCeil(1), 1))
        #expect(isClose(ParameterGUI.niceCeil(1.2), 2))
        #expect(isClose(ParameterGUI.niceCeil(6), 10))
        #expect(isClose(ParameterGUI.niceCeil(60), 100))
        #expect(isClose(ParameterGUI.niceCeil(0), 1))      // 値 0 でも潰れない
    }
}
