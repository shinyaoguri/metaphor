import metaphor

@main final class RecursiveTree: Sketch {
    var config: SketchConfig { SketchConfig(title: "Recursive Tree") }

    private let maxDepth = 10

    func draw() {
        background(Color(gray: 0.08))

        push()

        // Start from bottom center
        translate(width / 2, height * 0.92)

        // Draw trunk and branches
        let trunkLength: Float = height * 0.18
        strokeWeight(8)
        stroke(Color(r: 0.45, g: 0.3, b: 0.15))
        branch(length: trunkLength, depth: 0, maxDepth: maxDepth)

        pop()
    }

    private func branch(length: Float, depth: Int, maxDepth: Int) {
        // Interpolate color from brown trunk to green leaves
        let t = Float(depth) / Float(maxDepth)
        let trunkColor = Color(r: 0.45, g: 0.3, b: 0.15)
        let leafColor = Color(r: 0.15, g: 0.75, b: 0.3)
        let branchColor = trunkColor.lerp(to: leafColor, t: t)
        stroke(branchColor)

        // Thickness decreases with depth
        let thickness = lerp(8.0, 1.0, t)
        strokeWeight(thickness)

        // Draw the branch line upward
        line(0, 0, 0, -length)
        translate(0, -length)

        if depth < maxDepth {
            let baseAngle: Float = Float.pi / 6
            let animatedAngle = baseAngle + sin(time * 0.5 + Float(depth) * 0.3) * 0.15

            // Right branch
            push()
            rotate(animatedAngle)
            branch(length: length * 0.67, depth: depth + 1, maxDepth: maxDepth)
            pop()

            // Left branch
            push()
            rotate(-animatedAngle)
            branch(length: length * 0.67, depth: depth + 1, maxDepth: maxDepth)
            pop()
        } else {
            // Draw small leaf circles at tips
            noStroke()
            let leafHue = 0.25 + sin(time + Float(depth)) * 0.08
            fill(Color(hue: leafHue, saturation: 0.8, brightness: 0.8, alpha: 0.7))
            circle(0, 0, 4)
        }
    }
}
