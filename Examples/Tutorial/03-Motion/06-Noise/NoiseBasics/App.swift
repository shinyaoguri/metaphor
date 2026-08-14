import metaphor

@main
final class NoiseBasics: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Noise Basics")
    }

    func setup() {
        noLoop()

        // 乱数と同じく、ノイズにも種がある。固定すれば同じ模様が出る
        noiseSeed(4)
        randomSeed(4)
    }

    func draw() {
        background(24)

        let left: Float = 40
        let right = width - 40
        let axis: Float = 108

        // 上段その 1: 乱数で折れ線を引く。隣り合う点に関係が無いので、
        // 毎回てっぺんから底まで飛ぶ
        noFill()
        strokeWeight(2)
        stroke(230, 90, 70)
        beginShape()
        var x = left
        while x <= right {
            vertex(x, axis - random(-42, 42))
            x += 8
        }
        endShape(.open)

        // 上段その 2: ノイズで折れ線を引く。noise() は 0〜1 を返し、
        // 近い座標には近い値を返すので、線がつながって見える
        stroke(110, 200, 160)
        beginShape()
        x = left
        while x <= right {
            vertex(x, axis - (noise(x * 0.012) - 0.5) * 84)
            x += 8
        }
        endShape(.open)

        // 下段: 2 次元のノイズを格子状にサンプルして明るさに使う。
        // 縦にも横にもつながっているので、雲のような模様になる
        noStroke()
        let cell: Float = 8
        var gy: Float = 190
        while gy < height {
            var gx: Float = 0
            while gx < width {
                fill(noise(gx * 0.012, gy * 0.012) * 255)
                rect(gx, gy, cell, cell)
                gx += cell
            }
            gy += cell
        }

        textSize(13)
        fill(230, 90, 70)
        text("random(-42, 42)", left, 42)
        fill(110, 200, 160)
        text("noise(x * 0.012)", left + 190, 42)
        fill(235)
        text("noise(x * 0.012, y * 0.012)", left, 180)
    }
}
