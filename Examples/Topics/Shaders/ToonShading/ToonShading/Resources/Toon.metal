// 3D カスタムマテリアル（トゥーンシェーディング）。原典 data/ToonFrag.glsl の移植。
//
// 書くのはフラグメント関数だけ。前文（#include <metal_stdlib> + Canvas3DUniforms /
// Light3D / Canvas3DVertexOut などの構造体 + ライティング関数）は
// createMaterialFromFile() が必ず足すので、自分で定義すると再定義エラーになる。
//
// 頂点シェーダーは組み込みのまま。Canvas3DVertexOut が法線とワールド座標を運ぶので、
// 面の塗り方を変えるだけならフラグメントで足りる。

fragment float4 toonFragment(
    Canvas3DVertexOut in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]],
    constant Light3D *lights [[buffer(2)]]
) {
    float3 n = normalize(in.normal);

    // 原典は「ディレクショナルライトが 1 つだけ」を前提にしているので、先頭のライトだけ見る。
    // 読み方は組み込みのライティング関数（MetaphorLighting.h）と揃える:
    // type 0 = directional で directionAndCutoff は光の進む向き、それ以外は位置から求める。
    float3 lightDir = float3(0.0, 0.0, 1.0);  // ライトが無いときは視線方向から当てる
    if (uniforms.lightCount > 0) {
        if (uint(lights[0].positionAndType.w) == 0) {
            lightDir = normalize(-lights[0].directionAndCutoff.xyz);
        } else {
            lightDir = normalize(lights[0].positionAndType.xyz - in.worldPosition);
        }
    }

    float intensity = max(0.0, dot(lightDir, n));

    // 連続した明るさを 4 段に量子化する。これがトゥーン（セル）シェーディングの本体で、
    // しきい値と色は原典 ToonFrag.glsl のまま。
    float4 color;
    if (intensity > 0.95) {
        color = float4(1.0, 0.5, 0.5, 1.0);
    } else if (intensity > 0.5) {
        color = float4(0.6, 0.3, 0.3, 1.0);
    } else if (intensity > 0.25) {
        color = float4(0.4, 0.2, 0.2, 1.0);
    } else {
        color = float4(0.2, 0.1, 0.1, 1.0);
    }
    return color;
}
