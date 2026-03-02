import metaphor
import Metal

@main
final class GameOfLifeExample: Sketch {
    let cellSize: Int = 8
    var cols = 0
    var rows = 0
    var paused = false

    var kernel: ComputeKernel!
    var currentGrid: GPUBuffer<Int32>!
    var nextGrid: GPUBuffer<Int32>!

    var config: SketchConfig {
        SketchConfig(title: "Game of Life (GPU)")
    }

    func setup() {
        cols = 1920 / cellSize
        rows = 1080 / cellSize
        let total = cols * rows

        currentGrid = createBuffer(count: total, type: Int32.self)!
        nextGrid = createBuffer(count: total, type: Int32.self)!

        randomize()

        kernel = try! createComputeKernel(source: """
        #include <metal_stdlib>
        using namespace metal;

        struct Params {
            uint cols;
            uint rows;
        };

        kernel void gameOfLifeStep(
            device const int *current [[buffer(0)]],
            device int *next [[buffer(1)]],
            constant Params &params [[buffer(2)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            uint c = gid.x;
            uint r = gid.y;
            if (c >= params.cols || r >= params.rows) return;

            int neighbors = 0;
            for (int dr = -1; dr <= 1; dr++) {
                for (int dc = -1; dc <= 1; dc++) {
                    if (dr == 0 && dc == 0) continue;
                    uint nr = (r + uint(dr) + params.rows) % params.rows;
                    uint nc = (c + uint(dc) + params.cols) % params.cols;
                    if (current[nr * params.cols + nc] > 0) neighbors++;
                }
            }

            uint idx = r * params.cols + c;
            int alive = current[idx];
            if (alive > 0) {
                next[idx] = (neighbors == 2 || neighbors == 3) ? alive + 1 : 0;
            } else {
                next[idx] = (neighbors == 3) ? 1 : 0;
            }
        }
        """, function: "gameOfLifeStep")
    }

    private func randomize() {
        let total = cols * rows
        for i in 0..<total {
            currentGrid[i] = Float.random(in: 0...1) > 0.7 ? 1 : 0
        }
    }

    private func addGlider(_ col: Int, _ row: Int) {
        for (dr, dc) in [(0,1), (1,2), (2,0), (2,1), (2,2)] {
            let r = (row + dr) % rows
            let c = (col + dc) % cols
            currentGrid[r * cols + c] = 1
        }
    }

    func compute() {
        guard !paused && frameCount % 6 == 0 else { return }

        struct Params {
            var cols: UInt32
            var rows: UInt32
        }
        var params = Params(cols: UInt32(cols), rows: UInt32(rows))

        dispatch(kernel, width: cols, height: rows) { encoder in
            encoder.setBuffer(currentGrid.buffer, offset: 0, index: 0)
            encoder.setBuffer(nextGrid.buffer, offset: 0, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.size, index: 2)
        }

        swap(&currentGrid, &nextGrid)
    }

    func draw() {
        background(Color(gray: 0.05))

        noStroke()
        let cs = Float(cellSize)
        for r in 0..<rows {
            for c in 0..<cols {
                let age = currentGrid[r * cols + c]
                if age > 0 {
                    let hue = Float(age % 360) / 360.0
                    fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
                    rect(Float(c) * cs, Float(r) * cs, cs - 1, cs - 1)
                }
            }
        }

        if paused {
            fill(Color(gray: 1.0, alpha: 0.5))
            rect(20, 20, 12, 30)
            rect(38, 20, 12, 30)
        }
    }

    func mousePressed() {
        let col = Int(input.mouseX) / cellSize
        let row = Int(input.mouseY) / cellSize
        if row >= 0 && row < rows && col >= 0 && col < cols {
            addGlider(col, row)
        }
    }

    func keyPressed() {
        if let key = input.lastKey {
            if key == "r" { randomize() }
            else if key == " " { paused = !paused }
        }
    }
}
