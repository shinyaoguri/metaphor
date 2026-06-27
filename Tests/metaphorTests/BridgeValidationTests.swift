import Testing
@testable import metaphor
@testable import MetaphorCore

/// 検証付きブリッジ（`make*` バリアント）が不正な引数で `MetaphorError.invalidParameter`
/// を投げ、正しい引数では成功することを確認する。検証は context に触れないため、
/// GPU を必要としない最小の Sketch で実行できる。
@Suite("Bridge validation variants")
@MainActor
struct BridgeValidationTests {

    final class MinimalSketch: Sketch {
        var config = SketchConfig()
        init() {}
        func setup() {}
        func draw() {}
    }

    @Test("makeAudioInput rejects non power-of-two fftSize")
    func audioRejectsNonPowerOfTwo() {
        let sketch = MinimalSketch()
        #expect(throws: MetaphorError.self) {
            _ = try sketch.makeAudioInput(fftSize: 1000)
        }
    }

    @Test("makeAudioInput accepts power-of-two fftSize")
    func audioAcceptsPowerOfTwo() throws {
        let sketch = MinimalSketch()
        _ = try sketch.makeAudioInput(fftSize: 1024)
    }

    @Test("makePhysics2D rejects non-positive cellSize")
    func physicsRejectsNonPositive() {
        let sketch = MinimalSketch()
        #expect(throws: MetaphorError.self) {
            _ = try sketch.makePhysics2D(cellSize: 0)
        }
    }

    @Test("makePhysics2D accepts positive cellSize")
    func physicsAcceptsPositive() throws {
        let sketch = MinimalSketch()
        _ = try sketch.makePhysics2D(cellSize: 50)
    }
}
