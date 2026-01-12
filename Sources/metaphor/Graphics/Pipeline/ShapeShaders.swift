import Metal

/// 2D形状描画用のMetalシェーダーソースコード
/// ランタイムでコンパイルされる
public let shapeShaderSource = """
#include <metal_stdlib>
using namespace metal;

// 頂点データ構造体
struct ShapeVertex {
    float2 position;
    float4 color;
    float2 uv;
    uint shapeType;
    float param1;
};

// Uniform構造体
struct ShapeUniforms {
    float4x4 projection;
};

// 頂点シェーダー出力
struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    uint shapeType;
    float param1;
};

// 頂点シェーダー
vertex VertexOut shapeVertexShader(
    const device ShapeVertex* vertices [[buffer(0)]],
    constant ShapeUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    ShapeVertex v = vertices[vid];
    VertexOut out;

    out.position = uniforms.projection * float4(v.position, 0.0, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    out.shapeType = v.shapeType;
    out.param1 = v.param1;

    return out;
}

// フラグメントシェーダー
fragment float4 shapeFragmentShader(VertexOut in [[stage_in]]) {
    float4 color = in.color;

    // 楕円の場合: SDFでアンチエイリアス
    if (in.shapeType == 1) {
        // UV座標を-1〜1に変換
        float2 uv = in.uv * 2.0 - 1.0;
        float dist = length(uv);

        // アンチエイリアス幅を計算
        float aa = fwidth(dist) * 1.5;

        // 円の外側を透明に
        color.a *= 1.0 - smoothstep(1.0 - aa, 1.0, dist);
    }

    // 点の場合: 丸くする
    if (in.shapeType == 3) {
        float2 uv = in.uv * 2.0 - 1.0;
        float dist = length(uv);
        float aa = fwidth(dist) * 1.5;
        color.a *= 1.0 - smoothstep(1.0 - aa, 1.0, dist);
    }

    return color;
}
"""

/// シェーダーライブラリをコンパイルする
/// - Parameter device: Metalデバイス
/// - Returns: コンパイル済みライブラリ
public func compileShapeShaders(device: MTLDevice) throws -> MTLLibrary {
    let options = MTLCompileOptions()
    options.fastMathEnabled = true

    do {
        return try device.makeLibrary(source: shapeShaderSource, options: options)
    } catch {
        throw ShaderError.compilationFailed(error.localizedDescription)
    }
}

/// シェーダー関連のエラー
public enum ShaderError: Error, LocalizedError {
    case compilationFailed(String)
    case functionNotFound(String)
    case pipelineCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let message):
            return "Shader compilation failed: \(message)"
        case .functionNotFound(let name):
            return "Shader function not found: \(name)"
        case .pipelineCreationFailed(let message):
            return "Pipeline creation failed: \(message)"
        }
    }
}
