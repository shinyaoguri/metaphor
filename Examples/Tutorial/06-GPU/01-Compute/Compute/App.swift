import Metal
import metaphor

/// カーネルへ渡す設定。Swift と MSL の両方で同じ並び・同じ大きさにします。
/// ここがずれると、シェーダーは何も言わずに別の値を読みます。
struct FieldParams {
    var cols: UInt32
    var rows: UInt32
    var cx: Float
    var cy: Float
}

@main
final class Compute: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Compute")
    }

    // 4 ピクセル角のセルでキャンバスを埋める
    let cols = 160
    let rows = 90

    var kernel: ComputeKernel?
    var field: GPUBuffer<Float>?

    // GPU 側のカーネル。1 スレッドが 1 セルを担当する
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FieldParams {
        uint  cols;
        uint  rows;
        float cx;
        float cy;
    };

    kernel void julia(
        device float *out [[buffer(0)]],
        constant FieldParams &p [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= p.cols * p.rows) { return; }

        // セルの番号を複素平面の座標へ
        float x = (float(id % p.cols) + 0.5) / float(p.cols) * 3.2 - 1.6;
        float y = (float(id / p.cols) + 0.5) / float(p.rows) * 1.8 - 0.9;

        // 発散するまでの回数を数える（ジュリア集合）
        float2 z = float2(x, y);
        const int maxIter = 120;
        int i = 0;
        for (; i < maxIter; i++) {
            z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + float2(p.cx, p.cy);
            if (dot(z, z) > 256.0) { break; }
        }

        if (i == maxIter) {
            out[id] = 1.0;                    // 発散しなかった = 集合の内側
        } else {
            // 回数を小数まで滑らかにする（整数のままだと縞が出る）
            float smooth = float(i) + 1.0 - log2(log2(length(z)));
            out[id] = clamp(smooth / float(maxIter), 0.0, 0.999);
        }
    }
    """

    func setup() {
        kernel = try? createComputeKernel(source: source, function: "julia")
        field = createBuffer(count: cols * rows, type: Float.self)
        noStroke()
    }

    // draw() の前に呼ばれる GPU 計算のフック
    func compute() {
        guard let kernel, let field else { return }

        var params = FieldParams(cols: UInt32(cols), rows: UInt32(rows), cx: -0.70, cy: 0.27)
        dispatch(kernel, threads: cols * rows) { encoder in
            encoder.setBuffer(field.buffer, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<FieldParams>.stride, index: 1)
        }
    }

    func draw() {
        background(12)
        guard let field else { return }

        // GPU が書いた値をそのまま読む（ユニファイドメモリなのでコピーは要らない）
        let values = field.contents
        let cellW = Float(width) / Float(cols)
        let cellH = Float(height) / Float(rows)

        for iy in 0..<rows {
            for ix in 0..<cols {
                let t = values[iy * cols + ix]
                if t >= 1.0 {
                    fill(16, 18, 34)                     // 集合の内側
                } else {
                    let u = pow(t, 0.35)                 // 外側は縁に色を寄せる
                    fill(30 + 225 * u, 20 + 120 * u * u, 90 + 120 * u)
                }
                rect(Float(ix) * cellW, Float(iy) * cellH, cellW, cellH)
            }
        }

        fill(235)
        textSize(13)
        text("GPU が \(cols * rows) セルを並列に計算し、CPU がその値で塗り分けている", 14, 26)
    }
}
