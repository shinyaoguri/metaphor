import Foundation

/// Contains embedded MSL source code for texture merge (compositing) compute shaders.
///
/// Blends two textures using a specified blend mode via a compute kernel.
/// Supported blend_mode values: 0=add, 1=alpha, 2=multiply, 3=screen.
enum MergeShaders {

    /// MSL source code for the texture merge compute kernel.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Blend mode constants
    constant uint BLEND_ADD      = 0;
    constant uint BLEND_ALPHA    = 1;
    constant uint BLEND_MULTIPLY = 2;
    constant uint BLEND_SCREEN   = 3;

    // Merge parameters
    struct MergeParams {
        uint blend_mode;
    };

    // Two-texture compositing compute kernel
    kernel void metaphor_mergeTextures(
        texture2d<float, access::read>  texA   [[texture(0)]],
        texture2d<float, access::read>  texB   [[texture(1)]],
        texture2d<float, access::write> output [[texture(2)]],
        constant MergeParams &params           [[buffer(0)]],
        uint2 gid                              [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

        float4 a = texA.read(gid);
        float4 b = texB.read(gid);
        float4 result;

        switch (params.blend_mode) {
            case BLEND_ADD:
                result = float4(a.rgb + b.rgb, saturate(a.a + b.a));
                break;
            case BLEND_ALPHA:
                // B over A (B is foreground)
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
    """

    /// Merge shader function name constants.
    enum FunctionName {
        /// MSL function name for the texture merge compute kernel.
        static let mergeTextures = "metaphor_mergeTextures"
    }
}
