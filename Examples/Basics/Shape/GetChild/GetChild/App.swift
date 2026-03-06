import metaphor

/// GetChild
///
/// Demonstrates getChild() to access individual shapes within a group.
/// A group of named shapes is created, then individual children are
/// accessed and styled independently.
@main
final class GetChild: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "GetChild")
    }

    var group: MShape!

    func setup() {
        group = createShape(.group)

        // Create three named circle shapes
        let circle1 = createShape(.ellipse(x: -120, y: 0, width: 80, height: 80))
        circle1.name = "red"
        circle1.setFill(.red)
        circle1.setStroke(false)

        let circle2 = createShape(.ellipse(x: 0, y: 0, width: 80, height: 80))
        circle2.name = "green"
        circle2.setFill(.green)
        circle2.setStroke(false)

        let circle3 = createShape(.ellipse(x: 120, y: 0, width: 80, height: 80))
        circle3.name = "blue"
        circle3.setFill(.blue)
        circle3.setStroke(false)

        group.addChild(circle1)
        group.addChild(circle2)
        group.addChild(circle3)
    }

    func draw() {
        background(51)

        // Access children by name and modify their style dynamically
        let t = Float(frameCount) * 0.02

        if let red = group.getChild("red") {
            let brightness = (sin(t) + 1) / 2
            red.setFill(Color(r: brightness, g: 0, b: 0))
        }
        if let green = group.getChild("green") {
            let brightness = (sin(t + Float.pi * 2 / 3) + 1) / 2
            green.setFill(Color(r: 0, g: brightness, b: 0))
        }
        if let blue = group.getChild("blue") {
            let brightness = (sin(t + Float.pi * 4 / 3) + 1) / 2
            blue.setFill(Color(r: 0, g: 0, b: brightness))
        }

        // Also access by index
        let childCount = group.childCount
        fill(.white)
        textSize(14)
        text("Group has \(childCount) children", 20, 30)

        // Draw the group
        translate(width / 2, height / 2)
        shape(group)
    }
}
