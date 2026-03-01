import metaphor

/// Feature 3 デモ: カスタムシェーダーマテリアル
///
/// トゥーンシェーディング（セル画調）のカスタムフラグメントシェーダーを
/// 3Dオブジェクトに適用する。
@main
final class CustomShader: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Custom Shader Material — Toon Shading")
    }

    var toonMaterial: CustomMaterial?

    // トゥーンシェーダー用パラメータ
    struct ToonParams {
        var bands: Float       // 明暗の段階数
        var edgeThreshold: Float // アウトラインの閾値
        var tintR: Float
        var tintG: Float
        var tintB: Float
        var _pad: Float = 0
    }

    func setup() {
        // カスタムフラグメントシェーダー (MSL)
        let toonSource = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)
        \(BuiltinShaders.canvas3DLightingFn)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        struct ToonParams {
            float bands;
            float edgeThreshold;
            float tintR;
            float tintG;
            float tintB;
            float _pad;
        };

        fragment float4 toonFragment(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]],
            constant ToonParams &params [[buffer(4)]]
        ) {
            float3 N = normalize(in.normal);
            float3 baseColor = in.color.rgb;
            float3 tint = float3(params.tintR, params.tintG, params.tintB);
            baseColor *= tint;

            if (uniforms.lightCount == 0) {
                return float4(baseColor, in.color.a);
            }

            // ライティング計算
            float3 lit = calculateLighting(
                in.worldPosition,
                in.normal,
                uniforms.cameraPosition.xyz,
                baseColor,
                lights,
                uniforms.lightCount,
                material
            );

            // 輝度を計算
            float luminance = dot(lit, float3(0.299, 0.587, 0.114));

            // バンド化（段階的な明暗）
            float bands = max(params.bands, 2.0);
            float quantized = floor(luminance * bands) / bands;

            // 色に適用
            float3 toonColor = baseColor * (quantized + 0.1);

            // エッジ検出（カメラに対する法線の角度）
            float3 viewDir = normalize(uniforms.cameraPosition.xyz - in.worldPosition);
            float edge = dot(N, viewDir);
            if (edge < params.edgeThreshold) {
                toonColor *= 0.1; // アウトライン
            }

            return float4(toonColor, in.color.a);
        }
        """

        do {
            toonMaterial = try createMaterial(
                source: toonSource,
                fragmentFunction: "toonFragment"
            )
        } catch {
            print("Shader compilation failed: \(error)")
        }
    }

    func draw() {
        background(Color(r: 0.95, g: 0.92, b: 0.88))

        let t = time

        camera(
            eye: SIMD3<Float>(0, 100, 600),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        perspective(fov: radians(50), near: 1, far: 2000)

        noLights()
        directionalLight(0.6, -0.8, -0.5)
        ambientLight(0.2)

        guard let mat = toonMaterial else { return }

        // ── 左: バンド数少なめ（パキッとしたトゥーン）──
        pushMatrix()
        translate(-250, 50, 0)
        rotateY(t * 0.5)
        rotateX(sin(t * 0.3) * 0.2)

        mat.setParameters(ToonParams(
            bands: 3,
            edgeThreshold: 0.25,
            tintR: 0.9, tintG: 0.3, tintB: 0.3
        ))
        material(mat)
        fill(Color(gray: 0.9))
        sphere(90, detail: 48)
        noMaterial()
        popMatrix()

        // ── 中央: バンド数多め + 回転するボックス群 ──
        pushMatrix()
        translate(0, 50, 0)
        rotateY(t * 0.6)

        mat.setParameters(ToonParams(
            bands: 5,
            edgeThreshold: 0.2,
            tintR: 0.3, tintG: 0.7, tintB: 0.9
        ))
        material(mat)
        fill(Color(gray: 0.95))
        box(130)
        noMaterial()
        popMatrix()

        // 中央の周りに浮遊するミニオブジェクト
        for i in 0..<6 {
            let angle = Float(i) / 6 * Float.pi * 2 + t * 0.8
            let orbitR: Float = 200
            let bobY = sin(t * 2 + Float(i)) * 30

            pushMatrix()
            translate(cos(angle) * orbitR, 50 + bobY, sin(angle) * orbitR)
            rotateY(t * 2 + Float(i))
            rotateX(t * 1.5)

            // 各オブジェクトに異なる色のトゥーン
            let hue = Float(i) / 6
            let r = (sin(hue * Float.pi * 2) + 1) * 0.5
            let g = (sin(hue * Float.pi * 2 + Float.pi * 2 / 3) + 1) * 0.5
            let b = (sin(hue * Float.pi * 2 + Float.pi * 4 / 3) + 1) * 0.5

            mat.setParameters(ToonParams(
                bands: 4,
                edgeThreshold: 0.3,
                tintR: r * 0.8 + 0.2,
                tintG: g * 0.8 + 0.2,
                tintB: b * 0.8 + 0.2
            ))
            material(mat)
            fill(Color(gray: 0.9))
            sphere(30, detail: 24)
            noMaterial()

            popMatrix()
        }

        // ── 右: エッジ強調 ──
        pushMatrix()
        translate(250, 50, 0)
        rotateY(t * 0.4)
        rotateX(t * 0.3)

        mat.setParameters(ToonParams(
            bands: 4,
            edgeThreshold: 0.45,
            tintR: 0.4, tintG: 0.9, tintB: 0.4
        ))
        material(mat)
        fill(Color(gray: 0.9))
        cylinder(radius: 60, height: 140, detail: 32)
        noMaterial()
        popMatrix()

        // ── 地面のプレート ──
        pushMatrix()
        translate(0, -100, 0)
        rotateX(Float.pi / 2)

        mat.setParameters(ToonParams(
            bands: 3,
            edgeThreshold: 0.15,
            tintR: 0.6, tintG: 0.55, tintB: 0.5
        ))
        material(mat)
        fill(Color(gray: 0.8))
        box(600, 600, 10)
        noMaterial()
        popMatrix()

        // ── UI ──
        noLights()
        noStroke()
        fill(Color(gray: 0.3))
        textSize(14)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Custom Fragment Shader: Toon / Cel Shading", 30, 30)
        text("Left: 3 bands | Center: 5 bands | Right: thick edge", 30, 50)
    }
}
