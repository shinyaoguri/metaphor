import metaphor

/// ShapeVertices
///
/// Demonstrates getVertex() and vertexCount on an MShape.
/// A polygon shape is created, then its vertices are visualized as dots.
@main
final class ShapeVertices: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ShapeVertices")
    }

    var polygon: MShape!

    func setup() {
        // Create a polygon with many vertices (a rounded shape)
        polygon = createShape()
        polygon.beginShape()
        polygon.fill(50)
        polygon.stroke(100)
        polygon.strokeWeight(1)
        for i in 0..<36 {
            let angle = Float(i) * Float.pi * 2 / 36
            let r: Float = 100 + sin(Float(i) * 0.8) * 30
            polygon.vertex(cos(angle) * r, sin(angle) * r)
        }
        polygon.endShape(.close)
    }

    func draw() {
        background(0)

        // Draw the shape
        pushMatrix()
        translate(width / 2, height / 2)
        shape(polygon)

        // Iterate through vertices and draw colored dots
        noStroke()
        for i in 0..<polygon.vertexCount {
            if let v = polygon.getVertex(i) {
                // Cycle through colors based on vertex index
                let hue = Float(i) / Float(polygon.vertexCount)
                fill(hue * 255, 200, 255)
                circle(v.x, v.y, 8)
            }
        }
        popMatrix()

        // Display vertex count
        fill(.white)
        textSize(14)
        text("Vertex count: \(polygon.vertexCount)", 20, 30)
    }
}
