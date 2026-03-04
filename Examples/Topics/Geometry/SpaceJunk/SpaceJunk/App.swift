import metaphor

struct JunkCube {
    var w: Float
    var h: Float
    var d: Float
    var shiftX: Float
    var shiftY: Float
    var shiftZ: Float
}

@main
final class SpaceJunk: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "SpaceJunk", width: 640, height: 360)
    }

    let limit = 500
    var cubes: [JunkCube] = []
    var angle: Float = 0

    func setup() {
        noStroke()
        for _ in 0..<limit {
            cubes.append(JunkCube(
                w: Float(Int.random(in: -10...10)),
                h: Float(Int.random(in: -10...10)),
                d: Float(Int.random(in: -10...10)),
                shiftX: Float(Int.random(in: -140...140)),
                shiftY: Float(Int.random(in: -140...140)),
                shiftZ: Float(Int.random(in: -140...140))
            ))
        }
    }

    func draw() {
        background(0)
        fill(200)

        pointLight(51, 102, 255, 65, 60, 100)
        pointLight(200, 40, 60, -65, -60, -150)
        ambientLight(70, 70, 10)

        translate(width / 2, height / 2, -200 + mouseX * 0.65)
        rotateY(radians(angle))
        rotateX(radians(angle))

        for i in 0..<cubes.count {
            pushMatrix()
            translate(cubes[i].shiftX, cubes[i].shiftY, cubes[i].shiftZ)
            box(max(abs(cubes[i].w), 2), max(abs(cubes[i].h), 2), max(abs(cubes[i].d), 2))
            popMatrix()
        }

        angle += 0.2
    }
}
