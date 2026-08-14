import metaphor

@main
final class Mesh3D: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Mesh 3D")
    }

    // setup() で 1 度だけ作り、draw() で何度でも描くメッシュ
    var ring: Mesh!

    func setup() {
        noLoop()
        ring = createTorusMesh(ringRadius: 38, tubeRadius: 12)
    }

    func draw() {
        background(16)
        noStroke()
        ambientLight(60)
        directionalLight(0.35, 0.8, -0.5)

        // 左: 頂点を自分で並べて作った四角錐
        fill(235, 180, 90)
        push()
        translate(150, 185, 0)
        rotateX(-0.35)
        rotateY(0.7)
        pyramid(base: 150, height: 150)
        pop()

        // 右: 同じ Mesh を 3 回描く。位置と向きは現在の変換行列が決める
        fill(110, 190, 200)
        for i in 0..<3 {
            push()
            translate(380 + Float(i) * 100, 185, Float(i) * -50)
            rotateX(-0.85)
            rotateZ(Float(i) * 0.6)
            mesh(ring)
            pop()
        }

        fill(200)
        textSize(12)
        textAlign(.center)
        text("beginShape3D で組む", 150, 330)
        text("同じ Mesh を 3 回描く", 480, 330)
    }

    /// 四角錐を三角形で組む。底面は xz 平面、頂点は真上（y が負の向き）。
    private func pyramid(base: Float, height: Float) {
        let h = base / 2
        let apex = Vec3(0, -height / 2, 0)
        let corners = [
            Vec3(-h, height / 2, -h),
            Vec3(h, height / 2, -h),
            Vec3(h, height / 2, h),
            Vec3(-h, height / 2, h),
        ]

        // 頂点を回す向き（ワインディング）で法線の向きが決まる。逆に回すと
        // 法線が内側を向き、外から見た面が真っ暗になる
        beginShape3D(.triangles)
        for i in 0..<4 {
            triangle3D(apex, corners[i], corners[(i + 1) % 4])   // 側面
        }
        triangle3D(corners[0], corners[2], corners[1])           // 底面
        triangle3D(corners[0], corners[3], corners[2])
        endShape3D()
    }

    /// 3 頂点を、面の向き（法線）付きで送る。法線が無いと陰影が付かない。
    private func triangle3D(_ a: Vec3, _ b: Vec3, _ c: Vec3) {
        let n = normalize(cross(b - a, c - a))
        normal(n.x, n.y, n.z)
        vertex(a.x, a.y, a.z)
        vertex(b.x, b.y, b.z)
        vertex(c.x, c.y, c.z)
    }
}
