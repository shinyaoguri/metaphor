import metaphor

@main
final class Spore2: Sketch {
    var config: SketchConfig { SketchConfig(title: "Spore 2", width: 640, height: 360) }

    let maxCells = 8000
    var cellX: [Int] = []
    var cellY: [Int] = []
    var numCells = 0
    let runsPerLoop = 10000
    var grid: [[UInt8]] = []  // 0=empty, 1-4=species
    var w = 640, h = 360
    let colors: [(UInt8, UInt8, UInt8)] = [
        (0, 0, 0), (128, 172, 255), (64, 128, 255), (255, 128, 172), (255, 64, 128)
    ]

    func setup() {
        w = Int(width); h = Int(height)
        grid = Array(repeating: Array(repeating: 0, count: h), count: w)
        background(0)
        seed()
    }

    func seed() {
        cellX = []; cellY = []; numCells = 0
        for _ in 0..<maxCells {
            let cx = Int(random(Float(w)))
            let cy = Int(random(Float(h)))
            let species = UInt8(Int(random(4)) + 1)
            if grid[cx][cy] == 0 {
                grid[cx][cy] = species
                let c = colors[Int(species)]
                stroke(Float(c.0), Float(c.1), Float(c.2))
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
        let myType = getG(x, y)
        if myType == 1 || myType == 2 {
            if getG(x-1, y+1) == 0 && getG(x+1, y+1) == 0 && getG(x, y+1) == 0 { moveCell(i, 0, 1) }
            else { moveCell(i, Int(random(3)) - 1, 0) }
        } else if myType == 3 || myType == 4 {
            if getG(x-1, y-1) == 0 && getG(x+1, y-1) == 0 && getG(x, y-1) == 0 { moveCell(i, 0, -1) }
            else { moveCell(i, Int(random(3)) - 1, 0) }
        }
    }

    func moveCell(_ i: Int, _ dx: Int, _ dy: Int) {
        let nx = cellX[i] + dx, ny = cellY[i] + dy
        if getG(nx, ny) == 0 {
            let species = getG(cellX[i], cellY[i])
            setG(nx, ny, species)
            let c = colors[Int(species)]
            stroke(Float(c.0), Float(c.1), Float(c.2))
            point(Float(((nx % w) + w) % w), Float(((ny % h) + h) % h))
            setG(cellX[i], cellY[i], 0)
            stroke(0)
            point(Float(cellX[i]), Float(cellY[i]))
            cellX[i] = nx; cellY[i] = ny
        }
    }

    func getG(_ x: Int, _ y: Int) -> UInt8 {
        grid[((x % w) + w) % w][((y % h) + h) % h]
    }

    func setG(_ x: Int, _ y: Int, _ v: UInt8) {
        grid[((x % w) + w) % w][((y % h) + h) % h] = v
    }

    func mousePressed() {
        grid = Array(repeating: Array(repeating: 0, count: h), count: w)
        background(0)
        seed()
    }
}
