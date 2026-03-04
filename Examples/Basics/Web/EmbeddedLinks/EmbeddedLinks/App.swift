import metaphor
#if os(macOS)
import AppKit
#endif

@main
final class EmbeddedLinks: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Embedded Links")
    }

    var overButton = false

    func draw() {
        background(204)
        if overButton {
            fill(255)
        } else {
            noFill()
        }
        stroke(0)
        rect(105, 60, 75, 75)
        line(135, 105, 155, 85)
        line(140, 85, 155, 85)
        line(155, 85, 155, 100)

        fill(0)
        textAlign(.center, .center)
        textSize(12)
        text("Click to open\nprocessing.org", 142, 170)
    }

    func mousePressed() {
        if overButton {
            #if os(macOS)
            if let url = URL(string: "https://www.processing.org") {
                NSWorkspace.shared.open(url)
            }
            #endif
        }
    }

    func mouseMoved() {
        checkButtons()
    }

    func mouseDragged() {
        checkButtons()
    }

    func checkButtons() {
        overButton = mouseX > 105 && mouseX < 180 && mouseY > 60 && mouseY < 135
    }
}
