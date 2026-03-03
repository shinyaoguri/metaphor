/// Contains embedded MSL source code for Canvas2D instanced drawing shaders.
///
/// Uses `instance_id` to read per-instance data (transform, color),
/// allowing batch rendering of identical shapes in a single draw call.
enum Canvas2DInstancedShaders {

    // MARK: - Function Names

    /// MSL function name for the instanced vertex shader.
    static let vertexFunctionName = "metaphor_canvas2DInstancedVertex"
    /// MSL function name for the instanced fragment shader.
    static let fragmentFunctionName = "metaphor_canvas2DInstancedFragment"
    /// MSL function name for the instanced difference blend fragment shader.
    static let differenceFragmentFunctionName = "metaphor_canvas2DInstancedDifferenceFragment"
    /// MSL function name for the instanced exclusion blend fragment shader.
    static let exclusionFragmentFunctionName = "metaphor_canvas2DInstancedExclusionFragment"

    // MARK: - MSL Source

    /// MSL source code for Canvas2D instanced rendering with blend mode variants.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Per-instance data (80 bytes, 16-byte aligned)
    struct InstanceData2D {
        float4x4 transform;  // 2D affine embedded in 4x4
        float4 color;         // RGBA
    };

    struct Canvas2DInstancedVertexIn {
        float2 position [[attribute(0)]];
    };

    struct Canvas2DInstancedVertexOut {
        float4 position [[position]];
        float4 color;
    };

    // ──────────────────────────────────────────────
    // Vertex shader
    // ──────────────────────────────────────────────

    vertex Canvas2DInstancedVertexOut \(vertexFunctionName)(
        Canvas2DInstancedVertexIn in [[stage_in]],
        uint instanceID [[instance_id]],
        device const InstanceData2D *instances [[buffer(6)]],
        constant float4x4 &projection [[buffer(1)]]
    ) {
        Canvas2DInstancedVertexOut out;
        InstanceData2D inst = instances[instanceID];
        float4 worldPos = inst.transform * float4(in.position, 0.0, 1.0);
        out.position = projection * worldPos;
        out.color = inst.color;
        return out;
    }

    // ──────────────────────────────────────────────
    // Fragment shaders (3 variants for blend modes)
    // ──────────────────────────────────────────────

    fragment float4 \(fragmentFunctionName)(
        Canvas2DInstancedVertexOut in [[stage_in]]
    ) {
        return in.color;
    }

    fragment float4 \(differenceFragmentFunctionName)(
        Canvas2DInstancedVertexOut in [[stage_in]],
        float4 dest [[color(0)]]
    ) {
        float4 src = in.color;
        float a = src.a + dest.a * (1.0 - src.a);
        float3 blended = abs(src.rgb - dest.rgb);
        float3 result = mix(dest.rgb, blended, src.a);
        return float4(result, a);
    }

    fragment float4 \(exclusionFragmentFunctionName)(
        Canvas2DInstancedVertexOut in [[stage_in]],
        float4 dest [[color(0)]]
    ) {
        float4 src = in.color;
        float a = src.a + dest.a * (1.0 - src.a);
        float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
        float3 result = mix(dest.rgb, blended, src.a);
        return float4(result, a);
    }
    """
}
