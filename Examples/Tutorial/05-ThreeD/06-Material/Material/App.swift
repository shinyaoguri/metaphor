import metaphor

@main
final class Material: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Material")
    }

    let roughnessValues: [Float] = [0.05, 0.25, 0.5, 0.75, 1.0]

    func setup() {
        noLoop()
    }

    func draw() {
        background(14)
        noStroke()

        ambientLight(70)
        directionalLight(0.4, 0.85, -0.35)
        directionalLight(-0.6, -0.3, -0.5, color: Color(r: 0.45, g: 0.5, b: 0.6))
        pointLight(320, 20, 340, color: .white, falloff: 0.0015)

        fill(240, 220, 195)

        // 上の段は非金属（metallic 0）、下の段は金属（metallic 1）。
        // 列ごとに roughness だけを変える
        for (row, metal) in [Float(0), 1].enumerated() {
            for (col, rough) in roughnessValues.enumerated() {
                push()
                translate(110 + Float(col) * 115, 140 + Float(row) * 112, 0)
                metallic(metal)
                roughness(rough)      // roughness を呼ぶと PBR モードに切り替わる
                sphere(42)
                pop()
            }
        }

        fill(200)
        textSize(12)
        textAlign(.center)
        for (col, rough) in roughnessValues.enumerated() {
            text("roughness \(rough)", 110 + Float(col) * 115, 46)
        }
        textAlign(.left)
        text("metallic 0", 8, 144)
        text("metallic 1", 8, 256)
    }
}
