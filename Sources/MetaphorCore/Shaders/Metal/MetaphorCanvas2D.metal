#include "MetaphorCanvas2DTypes.h"

// `Canvas2DVertexIn` / `Canvas2DVertexOut` は `MetaphorCanvas2DTypes.h`（= カスタム
// 2D シェーダへ配る前文）にある。組み込みとカスタムで stage_in のレイアウトが
// ずれないよう、定義は 1 箇所に置く。

vertex Canvas2DVertexOut metaphor_canvas2DVertex(
    Canvas2DVertexIn in [[stage_in]],
    constant float4x4 &projection [[buffer(1)]]
) {
    Canvas2DVertexOut out;
    out.position = projection * float4(in.position, 0.0, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 metaphor_canvas2DFragment(
    Canvas2DVertexOut in [[stage_in]]
) {
    return in.color;
}

fragment float4 metaphor_canvas2DDifferenceFragment(
    Canvas2DVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = abs(src.rgb - dest.rgb);
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}

fragment float4 metaphor_canvas2DExclusionFragment(
    Canvas2DVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}
