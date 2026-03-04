import metaphor

@main
final class GameOfLife: Sketch {
    var config: SketchConfig { SketchConfig(title: "Game of Life", width: 640, height: 360) }

    let cellSize = 5
    var cells: [[Int]] = []
    var cellsBuffer: [[Int]] = []
    var paused = false
    var cols = 0, rows = 0
    var lastTime: Int = 0

    func setup() {
        cols = Int(width) / cellSize
        rows = Int(height) / cellSize
        cells = Array(repeating: Array(repeating: 0, count: rows), count: cols)
        cellsBuffer = cells
        stroke(48)
        randomizeCells()
        background(0)
    }

    func draw() {
        for x in 0..<cols {
            for y in 0..<rows {
                if cells[x][y] == 1 { fill(0, 200, 0) } else { fill(0) }
                rect(Float(x * cellSize), Float(y * cellSize), Float(cellSize), Float(cellSize))
            }
        }
        if millis - lastTime > 100 && !paused {
            iteration()
            lastTime = millis
        }
        if paused && isMousePressed {
            let xc = max(0, min(Int(mouseX) / cellSize, cols - 1))
            let yc = max(0, min(Int(mouseY) / cellSize, rows - 1))
            cells[xc][yc] = cellsBuffer[xc][yc] == 1 ? 0 : 1
        } else if paused && !isMousePressed {
            cellsBuffer = cells
        }
    }

    func iteration() {
        cellsBuffer = cells
        for x in 0..<cols {
            for y in 0..<rows {
                var n = 0
                for xx in max(0, x - 1)...min(cols - 1, x + 1) {
                    for yy in max(0, y - 1)...min(rows - 1, y + 1) {
                        if !(xx == x && yy == y) && cellsBuffer[xx][yy] == 1 { n += 1 }
                    }
                }
                if cellsBuffer[x][y] == 1 {
                    if n < 2 || n > 3 { cells[x][y] = 0 }
                } else if n == 3 { cells[x][y] = 1 }
            }
        }
    }

    func randomizeCells() {
        for x in 0..<cols { for y in 0..<rows { cells[x][y] = random(100) < 15 ? 1 : 0 } }
    }

    func keyPressed() {
        if key == "r" || key == "R" { randomizeCells() }
        if key == " " { paused = !paused }
        if key == "c" || key == "C" { cells = Array(repeating: Array(repeating: 0, count: rows), count: cols) }
    }
}
