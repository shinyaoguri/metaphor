import Foundation

/// metaphorの組み込みMetalシェーダーソース
public enum BuiltinShaders {

    // MARK: - Blit (フルスクリーンテクスチャ転送)

    /// オフスクリーンテクスチャを画面にブリットするシェーダー
    public static let blitSource = """
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
    """

    // MARK: - Common Structures

    /// 全シェーダーで共有されるMSL構造体定義
    static let commonStructs = """
    struct MetaphorUniforms {
        float4x4 modelMatrix;
        float4x4 viewProjectionMatrix;
        float4 color;
        float3 lightDirection;
        float time;
    };
    """

    // MARK: - FlatColor (単色・ライティングなし)

    /// 単色で描画するシェーダー (positionのみ vertex descriptor使用)
    public static let flatColorSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(commonStructs)

    struct FlatColorVertexIn {
        float3 position [[attribute(0)]];
    };

    struct FlatColorVertexOut {
        float4 position [[position]];
    };

    vertex FlatColorVertexOut metaphor_flatColorVertex(
        FlatColorVertexIn in [[stage_in]],
        constant MetaphorUniforms &uniforms [[buffer(1)]]
    ) {
        FlatColorVertexOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.position = uniforms.viewProjectionMatrix * worldPos;
        return out;
    }

    fragment float4 metaphor_flatColorFragment(
        FlatColorVertexOut in [[stage_in]],
        constant MetaphorUniforms &uniforms [[buffer(1)]]
    ) {
        return uniforms.color;
    }
    """

    // MARK: - VertexColor (頂点カラー・ライティングなし)

    /// 頂点カラーで描画するシェーダー (positionColor or positionNormalColor)
    public static let vertexColorSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(commonStructs)

    struct VertexColorIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct VertexColorOut {
        float4 position [[position]];
        float4 color;
    };

    vertex VertexColorOut metaphor_vertexColorVertex(
        VertexColorIn in [[stage_in]],
        constant MetaphorUniforms &uniforms [[buffer(1)]]
    ) {
        VertexColorOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.color = in.color;
        return out;
    }

    fragment float4 metaphor_vertexColorFragment(
        VertexColorOut in [[stage_in]]
    ) {
        return in.color;
    }
    """

    // MARK: - Lit (Blinn-Phongライティング)

    /// Blinn-Phongライティング付きシェーダー (positionNormalColor)
    public static let litSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(commonStructs)

    struct LitVertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct LitVertexOut {
        float4 position [[position]];
        float3 normal;
        float4 color;
        float3 worldPosition;
    };

    vertex LitVertexOut metaphor_litVertex(
        LitVertexIn in [[stage_in]],
        constant MetaphorUniforms &uniforms [[buffer(1)]]
    ) {
        LitVertexOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
        out.color = in.color * uniforms.color;
        return out;
    }

    fragment float4 metaphor_litFragment(
        LitVertexOut in [[stage_in]],
        constant MetaphorUniforms &uniforms [[buffer(1)]]
    ) {
        float3 normal = normalize(in.normal);
        float3 lightDir = normalize(uniforms.lightDirection);

        float diffuse = max(dot(normal, lightDir), 0.0);
        float ambient = 0.3;
        float lighting = ambient + diffuse * 0.7;

        return float4(in.color.rgb * lighting, in.color.a);
    }
    """

    // MARK: - Canvas2D (2D描画用 - Phase 2で使用)

    /// Canvas2D用のフラットカラーシェーダー
    public static let canvas2DSource = """
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
    """

    // MARK: - Canvas3D Shared Structures (3Dシェーダー共通定義)

    /// Canvas3D用のGPU構造体定義（untextured / textured で共有）
    ///
    /// カスタムマテリアルシェーダーを作成する際に、MSLソースのプレフィックスとして使用する。
    /// ```swift
    /// let source = """
    /// #include <metal_stdlib>
    /// using namespace metal;
    /// \(BuiltinShaders.canvas3DStructs)
    /// // カスタムフラグメントシェーダー ...
    /// """
    /// ```
    public static let canvas3DStructs = """
    struct Canvas3DUniforms {
        float4x4 modelMatrix;
        float4x4 viewProjectionMatrix;
        float4x4 normalMatrix;
        float4 color;
        float4 cameraPosition;
        float time;
        uint lightCount;
        uint hasTexture;
        uint _pad;
    };

    struct Light3D {
        float4 positionAndType;
        float4 directionAndCutoff;
        float4 colorAndIntensity;
        float4 attenuationAndOuterCutoff;
    };

    struct Material3D {
        float4 ambientColor;
        float4 specularAndShininess;
        float4 emissiveAndMetallic;
    };
    """

