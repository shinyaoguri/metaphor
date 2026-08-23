import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorRenderGraph

/// ブリッジの `create*` に統合された引数検証（ADR-0005 フェーズ 2、#200）を確認する。
/// 不正な引数は warning + 安全なフォールバック（またはコンテキスト非依存の nil）で
/// 処理され、クラッシュや不正状態のインスタンスを作らない。検証は context に
/// 触れないため、GPU を必要としない最小の Sketch で実行できる。
///
/// 旧 `make*` バリアント（throws）は deprecated（次の minor で削除予定）。
/// `-warnings-as-errors` の CI では deprecated API を呼べないため、テストは
/// `create*` 側の検証セマンティクスを固定する。
@Suite("Bridge validation")
@MainActor
struct BridgeValidationTests {

    final class MinimalSketch: Sketch {
        var config = SketchConfig()
        init() {}
        func setup() {}
        func draw() {}
    }

    @Test("createAudioInput falls back to 1024 for non power-of-two fftSize")
    func audioFallsBackForNonPowerOfTwo() {
        let sketch = MinimalSketch()
        let analyzer = sketch.createAudioInput(fftSize: 1000)
        // spectrum のビン数 = fftSize / 2。フォールバック（1024）なら 512
        #expect(analyzer.spectrum.count == 512, "不正な fftSize はデフォルト 1024 へフォールバック")
    }

    @Test("createAudioInput accepts power-of-two fftSize")
    func audioAcceptsPowerOfTwo() {
        let sketch = MinimalSketch()
        let analyzer = sketch.createAudioInput(fftSize: 2048)
        #expect(analyzer.spectrum.count == 1024)
    }

    @Test("createPhysics2D falls back to 50 for non-positive cellSize")
    func physicsFallsBackForNonPositive() {
        let sketch = MinimalSketch()
        // フォールバック後も動作するワールドが返る（クラッシュ・不正状態にしない）
        let world = sketch.createPhysics2D(cellSize: 0)
        _ = world.addCircle(x: 0, y: 0, radius: 1)
        world.step(1.0 / 60.0)
        #expect(world.bodies.count == 1)
    }

    @Test("createPhysics2D accepts positive cellSize")
    func physicsAcceptsPositive() {
        let sketch = MinimalSketch()
        let world = sketch.createPhysics2D(cellSize: 50)
        #expect(world.bodies.isEmpty)
    }

    @Test("createSourcePass returns nil for non-positive dimensions")
    func sourcePassRejectsNonPositive() {
        // 検証は context アクセスの前に走るため GPU なしでテストできる
        let sketch = MinimalSketch()
        #expect(sketch.createSourcePass(label: "t", width: 0, height: 64) == nil)
        #expect(sketch.createSourcePass(label: "t", width: 64, height: -1) == nil)
    }

    @Test("createEffectPass returns nil for empty effects")
    func effectPassRejectsEmpty() throws {
        // effects の検証は input ノードや context に触れる前に走る。
        // ダミー入力ノードの生成には GPU が必要なため、GPU がある場合のみ実行する
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let sketch = MinimalSketch()
        let source = try SourcePass(label: "src", device: device, width: 8, height: 8)
        #expect(sketch.createEffectPass(source, effects: []) == nil)
    }
}
