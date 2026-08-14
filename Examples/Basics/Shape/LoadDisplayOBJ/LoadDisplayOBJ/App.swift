import metaphor
import Foundation

@main
final class LoadDisplayOBJ: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Load Display OBJ")
    }

    var rocket: Mesh?
    var ry: Float = 0

    func setup() {
        guard let path = Bundle.module.path(forResource: "rocket", ofType: "obj", inDirectory: "Resources") else { return }
        rocket = loadModel(path)
    }

    func draw() {
        background(0)
        lights()
        // loadModel() は既定でモデルを正規化する（原点中心・最大辺 2 単位）。原点がモデルの
        // 中心へ移るので、原典のように下へ寄せず画面中央へ置く。
        translate(width / 2, height / 2, -200)
        rotateZ(Float.pi)
        rotateY(ry)
        if let rocket = rocket {
            // 正規化されたモデルはそのまま描くと 2px にしかならない。画面の高さを基準に
            // 大きさを与える（最大辺が画面の高さの 60%）。
            scale(height * 0.3)
            mesh(rocket)
        } else {
            fill(200, 200, 220)
            box(60, 160, 60)
        }
        ry += 0.02
    }
}
