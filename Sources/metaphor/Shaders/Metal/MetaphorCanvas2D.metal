#include <metal_stdlib>
using namespace metal;

struct Canvas2DVertexIn {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct Canvas2DVertexOut {
    float4 position [[position]];
    float4 color;
};

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
