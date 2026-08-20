import metaphor

/// シェーダーの buffer(4) へ渡す自前のパラメータ。
/// MSL 側の struct と並びと大きさを合わせます。
struct PaintParams {
    var phase: Float
    var bands: Float
}

@main
final class ShapeShader: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ShapeShader")
    }

    var paint: Shader2D?

    // 前文（Metal 標準ライブラリと Canvas2DVertexOut / Canvas2DShaderUniforms の定義）は
    // metaphor が必ず先頭へ足すので、フラグメント関数だけを書きます
    let source = """
    struct PaintParams {
        float phase;
        float bands;
    };

    fragment float4 paint(
        Canvas2DVertexOut in [[stage_in]],
        constant Canvas2DShaderUniforms &u [[buffer(3)]],
        constant PaintParams &p [[buffer(4)]]
    ) {
        // 2D の頂点は UV を持たないので、画面ピクセル座標を resolution で割って作る
        float2 uv = in.position.xy / u.resolution;
        float2 c = uv * 2.0 - 1.0;
        c.x *= u.resolution.x / u.resolution.y;   // 縦横比を戻して同心円を真円にする

        float wave = sin(length(c) * p.bands - p.phase);
        float band = smoothstep(-0.6, 0.6, wave);
        float3 rgb = mix(float3(0.09, 0.13, 0.30), float3(0.98, 0.55, 0.25), band);

        // fill() の色とアルファを掛け、premultiplied にして返す（キャンバスの規範）
        return metaphorPremultiply(float4(rgb, 1.0) * in.color);
    }
    """

    func setup() {
        paint = try? createShader(source: source, fragment: "paint")
        noStroke()
    }

    func draw() {
        background(14, 16, 26)
        guard let paint else { return }

        // 位相はフレーム数から作る（同じフレームなら必ず同じ絵になる）
        let phase = Float(frameCount) * 0.06

        // 画面いっぱいの矩形。fill() の色が掛かるので、暗い灰色で敷いて奥へ下げる
        paint.setParameters(PaintParams(phase: phase, bands: 14))
        fill(110)
        shader(paint)
        rect(0, 0, width, height)

        // 同じシェーダーを別のパラメータで円に掛ける。
        // shader() を呼び直すとバッチが切れ、その時点のパラメータが焼き込まれる
        paint.setParameters(PaintParams(phase: -phase * 1.6, bands: 40))
        fill(255)
        shader(paint)
        circle(320, 170, 220)

        resetShader()

        // 解除したので、ここから下は組み込みシェーダーに戻る
        fill(0, 150)
        rect(0, 316, width, 44)
        fill(255)
        textSize(15)
        textAlign(.center)
        text("矩形と円はシェーダー、この帯と文字は resetShader() のあと", 320, 342)
    }
}
