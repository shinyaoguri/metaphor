import metaphor

struct InnerCube {
    var px: Float = 0, py: Float = 0, pz: Float = 0
    var vx: Float, vy: Float, vz: Float
    var rx: Float, ry: Float, rz: Float
    var size: Float
    var gray: Float
}

@main
final class CubesWithinCube: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Cubes Within Cube")
    }

    var cubies: [InnerCube] = []
    let bounds: Float = 300

    func setup() {
        for _ in 0..<20 {
            let s = Float.random(in: 5...15)
            let a1 = Float.random(in: 0..<Float.pi * 2)
            let a2 = Float.random(in: 0..<Float.pi * 2)
            cubies.append(InnerCube(
                vx: sin(a1) * cos(a2), vy: sin(a1) * sin(a2), vz: cos(a1),
                rx: Float.random(in: 40...100), ry: Float.random(in: 40...100),
                rz: Float.random(in: 40...100), size: s,
                gray: Float.random(in: 50...200)
            ))
        }
    }

    func draw() {
        background(50)
        lights()
        translate(width / 2, height / 2, -130)
        rotateX(Float(frameCount) * 0.001)
        rotateY(Float(frameCount) * 0.002)
        rotateZ(Float(frameCount) * 0.001)
        stroke(255)
        noFill()
        box(bounds, bounds, bounds)
        for i in 0..<cubies.count {
            cubies[i].px += cubies[i].vx
            cubies[i].py += cubies[i].vy
            cubies[i].pz += cubies[i].vz
            if cubies[i].px > bounds / 2 || cubies[i].px < -bounds / 2 { cubies[i].vx *= -1 }
            if cubies[i].py > bounds / 2 || cubies[i].py < -bounds / 2 { cubies[i].vy *= -1 }
            if cubies[i].pz > bounds / 2 || cubies[i].pz < -bounds / 2 { cubies[i].vz *= -1 }
            pushMatrix()
            translate(cubies[i].px, cubies[i].py, cubies[i].pz)
            rotateX(Float(frameCount) * Float.pi / cubies[i].rx)
            rotateY(Float(frameCount) * Float.pi / cubies[i].ry)
            rotateZ(Float(frameCount) * Float.pi / cubies[i].rz)
            noStroke()
            fill(cubies[i].gray)
            box(cubies[i].size, cubies[i].size, cubies[i].size)
            popMatrix()
        }
    }
}
