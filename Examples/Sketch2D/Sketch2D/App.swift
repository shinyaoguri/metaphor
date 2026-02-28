import metaphor

@main
final class Sketch2D: Sketch {
    var config: SketchConfig {
        SketchConfig(
            title: "Sketch2D",
            syphonName: "Sketch2D"
        )
    }

    func draw() {
        // 背景（少し透明にしてトレイル効果）
        background(Color(gray: 0.05, alpha: 0.15))

        let t = time
        let cx = width * 0.5
        let cy = height * 0.5

        // 回転する円のリング
        let ringCount = 12
        let ringRadius: Float = 250
        noStroke()

        for i in 0..<ringCount {
            let angle = Float(i) / Float(ringCount) * Float.pi * 2 + t * 0.5
            let x = cx + cos(angle) * ringRadius
            let y = cy + sin(angle) * ringRadius

            let hue = (Float(i) / Float(ringCount) + t * 0.05)
                .truncatingRemainder(dividingBy: 1.0)
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.8))
            circle(x, y, 60)
        }

        // 中央の脈動する円
        let pulseSize = 100 + sin(t * 2) * 40
        fill(Color(gray: 1.0, alpha: 0.3))
        circle(cx, cy, pulseSize)

        // ノイズで動く小さな点
        strokeWeight(3)
        noFill()
        for i in 0..<200 {
            let fi = Float(i)
            let nx = noise(fi * 0.02, t * 0.3) * width
            let ny = noise(fi * 0.02 + 100, t * 0.3) * height
            let hue = noise(fi * 0.01, t * 0.1)
            stroke(Color(hue: hue, saturation: 0.6, brightness: 1.0, alpha: 0.5))
            point(nx, ny)
        }

        // Transform stackのデモ: 回転する三角形
        push()
        translate(cx, cy)
        rotate(t * 0.3)
        noFill()
        stroke(Color(gray: 1.0, alpha: 0.4))
        strokeWeight(2)
        let triSize: Float = 180
        triangle(
            0, -triSize,
            -triSize * 0.866, triSize * 0.5,
            triSize * 0.866, triSize * 0.5
        )
        pop()

        // ベジェ曲線
        noFill()
        stroke(Color(hue: 0.5, saturation: 0.7, brightness: 1.0, alpha: 0.6))
        strokeWeight(2)
        let bx = sin(t * 0.7) * 300
        bezier(
            200, cy,
            200 + bx, cy - 300,
            width - 200 - bx, cy + 300,
            width - 200, cy
        )
    }

    func mousePressed() {
        print("click: \(input.mouseX), \(input.mouseY)")
    }
}
