// Based on Processing's MultipleWindows example by GeneKao
// Two windows with independent 3D orbit cameras, cross-window state sharing

import metaphor

@main
final class MultipleWindows: Sketch {
    var child: SketchWindow?
    var mousePressedOnParent = false

    var config: SketchConfig {
        SketchConfig(width: 320, height: 240, title: "Main sketch")
    }

    func setup() {
        child = createWindow(SketchWindowConfig(
            width: 400, height: 400, title: "Child sketch"
        ))
    }

    func draw() {
        background(250)
        orbitControl()

        // 3D box — color changes when mouse is pressed
        lights()
        if isMousePressed {
            mousePressedOnParent = true
            fill(0, 240, 0)
        } else {
            mousePressedOnParent = false
            fill(200, 200, 255)
        }
        box(100)

        // HUD text (drawn in 2D after 3D)
        noLights()
        if isMousePressed {
            fill(0)
            textSize(12)
            text("Mouse pressed on parent.", 10, 16)
        }
        if child?.input.isMouseDown == true {
            fill(0)
            textSize(12)
            text("Mouse pressed on child.", 10, 32)
        }

        // Draw child window
        child?.draw { [self] ctx in
            ctx.background(0)
            ctx.orbitControl()

            // 3D box — color changes when mouse is pressed
            ctx.lights()
            if ctx.input.isMouseDown {
                ctx.fill(240, 0, 0)
            } else {
                ctx.fill(255, 200, 200)
            }
            ctx.box(100, 200, 100)

            // HUD text
            ctx.noLights()
            ctx.fill(255)
            ctx.textSize(12)
            if ctx.input.isMouseDown {
                ctx.text("Mouse pressed on child.", 10, 20)
            }
            if mousePressedOnParent {
                ctx.text("Mouse pressed on parent.", 10, 36)
            }
        }
    }
}