    /// Canvas3D用のBlinn-Phongライティング関数
    ///
    /// カスタムマテリアルシェーダーで組み込みライティング計算を利用する場合に使用する。
    public static let canvas3DLightingFn = """
    float3 calculateLighting(
        float3 worldPos,
        float3 normal,
        float3 cameraPos,
        float3 baseColor,
        constant Light3D *lights,
        uint lightCount,
        Material3D material
    ) {
        float3 N = normalize(normal);
        float3 V = normalize(cameraPos - worldPos);

        float3 ambient = material.ambientColor.xyz * baseColor;
        float3 result = ambient + material.emissiveAndMetallic.xyz;

        float metallic = material.emissiveAndMetallic.w;
        float shininess = max(material.specularAndShininess.w, 1.0);
        float3 specColor = mix(material.specularAndShininess.xyz, baseColor, metallic);
        float3 diffColor = baseColor * (1.0 - metallic);

        for (uint i = 0; i < lightCount; i++) {
            float3 lightColor = lights[i].colorAndIntensity.xyz * lights[i].colorAndIntensity.w;
            uint lightType = uint(lights[i].positionAndType.w);

            float3 L;
            float attenuation = 1.0;

            if (lightType == 0) {
                L = normalize(-lights[i].directionAndCutoff.xyz);
            } else {
                float3 lightVec = lights[i].positionAndType.xyz - worldPos;
                float dist = length(lightVec);
                L = lightVec / max(dist, 0.0001);

                float3 att = lights[i].attenuationAndOuterCutoff.xyz;
                attenuation = 1.0 / (att.x + att.y * dist + att.z * dist * dist);

                if (lightType == 2) {
                    float3 spotDir = normalize(lights[i].directionAndCutoff.xyz);
                    float theta = dot(L, -spotDir);
                    float innerCutoff = lights[i].directionAndCutoff.w;
                    float outerCutoff = lights[i].attenuationAndOuterCutoff.w;
                    float epsilon = innerCutoff - outerCutoff;
                    float spotIntensity = clamp((theta - outerCutoff) / max(epsilon, 0.001), 0.0, 1.0);
                    attenuation *= spotIntensity;
                }
            }

            float NdotL = max(dot(N, L), 0.0);
            float3 diffuse = diffColor * NdotL;

            float3 H = normalize(L + V);
            float NdotH = max(dot(N, H), 0.0);
            float spec = (NdotL > 0.0) ? pow(NdotH, shininess) : 0.0;
            float3 specular = specColor * spec;

            result += (diffuse + specular) * lightColor * attenuation;
        }

        return result;
    }
    """

    // MARK: - Canvas3D (3D描画用)

    /// Canvas3D用のマルチライト・マテリアル対応シェーダー（untextured）
    public static let canvas3DSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(canvas3DStructs)

    \(canvas3DLightingFn)

