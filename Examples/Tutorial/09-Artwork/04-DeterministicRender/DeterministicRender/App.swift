import metaphor

@main
final class DeterministicRenderSketch: Sketch {
    var config: SketchConfig {
        // 描く大きさは 1920×1080 のまま、窓だけ小さく開く。
        // 焼き出す解像度と、作業中に見る大きさは別のもの
        SketchConfig(width: 1920, height: 1080, title: "DeterministicRender", windowScale: 0.4)
    }

    let outputDirectory = "output/render"
    let bakeFrames = 120

    /// 絵を決めるただ一つの数。時刻ではなくこれで動かすから、同じ番号なら同じ絵になる
    var artFrame = 0
    var isBaking = false
    var status = ""

    func setup() {
        // 種を固定する。これを忘れると、焼き直すたびに違う作品が出てくる
        randomSeed(2024)
        noiseSeed(2024)
        status = "B: \(bakeFrames) フレームを焼き出す"
    }

    func draw() {
        // 予定の枚数に届いたら、この絵を描く前に記録を閉じる。
        // 閉じたあとのフレームは書き出されない
        if isBaking && artFrame >= bakeFrames {
            finishBake()
        }

        drawArt(frame: artFrame)
        artFrame += 1

        // 焼き出し中は案内を描かない。画面のための描画を作品に混ぜない
        if !isBaking {
            drawStatusBar()
        }
    }

    func keyPressed() {
        if (key == "b" || key == "B") && !isBaking {
            startBake()
        }
    }

    private func startBake() {
        // 0 フレーム目から焼く。途中から始めると同じ動きにならない
        artFrame = 0
        isBaking = true
        // 実時間から切り離す。time は frameCount / fps、deltaTime は 1/fps に固定され、
        // 1 枚に何秒かかっても出来上がりの時間軸は変わらない
        beginOfflineRender(fps: 60)
        beginFrameRecord(directory: outputDirectory, pattern: "frame_%04d.png")
        status = "焼き出し中…"
    }

    private func finishBake() {
        endFrameRecord()
        endOfflineRender()
        isBaking = false
        status = "\(outputDirectory) に \(bakeFrames) 枚 書き出しました"
        print("ffmpeg -framerate 60 -i \(outputDirectory)/frame_%04d.png -c:v libx264 -pix_fmt yuv420p -crf 16 output/render.mp4")
    }

    /// フレーム番号だけを入力にして絵を決める。引数以外に外の状態を見ない
    private func drawArt(frame: Int) {
        background(9, 10, 14)

        let phase = Float(frame) * 0.008
        push()
        translate(width / 2, height / 2)
        noFill()

        for ring in 0..<44 {
            let k = Float(ring) / 44
            push()
            rotate(phase * (1 + k * 2.2) + k * TWO_PI * 0.18)
            stroke(90 + k * 150, 190 - k * 60, 255 - k * 90, 180)
            strokeWeight(1 + k * 2.5)
            // noise も種で決まる。noiseSeed を変えれば別の作品になる
            let wobble = (noise(k * 5, phase) - 0.5) * 90
            polygon(sides: 6, radius: 70 + k * 430, wobble: wobble)
            pop()
        }

        pop()
    }

    private func polygon(sides: Int, radius: Float, wobble: Float) {
        beginShape()
        for index in 0..<sides {
            let angle = Float(index) / Float(sides) * TWO_PI
            let r = radius + sin(angle * 3) * wobble
            vertex(cos(angle) * r, sin(angle) * r)
        }
        endShape(.close)
    }

    private func drawStatusBar() {
        noStroke()
        fill(0, 0, 0, 180)
        rect(0, height - 64, width, 64)
        fill(235)
        textSize(24)
        textAlign(.left, .center)
        text(status, 32, height - 32)
    }
}
