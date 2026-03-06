import metaphor

/// PolygonPShapeOOP3
///
/// Multiple objects with different shape types (ellipse, rect, custom polygon).
/// Each object is randomly assigned one of three shapes.

struct Polygon {
    var s: MShape
    var x: Float
    var y: Float
    var speed: Float
}

@main
final class PolygonPShapeOOP3: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PolygonPShapeOOP3")
    }

    var polygons: [Polygon] = []

    func setup() {
        // Three possible shapes
        let circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 100))
        circle.setFill(Color(gray: 1.0, alpha: 127.0 / 255.0))
        circle.setStroke(false)

        let rect = createShape(.rect(x: 0, y: 0, width: 100, height: 100))
        rect.setFill(Color(gray: 1.0, alpha: 127.0 / 255.0))
        rect.setStroke(false)

        let star = createShape()
        star.beginShape()
        star.fill(Color(gray: 0, alpha: 127.0 / 255.0))
        star.noStroke()
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

        let shapes = [circle, rect, star]

        // Create 25 polygons with random shape selection
        for _ in 0..<25 {
            let selection = Int(random(Float(shapes.count)))
            polygons.append(Polygon(
                s: shapes[selection],
                x: random(width),
                y: random(-500, -100),
                speed: random(2, 6)
            ))
        }
    }

    func draw() {
        background(102)

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
