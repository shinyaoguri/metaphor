import metaphor

// Loading Tabular Data (by Daniel Shiffman)
// Load data from a CSV file using loadTable() and generate objects.
// Click to add bubbles, then save back to data/data.csv with saveTable() and reload.
// Run from the example directory with `swift run` (data/ is resolved relative to CWD).

@main
final class LoadSaveTable: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadSaveTable")
    }

    struct Bubble {
        var x: Float
        var y: Float
        var diameter: Float
        var name: String
        var over = false
    }

    var bubbles: [Bubble] = []
    var table = Table()

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
        // Load CSV file into a Table object (header row is on by default)
        do {
            table = try loadTable("data/data.csv")
        } catch {
            print("Failed to load data/data.csv: \(error)")
            return
        }
        // Access fields via their column name (or index)
        bubbles = table.rows.map { row in
            Bubble(
                x: row.getFloat("x"),
                y: row.getFloat("y"),
                diameter: row.getFloat("diameter"),
                name: row.getString("name"))
        }
    }

    func mousePressed() {
        // Create a new row and set its values
        let row = table.addRow()
        row.setFloat("x", mouseX)
        row.setFloat("y", mouseY)
        row.setFloat("diameter", random(40, 80))
        row.setString("name", "Blah")

        // If the table has more than 10 rows, delete the oldest
        if table.rowCount > 10 {
            table.removeRow(0)
        }

        // Write the CSV back to the same file and reload
        do {
            try saveTable(table, "data/data.csv")
        } catch {
            print("Failed to save data/data.csv: \(error)")
        }
        loadData()
    }
}