    struct Canvas3DVertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float4 color    [[attribute(2)]];
    };

    struct Canvas3DVertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float4 color;
    };

    vertex Canvas3DVertexOut metaphor_canvas3DVertex(
        Canvas3DVertexIn in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]]
    ) {
        Canvas3DVertexOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
        out.color = in.color * uniforms.color;
        return out;
    }

    fragment float4 metaphor_canvas3DFragment(
        Canvas3DVertexOut in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]]
    ) {
        if (uniforms.lightCount == 0) {
            return in.color;
        }

        float3 lit = calculateLighting(
            in.worldPosition,
            in.normal,
            uniforms.cameraPosition.xyz,
            in.color.rgb,
            lights,
            uniforms.lightCount,
            material
        );

        return float4(lit, in.color.a);
    }
    """

    // MARK: - Canvas3D Textured (テクスチャ付き3D描画)

    /// Canvas3D用テクスチャ付きシェーダー
    public static let canvas3DTexturedSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(canvas3DStructs)

    \(canvas3DLightingFn)

    struct Canvas3DTexVertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float2 uv       [[attribute(2)]];
    };

    struct Canvas3DTexVertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float2 uv;
    };

    vertex Canvas3DTexVertexOut metaphor_canvas3DTexturedVertex(
        Canvas3DTexVertexIn in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]]
    ) {
        Canvas3DTexVertexOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
        out.uv = in.uv;
        return out;
    }

    fragment float4 metaphor_canvas3DTexturedFragment(
        Canvas3DTexVertexOut in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]],
        texture2d<float> tex [[texture(0)]]
    ) {
        constexpr sampler s(filter::linear, address::repeat);
        float4 texColor = tex.sample(s, in.uv);
        float4 tintedColor = texColor * uniforms.color;

        if (uniforms.lightCount == 0) {
            return tintedColor;
        }

        float3 lit = calculateLighting(
            in.worldPosition,
            in.normal,
            uniforms.cameraPosition.xyz,
            tintedColor.rgb,
            lights,
            uniforms.lightCount,
            material
        );

        return float4(lit, tintedColor.a);
    }
    """

    // MARK: - Canvas2D Textured (テクスチャ付き2D描画)

    /// Canvas2D用テクスチャ付きシェーダー（画像・テキスト描画用）
    public static let canvas2DTexturedSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Canvas2DTexVertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct Canvas2DTexVertexOut {
        float4 position [[position]];
        float2 texCoord;
        float4 color;
    };

    vertex Canvas2DTexVertexOut metaphor_canvas2DTexturedVertex(
        Canvas2DTexVertexIn in [[stage_in]],
        constant float4x4 &projection [[buffer(1)]]
    ) {
        Canvas2DTexVertexOut out;
        out.position = projection * float4(in.position, 0.0, 1.0);
        out.texCoord = in.texCoord;
        out.color = in.color;
        return out;
    }

    fragment float4 metaphor_canvas2DTexturedFragment(
        Canvas2DTexVertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 texColor = tex.sample(s, in.texCoord);
        return texColor * in.color;
    }

    fragment float4 metaphor_canvas2DTexturedDifferenceFragment(
        Canvas2DTexVertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]],
        float4 dest [[color(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 src = tex.sample(s, in.texCoord) * in.color;
        float a = src.a + dest.a * (1.0 - src.a);
        float3 blended = abs(src.rgb - dest.rgb);
        float3 result = mix(dest.rgb, blended, src.a);
        return float4(result, a);
    }

    fragment float4 metaphor_canvas2DTexturedExclusionFragment(
        Canvas2DTexVertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]],
        float4 dest [[color(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 src = tex.sample(s, in.texCoord) * in.color;
        float a = src.a + dest.a * (1.0 - src.a);
        float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
        float3 result = mix(dest.rgb, blended, src.a);
        return float4(result, a);
    }
    """

    // MARK: - Shader Function Names

    /// 組み込みシェーダーの関数名
    public enum FunctionName {
        public static let blitVertex = "metaphor_blitVertex"
        public static let blitFragment = "metaphor_blitFragment"
        public static let flatColorVertex = "metaphor_flatColorVertex"
        public static let flatColorFragment = "metaphor_flatColorFragment"
        public static let vertexColorVertex = "metaphor_vertexColorVertex"
        public static let vertexColorFragment = "metaphor_vertexColorFragment"
        public static let litVertex = "metaphor_litVertex"
        public static let litFragment = "metaphor_litFragment"
        public static let canvas2DVertex = "metaphor_canvas2DVertex"
        public static let canvas2DFragment = "metaphor_canvas2DFragment"
        public static let canvas2DDifferenceFragment = "metaphor_canvas2DDifferenceFragment"
        public static let canvas2DExclusionFragment = "metaphor_canvas2DExclusionFragment"
        public static let canvas3DVertex = "metaphor_canvas3DVertex"
        public static let canvas3DFragment = "metaphor_canvas3DFragment"
        public static let canvas2DTexturedVertex = "metaphor_canvas2DTexturedVertex"
        public static let canvas2DTexturedFragment = "metaphor_canvas2DTexturedFragment"
        public static let canvas2DTexturedDifferenceFragment = "metaphor_canvas2DTexturedDifferenceFragment"
        public static let canvas2DTexturedExclusionFragment = "metaphor_canvas2DTexturedExclusionFragment"
        public static let canvas3DTexturedVertex = "metaphor_canvas3DTexturedVertex"
        public static let canvas3DTexturedFragment = "metaphor_canvas3DTexturedFragment"
    }
}
