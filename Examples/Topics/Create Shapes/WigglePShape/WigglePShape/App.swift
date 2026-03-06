import metaphor

/// WigglePShape
///
/// How to move the individual vertices of an MShape using setVertex.
@main
final class WigglePShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "WigglePShape")
    }

    var s: MShape!
    var original: [SIMD2<Float>] = []
    var yoff: Float = 0

    func setup() {
        // The "original" locations of the vertices make up a circle
        var a: Float = 0
        while a < Float.pi * 2 {
            let v = SIMD2<Float>(cos(a) * 100, sin(a) * 100)
            original.append(v)
            a += 0.2
        }

        // Now make the MShape with those vertices
        s = createShape()
        s.beginShape()
        s.fill(127)
        s.stroke(.black)
        s.strokeWeight(2)
        for v in original {
            s.vertex(v.x, v.y)
        }
        s.endShape(.close)
    }

    func draw() {
        background(255)

        // Wiggle: apply noise offset to each vertex
        var xoff: Float = 0
        for i in 0..<s.vertexCount {
            let pos = original[i]
            let a = Float.pi * 2 * noise(xoff, yoff)
            let rx = cos(a) * 4 + pos.x
            let ry = sin(a) * 4 + pos.y
            s.setVertex(i, rx, ry)
            xoff += 0.5
        }
        yoff += 0.02

        // Display
        pushMatrix()
        translate(width / 2, height / 2)
        shape(s)
        popMatrix()
    }
}
