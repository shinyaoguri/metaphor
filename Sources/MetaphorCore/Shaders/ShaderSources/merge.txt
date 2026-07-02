#include <metal_stdlib>
using namespace metal;

/// ブレンドモード定数
constant uint BLEND_ADD      = 0;
constant uint BLEND_ALPHA    = 1;
constant uint BLEND_MULTIPLY = 2;
constant uint BLEND_SCREEN   = 3;

/// マージパラメータ
struct MergeParams {
    uint blend_mode;
};

/// 2テクスチャ合成コンピュートカーネル
kernel void metaphor_mergeTextures(
    texture2d<float, access::read>  texA   [[texture(0)]],
    texture2d<float, access::read>  texB   [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant MergeParams &params           [[buffer(0)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    // 出力は max(texA, texB) サイズのため、小さい方の入力では gid が範囲外に
    // なり得る。範囲外 read は MSL では未定義値なので、transparent black を使う。
    float4 a = (gid.x < texA.get_width() && gid.y < texA.get_height())
        ? texA.read(gid) : float4(0.0);
    float4 b = (gid.x < texB.get_width() && gid.y < texB.get_height())
        ? texB.read(gid) : float4(0.0);
    float4 result;

    switch (params.blend_mode) {
        case BLEND_ADD:
            result = float4(a.rgb + b.rgb, saturate(a.a + b.a));
            break;
        case BLEND_ALPHA:
            // B over A (B が前景)
            result = float4(
                b.rgb * b.a + a.rgb * (1.0 - b.a),
                b.a + a.a * (1.0 - b.a)
            );
            break;
        case BLEND_MULTIPLY:
            result = float4(a.rgb * b.rgb, a.a * b.a);
            break;
        case BLEND_SCREEN:
            result = float4(
                1.0 - (1.0 - a.rgb) * (1.0 - b.rgb),
                1.0 - (1.0 - a.a) * (1.0 - b.a)
            );
            break;
        default:
            result = a;
            break;
    }

    output.write(result, gid);
}
