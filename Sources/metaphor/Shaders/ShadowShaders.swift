import Foundation

/// シャドウマッピング用シェーダーソース
public enum ShadowShaders {

    /// シャドウ深度パス用の MSL ソース
    public static let depthSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ShadowUniforms {
        float4x4 modelMatrix;
        float4x4 lightSpaceMatrix;
    };

    struct ShadowVertexIn {
        float3 position [[attribute(0)]];
    };

    vertex float4 metaphor_shadowDepthVertex(
        ShadowVertexIn in [[stage_in]],
        constant ShadowUniforms &uniforms [[buffer(1)]]
    ) {
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        return uniforms.lightSpaceMatrix * worldPos;
    }
    """
}
