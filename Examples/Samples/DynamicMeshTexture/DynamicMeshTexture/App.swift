// DynamicMeshTexture
//
// DynamicMesh の 2 つの特徴を同時に見せるサンプル:
//   1. 頂点を毎フレーム書き換えられる（setVertex で波打たせる）
//   2. addTexCoord で宣言した UV に沿ってテクスチャが貼られる
//
// UV は一度だけ宣言し、以降は位置だけを更新します（UV は頂点と同じ添字で保持されるため、
// setVertex しても貼り付きはずれません）。

import metaphor

@main
final class DynamicMeshTexture: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "DynamicMeshTexture")
    }

    // グリッドの分割数（頂点数は (cols + 1) * (rows + 1)）
    let cols = 40
    let rows = 30
    let cellSize: Float = 14

    var mesh: DynamicMesh!
    var img: MImage!

    func setup() {
        img = makeCheckerImage(size: 256, tile: 32)

        mesh = createDynamicMesh()
        mesh.addNormal(SIMD3(0, 0, 1))

        // 頂点と UV（左上 (0,0) → 右下 (1,1)）
        for row in 0...rows {
            for col in 0...cols {
                mesh.addTexCoord(Float(col) / Float(cols), Float(row) / Float(rows))
                mesh.addVertex(position(col: col, row: row, time: 0))
            }
        }

        // 各セルを 2 枚の三角形に
        for row in 0..<rows {
            for col in 0..<cols {
                let i = UInt32(row * (cols + 1) + col)
                let below = i + UInt32(cols + 1)
                mesh.addTriangle(i, i + 1, below + 1)
                mesh.addTriangle(i, below + 1, below)
            }
        }

        noStroke()
    }

    func draw() {
        background(18)

        let t = Float(frameCount) * 0.03
        for row in 0...rows {
            for col in 0...cols {
                mesh.setVertex(row * (cols + 1) + col, position(col: col, row: row, time: t))
            }
        }

        translate(width / 2, height / 2)
        rotateX(-0.9)
        rotateZ(Float(frameCount) * 0.004)

        texture(img)
        dynamicMesh(mesh)
    }

    // 波打つグリッドの頂点位置（グリッド中央が原点）
    private func position(col: Int, row: Int, time: Float) -> SIMD3<Float> {
        let x = (Float(col) - Float(cols) / 2) * cellSize
        let y = (Float(row) - Float(rows) / 2) * cellSize
        let z = sin(Float(col) * 0.35 + time) * 18 + cos(Float(row) * 0.3 - time) * 18
        return SIMD3(x, y, z)
    }

    // 市松模様のテクスチャを手続き的に生成（外部ファイル不要）
    private func makeCheckerImage(size: Int, tile: Int) -> MImage {
        let image = createImage(size, size)!
        image.loadPixels()
        for y in 0..<size {
            for x in 0..<size {
                let isEven = ((x / tile) + (y / tile)) % 2 == 0
                let idx = (y * size + x) * 4
                image.pixels[idx] = isEven ? 245 : 40                    // R
                image.pixels[idx + 1] = isEven ? 180 : 90                // G
                image.pixels[idx + 2] = UInt8(60 + 195 * y / size)       // B
                image.pixels[idx + 3] = 255
            }
        }
        image.updatePixels()
        return image
    }
}
