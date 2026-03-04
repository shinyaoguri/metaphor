import metaphor

// NOTE: Original uses a GLSL shader with ppixels uniform for Game of Life.
// This version uses CPU-based cellular automaton with MImage.

@main
final class Conway: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Conway", width: 400, height: 400)
    }

    let cellSize = 4
    var cols = 0
    var rows = 0
    var grid: [[Bool]] = []
    var img: MImage!

    func setup() {
        cols = Int(width) / cellSize
        rows = Int(height) / cellSize

        // Random initial state
        grid = Array(repeating: Array(repeating: false, count: rows), count: cols)
        for x in 0..<cols {
            for y in 0..<rows {
                grid[x][y] = Float.random(in: 0...1) > 0.7
            }
        }

        img = createImage(cols, rows)
    }

    func draw() {
        // Update grid
        var newGrid = Array(repeating: Array(repeating: false, count: rows), count: cols)
        for x in 0..<cols {
            for y in 0..<rows {
                var neighbors = 0
                for dx in -1...1 {
                    for dy in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = (x + dx + cols) % cols
                        let ny = (y + dy + rows) % rows
                        if grid[nx][ny] { neighbors += 1 }
                    }
                }
                if grid[x][y] {
                    newGrid[x][y] = neighbors == 2 || neighbors == 3
                } else {
                    newGrid[x][y] = neighbors == 3
                }
            }
        }
        grid = newGrid

        // Add cells near mouse
        let mx = Int(mouseX) / cellSize
        let my = Int(mouseY) / cellSize
        if mx >= 0 && mx < cols && my >= 0 && my < rows {
            for dx in -2...2 {
                for dy in -2...2 {
                    let nx = (mx + dx + cols) % cols
                    let ny = (my + dy + rows) % rows
                    if Float.random(in: 0...1) > 0.5 {
                        grid[nx][ny] = true
                    }
                }
            }
        }

        // Render to MImage
        img.loadPixels()
        for y in 0..<rows {
            for x in 0..<cols {
                let idx = (y * cols + x) * 4
                if grid[x][y] {
                    img.pixels[idx] = 255; img.pixels[idx + 1] = 255
                    img.pixels[idx + 2] = 255; img.pixels[idx + 3] = 255
                } else {
                    img.pixels[idx] = 0; img.pixels[idx + 1] = 0
                    img.pixels[idx + 2] = 0; img.pixels[idx + 3] = 255
                }
            }
        }
        img.updatePixels()
        image(img, 0, 0, width, height)
    }
}
