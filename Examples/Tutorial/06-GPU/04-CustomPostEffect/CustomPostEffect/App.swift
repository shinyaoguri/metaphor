import metaphor

/// シェーダーの buffer(1) へ渡す自前のパラメータ。
/// MSL 側の struct と並びと大きさを合わせます。
struct RippleParams {
    var frequency: Float
    var phase: Float
}

@main
final class Ripple: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "CustomPostEffect")
    }

    var effect: CustomPostEffect?

    // 共通の構造体定義（PPVertexOut / PostProcessParams）に自作の関数を足す
    let source = PostProcessShaders.commonStructs + """

    struct RippleParams {
        float frequency;
        float phase;
    };

    fragment float4 ripple(
        PPVertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]],
        constant PostProcessParams &params [[buffer(0)]],
        constant RippleParams &rp [[buffer(1)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        // 画面中心からの距離。texelSize から縦横比を戻して真円にする
        float aspect = params.texelSize.y / params.texelSize.x;
        float2 d = in.texCoord - float2(0.5);
        d.x *= aspect;
        float dist = length(d);

        // 距離に応じた波で、サンプリング位置を中心方向へずらす
        float wave = sin(dist * rp.frequency - rp.phase);
        float2 offset = normalize(d + 1e-6) * wave * params.intensity;
        offset.x /= aspect;

        float4 color = tex.sample(s, in.texCoord + offset);
        return float4(color.rgb + wave * 0.035, color.a);   // 波の峰をわずかに明るく
    }
    """

    func setup() {
        effect = try? createPostEffect(name: "ripple", source: source, fragmentFunction: "ripple")
        if let effect {
            effect.intensity = 0.006          // 組み込みの枠（PostProcessParams.intensity）
            addPostEffect(effect)
        }
        noStroke()
    }

    func draw() {
        // 波の位相だけを毎フレーム送る
        effect?.setParameters(RippleParams(frequency: 42, phase: Float(frameCount) * 0.08))

        background(14, 16, 26)

        // 歪みが見えるように、まっすぐな格子を敷く
        for iy in 0..<9 {
            for ix in 0..<16 {
                let odd = (ix + iy) % 2 == 0
                fill(odd ? 46 : 30, odd ? 58 : 38, odd ? 96 : 62)
                rect(Float(ix) * 40, Float(iy) * 40, 40, 40)
            }
        }

        fill(240, 180, 90)
        circle(320, 180, 90)
        fill(255)
        textSize(15)
        textAlign(.center)
        text("自作シェーダーで画面全体を波打たせている", 320, 336)
    }
}
