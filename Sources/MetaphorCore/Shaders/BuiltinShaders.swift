import Foundation

/// Built-in Metal shader source strings for runtime compilation.
///
/// metaphor uses a dual shader system:
/// - **`.metal` files** (in `Shaders/Metal/`): Pre-compiled by Xcode/SPM, preferred for production.
/// - **Source strings** (this file): Runtime-compiled via `MTLDevice.makeLibrary(source:)`.
///   Used as fallback and for shader hot-reload during development.
///
/// New shaders should be added as `.metal` files under `Shaders/Metal/`.
///
/// Includes blit, flat-color, vertex-color, lit (Blinn-Phong), Canvas2D,
/// Canvas3D (untextured/textured), and Canvas2D textured shaders.
public enum BuiltinShaders {

    // MARK: - Blit (Fullscreen Texture Transfer)

    /// MSL source code for the fullscreen blit shader that copies an offscreen texture to the screen.
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

    /// MSL struct definitions shared across all shaders.
    static let commonStructs = """
    struct MetaphorUniforms {
        float4x4 modelMatrix;
        float4x4 viewProjectionMatrix;
        float4 color;
        float3 lightDirection;
        float time;
    };
    """

    // MARK: - FlatColor (Solid Color, No Lighting)

    /// MSL source code for the flat-color shader (position-only vertex descriptor, no lighting).
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

    // MARK: - VertexColor (Per-Vertex Color, No Lighting)

    /// MSL source code for the vertex-color shader (positionColor or positionNormalColor, no lighting).
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

    // MARK: - Lit (Blinn-Phong Lighting)

    /// MSL source code for the Blinn-Phong lit shader (positionNormalColor).
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

    // MARK: - Canvas2D (2D Drawing)

    /// MSL source code for the Canvas2D flat-color shader with blend mode variants.
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

    // MARK: - Canvas3D Shared Structures (Common 3D Shader Definitions)

