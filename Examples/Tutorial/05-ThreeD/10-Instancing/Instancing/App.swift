import metaphor

@main
final class Instancing: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Instancing")
    }

    let cubeCount = 4000
    let radius: Float = 135

    var cube: Mesh!
    var transforms: [float4x4] = []
    var colors: [Color] = []

    func setup() {
        noLoop()
        noStroke()

        // 描くたびに作り直さない。メッシュも配置も setup() で 1 度だけ用意する
        cube = createBoxMesh(7)

        transforms.reserveCapacity(cubeCount)
        colors.reserveCapacity(cubeCount)

        // 球面上に均等に撒く（黄金角を使うフィボナッチ球）
        let golden = PI * (3 - sqrt(5))
        for i in 0..<cubeCount {
            let t = Float(i) / Float(cubeCount - 1)
            let y = 1 - t * 2                      // 上から下へ -1…1
            let r = sqrt(max(0, 1 - y * y))
            let angle = golden * Float(i)
            let position = Vec3(cos(angle) * r, y, sin(angle) * r) * radius

            transforms.append(
                float4x4(translation: position)
                * float4x4(scale: Vec3(repeating: 0.6 + r * 0.9))
            )
            colors.append(Color(hue: 0.55 - t * 0.35, saturation: 0.75, brightness: 1))
        }
    }

    func draw() {
        background(12)
        ambientLight(70)
        directionalLight(0.3, 0.9, -0.35)

        // 呼び出し前の変換が全インスタンスに効く
        push()
        translate(width / 2, height / 2, -60)
        rotateY(0.6)
        rotateX(-0.35)
        drawInstanced(cube, transforms: transforms, colors: colors)
        pop()

        fill(200)
        textSize(12)
        text("\(cubeCount) 個の立方体を drawInstanced() の 1 回で描く", 22, 336)
    }
}
