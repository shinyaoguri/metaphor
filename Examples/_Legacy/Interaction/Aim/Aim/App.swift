import metaphor

@main
final class AimExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Aim")
    }

    func draw() {
        background(Color.black)

        let cx = width / 2
        let cy = height / 2
        let eyeSize = min(width, height) * 0.12
        let pupilSize = eyeSize * 0.5
        let pupilOffset = eyeSize * 0.25
        let gap = eyeSize * 1.2

        // Draw left eye
        let leftX = cx - gap
        let leftY = cy
        let leftAngle = atan2(input.mouseY - leftY, input.mouseX - leftX)

        push()
        translate(leftX, leftY)
        fill(Color.white)
        ellipse(0, 0, eyeSize, eyeSize)
        rotate(leftAngle)
        fill(Color.black)
        ellipse(pupilOffset, 0, pupilSize, pupilSize)
        pop()

        // Draw right eye
        let rightX = cx + gap
        let rightY = cy
        let rightAngle = atan2(input.mouseY - rightY, input.mouseX - rightX)

        push()
        translate(rightX, rightY)
        fill(Color.white)
        ellipse(0, 0, eyeSize, eyeSize)
        rotate(rightAngle)
        fill(Color.black)
        ellipse(pupilOffset, 0, pupilSize, pupilSize)
        pop()
    }
}
