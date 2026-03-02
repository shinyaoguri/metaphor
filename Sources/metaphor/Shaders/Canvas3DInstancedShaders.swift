/// Canvas3D インスタンシング描画用シェーダー
///
/// `instance_id` で per-instance データ（transform, color）を読み取り、
/// 同一メッシュの大量描画を1回の draw call で処理する。
enum Canvas3DInstancedShaders {

    // MARK: - Function Names

    static let vertexFunctionName = "metaphor_canvas3DInstancedVertex"
    static let fragmentFunctionName = "metaphor_canvas3DInstancedFragment"
    static let texturedVertexFunctionName = "metaphor_canvas3DTexInstancedVertex"
    static let texturedFragmentFunctionName = "metaphor_canvas3DTexInstancedFragment"

    // MARK: - MSL Source

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    \(BuiltinShaders.canvas3DStructs)

    // Per-instance data (160 bytes, 16-byte aligned)
    struct InstanceData3D {
        float4x4 modelMatrix;
        float4x4 normalMatrix;
        float4 color;
        float4 _pad;
    };

    // Scene-wide uniforms shared across all instances in a batch
    struct InstancedSceneUniforms {
        float4x4 viewProjectionMatrix;
        float4 cameraPosition;
        float time;
        uint lightCount;
        uint hasTexture;
        uint _pad2;
    };

    \(BuiltinShaders.canvas3DLightingFn)

    // ──────────────────────────────────────────────
    // Untextured instanced vertex/fragment
    // ──────────────────────────────────────────────

    struct Canvas3DInstancedVertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float4 color    [[attribute(2)]];
    };

    struct Canvas3DInstancedVertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float4 color;
    };

    vertex Canvas3DInstancedVertexOut \(vertexFunctionName)(
        Canvas3DInstancedVertexIn in [[stage_in]],
        uint instanceID [[instance_id]],
        device const InstanceData3D *instances [[buffer(6)]],
        constant InstancedSceneUniforms &scene [[buffer(1)]]
    ) {
        Canvas3DInstancedVertexOut out;
        InstanceData3D inst = instances[instanceID];
        float4 worldPos = inst.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = scene.viewProjectionMatrix * worldPos;
        out.normal = (inst.normalMatrix * float4(in.normal, 0.0)).xyz;
        out.color = in.color * inst.color;
        return out;
    }

    fragment float4 \(fragmentFunctionName)(
        Canvas3DInstancedVertexOut in [[stage_in]],
        constant InstancedSceneUniforms &scene [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]],
        constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
        texture2d<float> shadowMap [[texture(1)]]
    ) {
        if (scene.lightCount == 0) {
            return in.color;
        }

        float3 lit = calculateLighting(
            in.worldPosition, in.normal, scene.cameraPosition.xyz,
            in.color.rgb, lights, scene.lightCount, material
        );

        constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::never);
        float shadow = calculateShadow(in.worldPosition, shadowUniforms, shadowMap, shadowSampler);
        float3 ambient = material.ambientColor.xyz * in.color.rgb;
        lit = ambient + (lit - ambient) * shadow;

        return float4(lit, in.color.a);
    }

    // ──────────────────────────────────────────────
    // Textured instanced vertex/fragment
    // ──────────────────────────────────────────────

    struct Canvas3DTexInstancedVertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float2 uv       [[attribute(2)]];
    };

    struct Canvas3DTexInstancedVertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float2 uv;
        float4 tintColor;
    };

    vertex Canvas3DTexInstancedVertexOut \(texturedVertexFunctionName)(
        Canvas3DTexInstancedVertexIn in [[stage_in]],
        uint instanceID [[instance_id]],
        device const InstanceData3D *instances [[buffer(6)]],
        constant InstancedSceneUniforms &scene [[buffer(1)]]
    ) {
        Canvas3DTexInstancedVertexOut out;
        InstanceData3D inst = instances[instanceID];
        float4 worldPos = inst.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = scene.viewProjectionMatrix * worldPos;
        out.normal = (inst.normalMatrix * float4(in.normal, 0.0)).xyz;
        out.uv = in.uv;
        out.tintColor = inst.color;
        return out;
    }

    fragment float4 \(texturedFragmentFunctionName)(
        Canvas3DTexInstancedVertexOut in [[stage_in]],
        constant InstancedSceneUniforms &scene [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]],
        constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
        texture2d<float> tex [[texture(0)]],
        texture2d<float> shadowMap [[texture(1)]]
    ) {
        constexpr sampler s(filter::linear, address::repeat);
        float4 texColor = tex.sample(s, in.uv);
        float4 tintedColor = texColor * in.tintColor;

        if (scene.lightCount == 0) {
            return tintedColor;
        }

        float3 lit = calculateLighting(
            in.worldPosition, in.normal, scene.cameraPosition.xyz,
            tintedColor.rgb, lights, scene.lightCount, material
        );

        constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::never);
        float shadow = calculateShadow(in.worldPosition, shadowUniforms, shadowMap, shadowSampler);
        float3 ambient = material.ambientColor.xyz * tintedColor.rgb;
        lit = ambient + (lit - ambient) * shadow;

        return float4(lit, tintedColor.a);
    }
    """
}
