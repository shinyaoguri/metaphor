import metaphor

@main
final class Spore1: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Spore 1") }

    let maxCells = 6700
    var cellX: [Int] = []
    var cellY: [Int] = []
    var numCells = 0
    let runsPerLoop = 10000
    var grid: [[Bool]] = []
    var w = 640, h = 360

    func setup() {
        w = Int(width); h = Int(height)
        grid = Array(repeating: Array(repeating: false, count: h), count: w)
        background(0)
        seed()
    }

    func seed() {
        cellX = []; cellY = []; numCells = 0
        for _ in 0..<maxCells {
            let cx = Int(random(Float(w)))
            let cy = Int(random(Float(h)))
            if !grid[cx][cy] {
                grid[cx][cy] = true
                stroke(172, 255, 128)
                point(Float(cx), Float(cy))
                cellX.append(cx); cellY.append(cy)
                numCells += 1
            }
        }
    }

    func draw() {
        for _ in 0..<runsPerLoop {
            guard numCells > 0 else { return }
            let sel = min(Int(random(Float(numCells))), numCells - 1)
            runCell(sel)
        }
    }

    func runCell(_ i: Int) {
        cellX[i] = ((cellX[i] % w) + w) % w
        cellY[i] = ((cellY[i] % h) + h) % h
        let x = cellX[i], y = cellY[i]
        if !getG(x + 1, y) {
            moveCell(i, 0, 1)
        } else if getG(x, y - 1) && getG(x, y + 1) {
            moveCell(i, Int(random(9)) - 4, Int(random(9)) - 4)
        }
    }

    func moveCell(_ i: Int, _ dx: Int, _ dy: Int) {
        let nx = cellX[i] + dx, ny = cellY[i] + dy
        if !getG(nx, ny) {
            setG(nx, ny, true)
            stroke(172, 255, 128)
            point(Float(((nx % w) + w) % w), Float(((ny % h) + h) % h))
            setG(cellX[i], cellY[i], false)
            stroke(0)
            point(Float(cellX[i]), Float(cellY[i]))
            cellX[i] = nx; cellY[i] = ny
        }
    }

    func getG(_ x: Int, _ y: Int) -> Bool {
        grid[((x % w) + w) % w][((y % h) + h) % h]
    }

    func setG(_ x: Int, _ y: Int, _ v: Bool) {
        grid[((x % w) + w) % w][((y % h) + h) % h] = v
    }

    func mousePressed() {
        grid = Array(repeating: Array(repeating: false, count: h), count: w)
        background(0)
        seed()
    }
}
