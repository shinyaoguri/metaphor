# Compute Shader

Run Metal compute shaders for GPU-accelerated parallel computation. Ideal for particle simulations, cellular automata, and physics.

## Overview

The compute pipeline runs in a separate phase **before** `draw()`:

```
frame: setup → compute() → draw()
```

Write your MSL (Metal Shading Language) kernel inline as a string, create typed GPU buffers, and dispatch work on the GPU.

## Creating Kernels

### `createComputeKernel(source: String, function: String) throws -> ComputeKernel`

Compiles MSL source code and creates a compute kernel. Call in `setup()`.

| Parameter | Description |
|-----------|-------------|
| `source` | Metal Shading Language source code |
| `function` | Entry point function name |

```swift
var kernel: ComputeKernel!

func setup() {
    kernel = try! createComputeKernel(source: """
    #include <metal_stdlib>
    using namespace metal;

    kernel void update(
        device float2 *positions [[buffer(0)]],
        constant float &time [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        positions[id].x += cos(time + float(id) * 0.01);
        positions[id].y += sin(time + float(id) * 0.01);
    }
    """, function: "update")
}
```

## Creating Buffers

### `createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>?`

Creates a zero-initialized typed GPU buffer.

```swift
var positions: GPUBuffer<SIMD2<Float>>!

func setup() {
    positions = createBuffer(count: 10000, type: SIMD2<Float>.self)!
}
```

### `createBuffer<T>(_ data: [T]) -> GPUBuffer<T>?`

Creates a GPU buffer initialized from an array.

```swift
let initialData: [Float] = [1.0, 2.0, 3.0, 4.0]
var buffer = createBuffer(initialData)!
```

## GPUBuffer

A typed wrapper around `MTLBuffer` with `storageModeShared` for zero-copy CPU/GPU access on Apple Silicon.

### Element Access

```swift
// Read/write individual elements
buffer[0] = SIMD2<Float>(100, 200)
let pos = buffer[0]

// Bulk operations
let array = buffer.toArray()       // Copy to Swift array
buffer.copyFrom(newData)           // Copy from Swift array

// Direct pointer access (for high-performance loops)
for i in buffer.contents.indices {
    buffer.contents[i] = ...
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `buffer` | `MTLBuffer` | Underlying Metal buffer |
| `count` | `Int` | Number of elements |
| `contents` | `UnsafeMutableBufferPointer<T>` | Direct memory access |

## Dispatching Work

### `dispatch(_ kernel: ComputeKernel, threads: Int, _ configure: (MTLComputeCommandEncoder) -> Void)`

1D dispatch — runs the kernel with `threads` total threads.

```swift
func compute() {
    var t = time
    dispatch(kernel, threads: positions.count) { encoder in
        encoder.setBuffer(positions.buffer, offset: 0, index: 0)
        encoder.setBytes(&t, length: MemoryLayout<Float>.size, index: 1)
    }
}
```

### `dispatch(_ kernel: ComputeKernel, width: Int, height: Int, _ configure: (MTLComputeCommandEncoder) -> Void)`

2D dispatch — for grid-based computations (e.g., cellular automata, image processing).

```swift
func compute() {
    dispatch(kernel, width: cols, height: rows) { encoder in
        encoder.setBuffer(currentGrid.buffer, offset: 0, index: 0)
        encoder.setBuffer(nextGrid.buffer, offset: 0, index: 1)
    }
}
```

### `computeBarrier()`

Inserts a memory barrier between dispatches to ensure data dependencies are resolved.

```swift
func compute() {
    dispatch(kernelA, threads: count) { enc in
        enc.setBuffer(buf.buffer, offset: 0, index: 0)
    }

    computeBarrier()  // Ensure kernelA results are visible

    dispatch(kernelB, threads: count) { enc in
        enc.setBuffer(buf.buffer, offset: 0, index: 0)
    }
}
```

## Example: Game of Life

```swift
@main
final class GameOfLife: Sketch {
    let cellSize = 8
    var cols = 0, rows = 0
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

        // Randomize initial state
        for i in 0..<total {
            currentGrid[i] = Float.random(in: 0...1) > 0.7 ? 1 : 0
        }

        kernel = try! createComputeKernel(source: """
        #include <metal_stdlib>
        using namespace metal;

        struct Params { uint cols; uint rows; };

        kernel void step(
            device const int *current [[buffer(0)]],
            device int *next [[buffer(1)]],
            constant Params &params [[buffer(2)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= params.cols || gid.y >= params.rows) return;

            int neighbors = 0;
            for (int dr = -1; dr <= 1; dr++) {
                for (int dc = -1; dc <= 1; dc++) {
                    if (dr == 0 && dc == 0) continue;
                    uint nr = (gid.y + uint(dr) + params.rows) % params.rows;
                    uint nc = (gid.x + uint(dc) + params.cols) % params.cols;
                    if (current[nr * params.cols + nc] > 0) neighbors++;
                }
            }

            uint idx = gid.y * params.cols + gid.x;
            int alive = current[idx];
            next[idx] = (alive > 0)
                ? ((neighbors == 2 || neighbors == 3) ? alive + 1 : 0)
                : ((neighbors == 3) ? 1 : 0);
        }
        """, function: "step")
    }

    func compute() {
        struct Params { var cols: UInt32; var rows: UInt32 }
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
                    fill(Color(hue: Float(age % 360) / 360.0, saturation: 0.8, brightness: 1.0))
                    rect(Float(c) * cs, Float(r) * cs, cs - 1, cs - 1)
                }
            }
        }
    }
}
```

## See Also

- [Sketch](sketch.md) - `compute()` lifecycle
- [Math](math.md) - Utility functions
