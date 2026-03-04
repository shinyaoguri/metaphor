import metaphor

struct Handle {
    var x: Float, y: Float
    var stretch: Float
    let size: Float = 10
    var locked = false
    var over = false
}

@main
final class Handles: Sketch {
    var config: SketchConfig { SketchConfig(title: "Handles", width: 640, height: 360) }

    var handles: [Handle] = []
    var firstPress = false

    func setup() {
        let num = Int(height) / 15
        for i in 0..<num {
            handles.append(Handle(x: width / 2, y: 10 + Float(i) * 15, stretch: 45))
        }
    }

    func draw() {
        background(153)
        let anyLocked = handles.contains { $0.locked }
        for i in 0..<handles.count {
            let boxx = handles[i].x + handles[i].stretch
            let boxy = handles[i].y - handles[i].size / 2
            if !anyLocked || handles[i].locked {
                handles[i].over = mouseX >= boxx && mouseX <= boxx + handles[i].size &&
                                  mouseY >= boxy && mouseY <= boxy + handles[i].size
                if (handles[i].over && firstPress) || handles[i].locked {
                    handles[i].locked = true
                }
            }
            if handles[i].locked {
                handles[i].stretch = max(0, min(mouseX - width / 2 - handles[i].size / 2, width / 2 - handles[i].size - 1))
            }
            // Draw
            stroke(0)
            line(handles[i].x, handles[i].y, handles[i].x + handles[i].stretch, handles[i].y)
            fill(255); stroke(0)
            rect(boxx, boxy, handles[i].size, handles[i].size)
            if handles[i].over || handles[i].locked {
                line(boxx, boxy, boxx + handles[i].size, boxy + handles[i].size)
                line(boxx, boxy + handles[i].size, boxx + handles[i].size, boxy)
            }
        }
        fill(0); noStroke()
        rect(0, 0, width / 2, height)
        if firstPress { firstPress = false }
    }

    func mousePressed() { firstPress = true }
    func mouseReleased() { for i in 0..<handles.count { handles[i].locked = false } }
}
