import metaphor

/// GroupPShape
///
/// How to group multiple MShapes into one MShape using .group.
@main
final class GroupPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "GroupPShape")
    }

    var group: MShape!

    func setup() {
        // Create the shape as a group
        group = createShape(.group)

        // Make a polygon MShape (star)
        let star = createShape()
        star.beginShape()
        star.noFill()
        star.stroke(.white)
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

        // Make a path MShape (random arc)
        let path = createShape()
        path.beginShape()
        path.noFill()
        path.stroke(.white)
        var a: Float = -.pi
        while a < 0 {
            let r = random(60, 70)
            path.vertex(r * cos(a), r * sin(a))
            a += 0.1
        }
        path.endShape()

        // Make a primitive (Rectangle) MShape
        let rectangle = createShape(.rect(x: -10, y: -10, width: 20, height: 20))
        rectangle.setFill(false)
        rectangle.setStroke(.white)

        // Add them all to the group
        group.addChild(star)
        group.addChild(path)
        group.addChild(rectangle)
    }

    func draw() {
        // We can access them individually via the group MShape
        let rectangle = group.getChild(2)
        // Shapes can be rotated
        rectangle?.rotate(0.1)

        background(52)
        // Display the group MShape
        translate(mouseX, mouseY)
        shape(group)
    }
}
