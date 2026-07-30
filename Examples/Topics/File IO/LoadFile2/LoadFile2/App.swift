import metaphor

// LoadFile 2
// Load tab-separated car data (400+ vehicles) with loadStrings(),
// convert each line to a Record struct, and display them.
// Click to advance to the next set of entries.
// Original used VLW font (loadFont); here we use the system font.
// Run from the example directory with `swift run` (data/ is resolved relative to CWD).

@main
final class LoadFile2: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadFile2")
    }

    struct Record {
        var name: String
        var mpg: Float
        var cylinders: Int
        var displacement: Float
        var horsepower: Float
        var weight: Float
        var acceleration: Float
        var year: Int
        var origin: Float

        init?(pieces: [String]) {
            guard pieces.count == 9 else { return nil }
            name = pieces[0]
            mpg = Float(pieces[1]) ?? 0
            cylinders = Int(pieces[2]) ?? 0
            displacement = Float(pieces[3]) ?? 0
            horsepower = Float(pieces[4]) ?? 0
            weight = Float(pieces[5]) ?? 0
            acceleration = Float(pieces[6]) ?? 0
            year = Int(pieces[7]) ?? 0
            origin = Float(pieces[8]) ?? 0
        }
    }

    var records: [Record] = []
    let num = 9  // Display this many entries on each screen
    var startingEntry = 0  // Display from this entry number

    func setup() {
        noLoop()
        textFont("Helvetica")
        textSize(20)

        do {
            let lines = try loadStrings("data/cars2.tsv")
            // Load data into array (skip malformed lines)
            records = lines.compactMap { Record(pieces: $0.components(separatedBy: "\t")) }
        } catch {
            print("Failed to load data/cars2.tsv: \(error)")
        }
    }

    func draw() {
        background(0)
        fill(255)
        for i in 0..<num {
            let thisEntry = startingEntry + i
            if thisEntry < records.count {
                text("\(thisEntry) > \(records[thisEntry].name)", 20, 20 + Float(i) * 20)
            }
        }
    }

    func mousePressed() {
        startingEntry += num
        if startingEntry > records.count {
            startingEntry = 0  // go back to the beginning
        }
        redraw()
    }
}
