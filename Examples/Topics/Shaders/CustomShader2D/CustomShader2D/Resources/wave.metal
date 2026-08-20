// 2D カスタムフラグメントシェーダ（loadShader() から読み込まれます）。
//
// metaphor が前文（Metal 標準ライブラリ + Canvas2DVertexOut /
// Canvas2DShaderUniforms の定義）を必ず先頭へ足すので、フラグメント関数だけを書けば動きます。
// 前文にある構造体は自分で定義し直さないでください（再定義エラーになります）。
//
// 2D のカラー頂点は UV を持たないので、uv は [[position]]（フラグメントでは画面ピクセル座標）を
// resolution で割って作ります。Shadertoy の fragCoord / iResolution と同じ形です。

struct WaveParams {
    float amount;   // 歪みの強さ
    float bands;    // 縞の本数
};

fragment float4 waveFragment(
    Canvas2DVertexOut in [[stage_in]],
    constant Canvas2DShaderUniforms &u [[buffer(3)]],
    constant WaveParams &p [[buffer(4)]]
) {
    float2 uv = in.position.xy / u.resolution;
    float2 c = uv * 2.0 - 1.0;
    c.x *= u.resolution.x / u.resolution.y;

    float r = length(c);
    float a = atan2(c.y, c.x);

    // 中心からの距離と角度で縞を作り、時間で流す
    float wave = sin(r * p.bands - u.time * 1.5 + sin(a * 3.0) * p.amount * 4.0);
    float band = smoothstep(0.0, 0.6, wave);

    float3 warm = float3(0.98, 0.42, 0.24);
    float3 cool = float3(0.13, 0.30, 0.62);
    float3 rgb = mix(cool, warm, band);

    // マウスの近くを明るくして、組み込み uniform が効いていることを見えるようにする
    float2 m = u.mouse / u.resolution;
    rgb += 0.35 * exp(-24.0 * distance(uv, m));

    // 図形の頂点色（fill / alpha）を掛けて、図形の形にシェーダを通す。
    // キャンバスの中身は premultiplied なので、返す直前に metaphorPremultiply() を通す
    // （前文に入っているヘルパ）。不透明しか返さないなら掛けても値は変わらない。
    return metaphorPremultiply(float4(rgb, 1.0) * in.color);
}