    /// MSL struct definitions shared by Canvas3D untextured and textured shaders.
    ///
    /// Use as a prefix when writing custom material shaders.
    /// ```swift
    /// let source = """
    /// #include <metal_stdlib>
    /// using namespace metal;
    /// \(BuiltinShaders.canvas3DStructs)
    /// // Custom fragment shader ...
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
        float4 pbrParams;
    };

    struct ShadowFragmentUniforms {
        float4x4 lightSpaceMatrix;
        float shadowBias;
        float shadowEnabled;
        float2 _pad;
    };
    """

    /// MSL lighting functions (Blinn-Phong + PBR Cook-Torrance GGX).
    ///
    /// Use when custom material shaders need built-in lighting calculations.
    public static let canvas3DLightingFn = """
    // Shadow calculation (PCF 3x3)
    float calculateShadow(
        float3 worldPos,
        constant ShadowFragmentUniforms &shadowUniforms,
        texture2d<float> shadowMap,
        sampler shadowSampler
    ) {
        if (shadowUniforms.shadowEnabled < 0.5) return 1.0;
        float4 lightSpacePos = shadowUniforms.lightSpaceMatrix * float4(worldPos, 1.0);
        float3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
        float2 shadowUV = projCoords.xy * 0.5 + 0.5;
        shadowUV.y = 1.0 - shadowUV.y;
        if (shadowUV.x < 0 || shadowUV.x > 1 || shadowUV.y < 0 || shadowUV.y > 1) return 1.0;
        float currentDepth = projCoords.z;
        if (currentDepth > 1.0) return 1.0;
        float bias = shadowUniforms.shadowBias;
        float shadow = 0.0;
        float2 texelSize = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                float closestDepth = shadowMap.sample(shadowSampler, shadowUV + float2(x, y) * texelSize).r;
                shadow += (currentDepth - bias > closestDepth) ? 0.0 : 1.0;
            }
        }
        return shadow / 9.0;
    }

    // PBR helper functions
    float DistributionGGX(float3 N, float3 H, float roughness) {
        float a = roughness * roughness;
        float a2 = a * a;
        float NdotH = max(dot(N, H), 0.0);
        float NdotH2 = NdotH * NdotH;
        float denom = NdotH2 * (a2 - 1.0) + 1.0;
        denom = M_PI_F * denom * denom;
        return a2 / max(denom, 0.0000001);
    }

    float GeometrySchlickGGX(float NdotV, float roughness) {
        float r = roughness + 1.0;
        float k = (r * r) / 8.0;
        return NdotV / (NdotV * (1.0 - k) + k);
    }

    float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
        float NdotV = max(dot(N, V), 0.0);
        float NdotL = max(dot(N, L), 0.0);
        return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
    }

    float3 FresnelSchlick(float cosTheta, float3 F0) {
        return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
    }

    // PBR (Cook-Torrance GGX) lighting
    float3 calculatePBRLighting(
        float3 worldPos, float3 normal, float3 cameraPos, float3 baseColor,
        constant Light3D *lights, uint lightCount, Material3D material
    ) {
        float3 N = normalize(normal);
        float3 V = normalize(cameraPos - worldPos);
        float metallic = material.emissiveAndMetallic.w;
        float roughness = clamp(material.pbrParams.x, 0.04, 1.0);
        float ao = material.pbrParams.z;
        float3 F0 = mix(float3(0.04), baseColor, metallic);
        float3 Lo = float3(0.0);

        for (uint i = 0; i < lightCount; i++) {
            float3 lightColor = lights[i].colorAndIntensity.xyz * lights[i].colorAndIntensity.w;
            uint lightType = uint(lights[i].positionAndType.w);
            float3 L; float attenuation = 1.0;

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
                    attenuation *= clamp((theta - outerCutoff) / max(epsilon, 0.001), 0.0, 1.0);
                }
            }

            float3 H = normalize(V + L);
            float NdotL = max(dot(N, L), 0.0);
            float D = DistributionGGX(N, H, roughness);
            float G = GeometrySmith(N, V, L, roughness);
            float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
            float3 specular = (D * G * F) / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001);
            float3 kD = (1.0 - F) * (1.0 - metallic);
            Lo += (kD * baseColor / M_PI_F + specular) * lightColor * NdotL * attenuation;
        }

        return material.ambientColor.xyz * baseColor * ao + material.emissiveAndMetallic.xyz + Lo;
    }

    // Blinn-Phong lighting
    float3 calculateBlinnPhongLighting(
        float3 worldPos, float3 normal, float3 cameraPos, float3 baseColor,
        constant Light3D *lights, uint lightCount, Material3D material
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
            float3 L; float attenuation = 1.0;

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
                    attenuation *= clamp((theta - outerCutoff) / max(epsilon, 0.001), 0.0, 1.0);
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

    // Unified entry point: auto-switch based on pbrParams.y
    float3 calculateLighting(
        float3 worldPos, float3 normal, float3 cameraPos, float3 baseColor,
        constant Light3D *lights, uint lightCount, Material3D material
    ) {
        if (material.pbrParams.y > 0.5) {
            return calculatePBRLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material);
        }
        return calculateBlinnPhongLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material);
    }
    """

    // MARK: - Canvas3D (3D Drawing)

    /// MSL source code for the Canvas3D multi-light material shader (untextured).
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
        constant Material3D &material [[buffer(3)]],
        constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
        texture2d<float> shadowMap [[texture(1)]]
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

        // Apply shadow
        constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::never);
        float shadow = calculateShadow(in.worldPosition, shadowUniforms, shadowMap, shadowSampler);
        float3 ambient = material.ambientColor.xyz * in.color.rgb;
        lit = ambient + (lit - ambient) * shadow;

        return float4(lit, in.color.a);
    }
    """

    // MARK: - Canvas3D Textured (Textured 3D Drawing)

    /// MSL source code for the Canvas3D textured shader.
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
        constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
        texture2d<float> tex [[texture(0)]],
        texture2d<float> shadowMap [[texture(1)]]
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

        // Apply shadow
        constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::never);
        float shadow = calculateShadow(in.worldPosition, shadowUniforms, shadowMap, shadowSampler);
        float3 ambient = material.ambientColor.xyz * tintedColor.rgb;
        lit = ambient + (lit - ambient) * shadow;

        return float4(lit, tintedColor.a);
    }
    """

    // MARK: - Canvas2D Textured (Textured 2D Drawing)

    /// MSL source code for the Canvas2D textured shader (used for image and text rendering).
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

    /// Built-in shader function name constants.
    public enum FunctionName {
        /// MSL function name for the blit vertex shader.
        public static let blitVertex = "metaphor_blitVertex"
        /// MSL function name for the blit fragment shader.
        public static let blitFragment = "metaphor_blitFragment"
        /// MSL function name for the flat-color vertex shader.
        public static let flatColorVertex = "metaphor_flatColorVertex"
        /// MSL function name for the flat-color fragment shader.
        public static let flatColorFragment = "metaphor_flatColorFragment"
        /// MSL function name for the vertex-color vertex shader.
        public static let vertexColorVertex = "metaphor_vertexColorVertex"
        /// MSL function name for the vertex-color fragment shader.
        public static let vertexColorFragment = "metaphor_vertexColorFragment"
        /// MSL function name for the lit vertex shader.
        public static let litVertex = "metaphor_litVertex"
        /// MSL function name for the lit fragment shader.
        public static let litFragment = "metaphor_litFragment"
        /// MSL function name for the Canvas2D vertex shader.
        public static let canvas2DVertex = "metaphor_canvas2DVertex"
        /// MSL function name for the Canvas2D fragment shader.
        public static let canvas2DFragment = "metaphor_canvas2DFragment"
        /// MSL function name for the Canvas2D difference blend fragment shader.
        public static let canvas2DDifferenceFragment = "metaphor_canvas2DDifferenceFragment"
        /// MSL function name for the Canvas2D exclusion blend fragment shader.
        public static let canvas2DExclusionFragment = "metaphor_canvas2DExclusionFragment"
        /// MSL function name for the Canvas3D vertex shader.
        public static let canvas3DVertex = "metaphor_canvas3DVertex"
        /// MSL function name for the Canvas3D fragment shader.
        public static let canvas3DFragment = "metaphor_canvas3DFragment"
        /// MSL function name for the Canvas2D textured vertex shader.
        public static let canvas2DTexturedVertex = "metaphor_canvas2DTexturedVertex"
        /// MSL function name for the Canvas2D textured fragment shader.
        public static let canvas2DTexturedFragment = "metaphor_canvas2DTexturedFragment"
        /// MSL function name for the Canvas2D textured difference blend fragment shader.
        public static let canvas2DTexturedDifferenceFragment = "metaphor_canvas2DTexturedDifferenceFragment"
        /// MSL function name for the Canvas2D textured exclusion blend fragment shader.
        public static let canvas2DTexturedExclusionFragment = "metaphor_canvas2DTexturedExclusionFragment"
        /// MSL function name for the Canvas3D textured vertex shader.
        public static let canvas3DTexturedVertex = "metaphor_canvas3DTexturedVertex"
        /// MSL function name for the Canvas3D textured fragment shader.
        public static let canvas3DTexturedFragment = "metaphor_canvas3DTexturedFragment"
        /// MSL function name for the Canvas2D instanced vertex shader.
        public static let canvas2DInstancedVertex = "metaphor_canvas2DInstancedVertex"
        /// MSL function name for the Canvas2D instanced fragment shader.
        public static let canvas2DInstancedFragment = "metaphor_canvas2DInstancedFragment"
        /// MSL function name for the Canvas2D instanced difference blend fragment shader.
        public static let canvas2DInstancedDifferenceFragment = "metaphor_canvas2DInstancedDifferenceFragment"
        /// MSL function name for the Canvas2D instanced exclusion blend fragment shader.
        public static let canvas2DInstancedExclusionFragment = "metaphor_canvas2DInstancedExclusionFragment"
    }
}
