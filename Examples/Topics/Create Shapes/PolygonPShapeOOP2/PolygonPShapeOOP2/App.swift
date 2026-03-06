import metaphor

/// PolygonPShapeOOP2
///
/// Multiple objects sharing the same MShape.
/// Demonstrates resource efficiency: one shape definition, many instances.

struct Polygon {
    var s: MShape
    var x: Float
    var y: Float
    var speed: Float
}

@main
final class PolygonPShapeOOP2: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PolygonPShapeOOP2")
    }

    var polygons: [Polygon] = []

    func setup() {
        // Make a single MShape (star)
        let star = createShape()
        star.beginShape()
        star.noStroke()
        star.fill(Color(gray: 0, alpha: 127.0 / 255.0))
        star.vertex(0, -50)
        star.vertex(14, -20)
        star.vertex(47, -15)
        star.vertex(23, 7)
        star.vertex(29, 40)
        star.vertex(0, 25)
        star.vertex(-29, 40)
        star.vertex(-23, 7)
        star.vertex(-47, -15)
        star.vertex(-14, -20)
        star.endShape(.close)

        // Create 25 polygons all sharing the same MShape
        for _ in 0..<25 {
            polygons.append(Polygon(
                s: star,
                x: random(width),
                y: random(-500, -100),
                speed: random(2, 6)
            ))
        }
    }

    func draw() {
        background(255)

        for i in 0..<polygons.count {
            // Display
            pushMatrix()
            translate(polygons[i].x, polygons[i].y)
            shape(polygons[i].s)
            popMatrix()

            // Move
            polygons[i].y += polygons[i].speed
            if polygons[i].y > height + 100 {
                polygons[i].y = -100
            }
        }
    }
}
