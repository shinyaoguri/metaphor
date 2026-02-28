import metaphor

@main final class Geometries: Sketch {
    var config: SketchConfig { SketchConfig(title: "Geometries") }

    func draw() {
        background(Color(gray: 0.05))

        lights()

        // Camera setup
        camera(
            eye: SIMD3<Float>(0, 0, 600),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        perspective(fov: radians(60), near: 1, far: 2000)

        // 6 shapes in a 3x2 grid
        let spacingX: Float = 280
        let spacingY: Float = 250
        let startX: Float = -spacingX
        let startY: Float = spacingY * 0.5

        let shapes: [(String, Float, Float)] = [
            ("box",      startX,              startY),
            ("sphere",   startX + spacingX,   startY),
            ("plane",    startX + spacingX*2,  startY),
            ("cylinder", startX,              startY - spacingY),
            ("cone",     startX + spacingX,   startY - spacingY),
            ("torus",    startX + spacingX*2,  startY - spacingY),
        ]

        for (index, shape) in shapes.enumerated() {
            let (name, x, y) = shape
            let hue = Float(index) / Float(shapes.count)
            let color = Color(hue: hue, saturation: 0.7, brightness: 0.9)

            fill(color)
            stroke(color.lerp(to: Color.white, t: 0.3))
            strokeWeight(0.5)

            pushMatrix()
            translate(x, y, 0)

            // Each shape rotates at a slightly different speed
            let rotSpeed = 0.4 + Float(index) * 0.1
            rotateY(time * rotSpeed)
            rotateX(time * rotSpeed * 0.3)

            let size: Float = 80

            switch name {
            case "box":
                box(size)
            case "sphere":
                sphere(size * 0.55, detail: 32)
            case "plane":
                plane(size * 1.2, size * 1.2)
            case "cylinder":
                cylinder(radius: size * 0.4, height: size * 1.0, detail: 32)
            case "cone":
                cone(radius: size * 0.45, height: size * 1.0, detail: 32)
            case "torus":
                torus(ringRadius: size * 0.4, tubeRadius: size * 0.15, detail: 32)
            default:
                break
            }

            popMatrix()
        }
    }
}
