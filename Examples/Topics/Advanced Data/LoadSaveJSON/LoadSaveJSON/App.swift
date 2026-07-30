import metaphor

// Loading JSON Data (by Daniel Shiffman)
// Load data from a JSON file using loadJSON() and generate objects.
// Click to add bubbles, then save back to data/data.json with saveJSON() and reload.
// Run from the example directory with `swift run` (data/ is resolved relative to CWD).

@main
final class LoadSaveJSON: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadSaveJSON")
    }

    struct Bubble {
        var x: Float
        var y: Float
        var diameter: Float
        var name: String
        var over = false
    }

    var bubbles: [Bubble] = []
    var json: JSONValue = [:]

    func setup() {
        loadData()
    }

    func draw() {
        background(255)
        // Display all bubbles
        for i in bubbles.indices {
            bubbles[i].over = dist(mouseX, mouseY, bubbles[i].x, bubbles[i].y) < bubbles[i].diameter / 2
            display(bubbles[i])
        }
        textAlign(.left)
        fill(0)
        text("Click to add bubbles.", 10, height - 10)
    }

    func display(_ b: Bubble) {
        stroke(0)
        strokeWeight(2)
        noFill()
        ellipse(b.x, b.y, b.diameter, b.diameter)
        if b.over {
            fill(0)
            textAlign(.center)
            text(b.name, b.x, b.y + b.diameter / 2 + 20)
        }
    }

    func loadData() {
        do {
            json = try loadJSON("data/data.json")
        } catch {
            print("Failed to load data/data.json: \(error)")
            return
        }
        // Make Bubble objects out of the JSON data
        bubbles = json["bubbles"].arrayValue.map { bubble in
            Bubble(
                x: bubble["position"]["x"].floatValue,
                y: bubble["position"]["y"].floatValue,
                diameter: bubble["diameter"].floatValue,
                name: bubble["label"].stringValue)
        }
    }

    func mousePressed() {
        // Create a new JSON bubble object and append it to the array
        let newBubble: JSONValue = [
            "position": ["x": JSONValue(mouseX), "y": JSONValue(mouseY)],
            "diameter": JSONValue(random(40, 80)),
            "label": "New label",
        ]
        json["bubbles"].append(newBubble)

        if json["bubbles"].count > 10 {
            json["bubbles"].remove(at: 0)
        }

        // Save new data and reload
        do {
            try saveJSON(json, "data/data.json")
        } catch {
            print("Failed to save data/data.json: \(error)")
        }
        loadData()
    }
}
