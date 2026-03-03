#include <metal_stdlib>
using namespace metal;

struct BlitVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex BlitVertexOut metaphor_blitVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2( 1,  1)
    };

    float2 texCoords[4] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };

    BlitVertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 metaphor_blitFragment(
    BlitVertexOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]]
) {
    constexpr sampler s(filter::linear);
    return texture.sample(s, in.texCoord);
}
