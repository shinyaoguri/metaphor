import metaphor

@main
final class DrawControl: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Draw Control")
    }

    var y: Float = 0
    var isRunning = true

    func setup() {
        // 1 秒あたりの描画回数。既定の 60 より遅くすると、線の動きが目で追える
        frameRate(30)
        y = height * 0.5
    }

    func draw() {
        background(24)
        stroke(255)
        strokeWeight(2)
        line(0, y, width, y)

        y -= 4
        if y < 0 { y = height }
    }

    // クリックで連続描画の停止 / 再開を切り替える
    func mousePressed() {
        isRunning.toggle()
        if isRunning {
            loop()
        } else {
            noLoop()
        }
    }

    // 止めている間は、キーを押すたびに 1 フレームだけ進む
    func keyPressed() {
        if !isRunning {
            redraw()
        }
    }
}
