import metaphor

@main
final class Texture: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Texture")
    }

    var checker: MImage!

    func setup() {
        noLoop()

        // 画像はファイルから読むだけでなく、その場で作れる（第 2 部 2.9 と同じ手）
        let size = 128
        checker = createImage(size, size)
        checker.loadPixels()
        for y in 0..<size {
            for x in 0..<size {
                let index = (y * size + x) * 4
                let isLight = ((x / 16) + (y / 16)) % 2 == 0
                checker.pixels[index] = isLight ? 240 : 40            // R
                checker.pixels[index + 1] = isLight ? 190 : 90        // G
                checker.pixels[index + 2] = UInt8(60 + x)             // B は横方向のグラデーション
                checker.pixels[index + 3] = 255
            }
        }
        checker.updatePixels()
    }

    func draw() {
        background(16)
        lights()
        noStroke()

        // 組み込みプリミティブは UV を持っているので、texture() を呼ぶだけで貼れる
        push()
        translate(130, 150, 0)
        rotateX(-0.5)
        rotateY(0.7)
        texture(checker)
        box(130)
        pop()

        push()
        translate(330, 150, 0)
        rotateY(0.5)
        texture(checker)
        sphere(72)
        pop()

        // 自分で貼るときは頂点ごとに UV を渡す。(0,0) が画像の左上、(1,1) が右下
        push()
        translate(520, 150, 0)
        rotateY(-0.45)
        texture(checker)
        beginShape3D(.triangles)
        vertex(-75, -75, 0, 0, 0)
        vertex(75, -75, 0, 1, 0)
        vertex(75, 75, 0, 1, 1)
        vertex(-75, -75, 0, 0, 0)
        vertex(75, 75, 0, 1, 1)
        vertex(-75, 75, 0, 0, 1)
        endShape3D()
        pop()

        noTexture()
        fill(200)
        textSize(12)
        textAlign(.center)
        text("box に貼る", 130, 290)
        text("sphere に貼る", 330, 290)
        text("UV を自分で渡す", 520, 290)
    }
}
