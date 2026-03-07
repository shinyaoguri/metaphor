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
        translate(width / 2, height / 2 + 100, -200)
        rotateZ(Float.pi)
        rotateY(ry)
        if let rocket = rocket {
            mesh(rocket)
        } else {
            fill(200, 200, 220)
            box(60, 160, 60)
        }
        ry += 0.02
    }
}
