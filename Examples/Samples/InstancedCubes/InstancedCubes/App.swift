// InstancedCubes
//
// drawInstanced(mesh, transforms:) で同じメッシュを一括描画するサンプル。
// 40 × 40 = 1,600 本の柱を、1 回の呼び出し（＝1 draw call）で描いています。
//
//   drawInstanced(cube, transforms: transforms, colors: colors)
//
// は次のループと同じ絵になりますが、インスタンスごとの状態評価がなくなるぶん CPU が軽くなります。
//
//   for (t, c) in zip(transforms, colors) {
//       fill(c); pushMatrix(); applyMatrix(t); mesh(cube); popMatrix()
//   }
//
// transforms は「現在の変換行列に対するローカル変換」なので、呼び出し前の translate /
// rotate がそのまま全インスタンスに効きます（下では画面中央へ移動し、見下ろしてから呼んでいます）。

import metaphor

@main
final class InstancedCubes: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 900, height: 700, title: "InstancedCubes")
    }

    // 柱のフィールド（インスタンス数は cols * rows）
    let cols = 40
    let rows = 40
    let spacing: Float = 17
    let unit: Float = 12          // 立方体メッシュの一辺（高さはスケールで伸ばす）

    var cube: Mesh!

    func setup() {
        // createBoxMesh は box() と同じジオメトリを「値としての Mesh」で返します
        // （sphere / plane / cylinder / cone / torus も同様。ファイルから読むなら loadModel(path)）
        guard let mesh = createBoxMesh(unit) else {
            fatalError("キューブメッシュを作れませんでした")
        }
        cube = mesh
        noStroke()
    }

    func draw() {
        background(10, 12, 18)
        ambientLight(70)
        directionalLight(-0.4, 0.9, -0.35)

        let t = Float(frameCount) * 0.02
        var transforms: [float4x4] = []
        var colors: [Color] = []
        transforms.reserveCapacity(cols * rows)
        colors.reserveCapacity(cols * rows)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = (Float(col) - Float(cols - 1) / 2) * spacing
                let z = (Float(row) - Float(rows - 1) / 2) * spacing
                let d = sqrt(x * x + z * z) * 0.02

                // 中心から広がる波。柱の高さ（Y スケール）と色を同じ値から作る
                let wave = sin(d * 1.2 - t * 2.2) * 0.5 + 0.5    // 0…1
                let height = 1 + wave * 11

                // 立方体を縦に伸ばし、底面を地面に揃えてから格子点へ移動する
                transforms.append(
                    float4x4(translation: SIMD3(x, -unit * height / 2, z))
                    * float4x4(scale: SIMD3(1, height, 1))
                )
                colors.append(Color(r: 0.2 + wave * 0.8, g: 0.35, b: 1 - wave * 0.6))
            }
        }

        // 現在の変換行列（＝この translate / rotate）が全インスタンスに効く
        translate(width / 2, height * 0.56, -430)
        rotateX(-0.95)
        rotateY(t * 0.15)
        drawInstanced(cube, transforms: transforms, colors: colors)
    }
}
