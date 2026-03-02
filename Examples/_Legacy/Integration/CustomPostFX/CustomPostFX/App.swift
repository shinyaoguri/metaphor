import metaphor

/// Feature 5 デモ: カスタムポストエフェクト
///
/// ユーザー定義のMSLフラグメントシェーダーでポストプロセスを行う。
/// ピクセレーション + カラーシフトの組み合わせエフェクト。
/// [1]キーでピクセレーション、[2]キーでRGBシフトをトグル。
@main
final class CustomPostFX: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Custom Post Effect — Pixelate & RGB Shift")
    }

    var pixelateFX: CustomPostEffect?
    var rgbShiftFX: CustomPostEffect?
    var usePixelate = true
    var useRGBShift = true

    // パラメータ構造体
    struct PixelateParams {
        var pixelSize: Float
        var _pad0: Float = 0
        var _pad1: Float = 0
        var _pad2: Float = 0
    }

    struct RGBShiftParams {
        var amount: Float
        var angle: Float
        var _pad0: Float = 0
        var _pad1: Float = 0
    }

    func setup() {
        // ── ピクセレーション エフェクト ──
        let pixelateSource = """
        #include <metal_stdlib>
        using namespace metal;

        \(PostProcessShaders.commonStructs)

        struct PixelateParams {
            float pixelSize;
            float _pad0;
            float _pad1;
            float _pad2;
        };

        fragment float4 pixelateFragment(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]],
            constant PixelateParams &custom [[buffer(1)]]
        ) {
            constexpr sampler s(filter::nearest);
            float2 uv = in.texCoord;

            float pixelSize = max(custom.pixelSize, 1.0);
            float2 texSize = float2(tex.get_width(), tex.get_height());
            float2 cell = floor(uv * texSize / pixelSize) * pixelSize / texSize;

            return tex.sample(s, cell);
        }
        """

        // ── RGB シフト エフェクト ──
        let rgbShiftSource = """
        #include <metal_stdlib>
        using namespace metal;

        \(PostProcessShaders.commonStructs)

        struct RGBShiftParams {
            float amount;
            float angle;
            float _pad0;
            float _pad1;
        };

        fragment float4 rgbShiftFragment(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]],
            constant RGBShiftParams &custom [[buffer(1)]]
        ) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float2 uv = in.texCoord;

            float2 dir = float2(cos(custom.angle), sin(custom.angle)) * custom.amount;
            float r = tex.sample(s, uv + dir).r;
            float g = tex.sample(s, uv).g;
            float b = tex.sample(s, uv - dir).b;
            float a = tex.sample(s, uv).a;

            return float4(r, g, b, a);
        }
        """

        do {
            pixelateFX = try createPostEffect(
                name: "pixelate",
                source: pixelateSource,
                fragmentFunction: "pixelateFragment"
            )
            rgbShiftFX = try createPostEffect(
                name: "rgbShift",
                source: rgbShiftSource,
                fragmentFunction: "rgbShiftFragment"
            )
        } catch {
            print("Post effect shader compilation failed: \(error)")
        }

        rebuildEffectChain()
    }

    func keyPressed() {
        // [1] = keyCode 18, [2] = keyCode 19
        if keyCode == 18 {
            usePixelate.toggle()
            rebuildEffectChain()
        }
        if keyCode == 19 {
            useRGBShift.toggle()
            rebuildEffectChain()
        }
    }

    func draw() {
        background(Color(r: 0.05, g: 0.03, b: 0.08))

        let t = time

        // ── アニメーションパラメータ ──
        if let px = pixelateFX {
            let size: Float = 4 + sin(t * 0.5) * 3 + (sin(t * 2) + 1) * 2
            px.setParameters(PixelateParams(pixelSize: size))
        }

        if let rgb = rgbShiftFX {
            let amount: Float = 0.003 + sin(t * 1.2) * 0.004
            let angle = t * 0.5
            rgb.setParameters(RGBShiftParams(amount: amount, angle: angle))
        }

        // ── シーン描画 ──
        drawScene(t: t)

        // ── UI ──
        fill(Color(gray: 0.5))
        noStroke()
        textSize(14)
        textFont("Menlo")
        textAlign(.left, .top)
        text("[1] Pixelate: \(usePixelate ? "ON" : "OFF")", 30, 30)
        text("[2] RGB Shift: \(useRGBShift ? "ON" : "OFF")", 30, 50)
    }

    // MARK: - エフェクトチェーン再構築

    private func rebuildEffectChain() {
        clearPostEffects()
        if usePixelate, let px = pixelateFX {
            addPostEffect(.custom(px))
        }
        if useRGBShift, let rgb = rgbShiftFX {
            addPostEffect(.custom(rgb))
        }
    }

    // MARK: - シーン

    private func drawScene(t: Float) {
        let cx = width / 2
        let cy = height / 2

        // 背景のグリッド
        stroke(Color(r: 0.15, g: 0.1, b: 0.25))
        strokeWeight(1)
        let gridSize: Float = 80
        let cols = Int(width / gridSize) + 1
        let rows = Int(height / gridSize) + 1
        for c in 0...cols {
            let x = Float(c) * gridSize
            line(x, 0, x, height)
        }
        for r in 0...rows {
            let y = Float(r) * gridSize
            line(0, y, width, y)
        }

        // 中央の幾何学模様
        noStroke()
        let layers = 8
        for i in (0..<layers).reversed() {
            let fi = Float(i)
            let r = 80 + fi * 35
            let rotation = t * (0.2 + fi * 0.05) * (i % 2 == 0 ? 1 : -1)
            let sides = 3 + i % 5

            let hue = fmod(fi / Float(layers) + t * 0.08, 1.0)
            colorMode(.hsb, 1)
            let alpha: Float = 0.4 + fi / Float(layers) * 0.4
            fill(hue, 0.7, 0.9, alpha)
            colorMode(.rgb, 255)

            var verts: [(Float, Float)] = []
            for s in 0..<sides {
                let angle = Float(s) / Float(sides) * Float.pi * 2 + rotation
                verts.append((cx + cos(angle) * r, cy + sin(angle) * r))
            }
            polygon(verts)
        }

        // 浮遊する粒子
        noStroke()
        for i in 0..<60 {
            let fi = Float(i)
            let angle = fi * 0.618 * Float.pi * 2 + t * 0.2
            let dist = 200 + sin(t + fi * 0.3) * 150
            let x = cx + cos(angle) * dist
            let y = cy + sin(angle) * dist
            let size: Float = 3 + sin(t * 2 + fi) * 2

            let brightness = 0.5 + sin(t * 3 + fi * 0.5) * 0.5
            fill(Color(r: brightness, g: 0.5 * brightness, b: 0.9, a: 0.7))
            circle(x, y, size)
        }
    }
}
