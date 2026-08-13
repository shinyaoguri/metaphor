import metaphor

@main
final class LongRunSketch: Sketch {
    /// 積み上がっていくもの。`Codable` にしておけば、そのまま state に載せられる
    struct Grain: Codable {
        var x: Float
        var y: Float
        var tone: Float
    }

    /// リロードをまたいで持ち越したいもの一式
    struct SavedState: Codable {
        var grains: [Grain]
        var reloads: Int
    }

    var config: SketchConfig {
        // frameCount と time もリロードをまたいで続ける
        SketchConfig(width: 640, height: 360, title: "LongRun", preserveClock: true)
    }

    /// 上限を決めておく。長く動かすものに「増え続ける入れもの」を置かない
    let maxGrains = 1200

    var grains: [Grain] = []
    /// 何回復元されたか。状態が本当に運ばれた証拠になる
    var reloads = 0

    // MARK: - 状態フック

    func saveState() -> Data? {
        encodeState(SavedState(grains: grains, reloads: reloads))
    }

    func restoreState(_ data: Data) {
        // 編集の途中で形が変わって decode に失敗したら、初期状態のまま続ける
        guard let state: SavedState = decodeState(data) else { return }
        grains = state.grains
        reloads = state.reloads + 1
    }

    // MARK: - スケッチ

    func setup() {
        randomSeed(5)
        // 右上に FPS・フレーム時間・GPU 時間が出る
        enablePerformanceHUD()
    }

    func draw() {
        background(12)
        addGrain()
        drawGrains()
        drawStatus()
    }

    /// 毎フレーム 1 粒だけ積む。上限に達したら古いものから捨てる
    private func addGrain() {
        // 落とす場所はゆっくり一周する。時間そのもので動かしているので、
        // リロードで time が戻ると積む場所も戻る（preserveClock で防ぐ）
        let angle = time * 1.1
        let radius = 50 + noise(time * 0.4) * 100
        grains.append(
            Grain(
                x: width / 2 + cos(angle) * radius + random(-6, 6),
                y: height / 2 + sin(angle) * radius * 0.7 + random(-6, 6),
                tone: random(1)
            )
        )
        if grains.count > maxGrains {
            grains.removeFirst(grains.count - maxGrains)
        }
    }

    private func drawGrains() {
        noStroke()
        for (index, grain) in grains.enumerated() {
            // 新しい粒ほど明るい
            let age = Float(index) / Float(max(grains.count, 1))
            fill(80 + grain.tone * 150, 140 + age * 90, 230 - grain.tone * 70, 40 + age * 200)
            circle(grain.x, grain.y, 3 + age * 3)
        }
    }

    private func drawStatus() {
        fill(235)
        textSize(13)
        textAlign(.left, .center)
        text("粒: \(grains.count) / \(maxGrains)", 18, height - 62)
        text("frameCount: \(frameCount)    time: \(String(format: "%.1f", time)) 秒", 18, height - 40)
        text("復元された回数: \(reloads)", 18, height - 18)
    }
}
