import metaphor

@main
final class TileImages: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 600, height: 600, title: "TileImages")
    }

    let scaleValue: Int = 3
    var xoffset: Int = 0
    var yoffset: Int = 0
    var finished = false

    func setup() {
        stroke(0, 100)
    }

    func draw() {
        background(204)

        if !finished {
            pushMatrix()
            scale(Float(scaleValue))
            translate(Float(xoffset) * (-width / Float(scaleValue)),
                      Float(yoffset) * (-height / Float(scaleValue)))
            line(10, 150, 500, 50)
            line(0, 600, 600, 0)
            popMatrix()

            // Display tile info
            fill(0)
            textSize(14)
            textAlign(.left, .top)
            text("Tile [\(yoffset), \(xoffset)]", 10, 10)

            // Original would save tile image here
            print("Saving tile lines-\(yoffset)-\(xoffset).png")
            setOffset()
        } else {
            // Show all tiles overview
            let tileW = width / Float(scaleValue)
            let tileH = height / Float(scaleValue)
            for ty in 0..<scaleValue {
                for tx in 0..<scaleValue {
                    pushMatrix()
                    let ox = Float(tx) * tileW
                    let oy = Float(ty) * tileH
                    // Draw the content scaled to fit in tile
                    translate(ox, oy)
                    scale(1.0 / Float(scaleValue))
                    stroke(0, 100)
                    line(10, 150, 500, 50)
                    line(0, 600, 600, 0)
                    popMatrix()

                    // Tile border
                    noFill()
                    stroke(255, 0, 0)
                    rect(ox, oy, tileW, tileH)
                }
            }

            fill(0)
            noStroke()
            textSize(16)
            textAlign(.center, .center)
            text("All \(scaleValue * scaleValue) tiles rendered", width / 2, height - 30)
            noLoop()
        }
    }

    func setOffset() {
        xoffset += 1
        if xoffset == scaleValue {
            xoffset = 0
            yoffset += 1
            if yoffset == scaleValue {
                print("Tiles saved.")
                finished = true
            }
        }
    }
}
