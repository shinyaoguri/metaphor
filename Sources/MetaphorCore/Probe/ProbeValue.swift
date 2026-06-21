import Foundation
import simd

/// AI エージェントが観測したい任意の値。`frame.json` の `custom` セクションに
/// JSON 値として書き出されます。
///
/// 構造化された値（ベクトル）は配列として、スカラー値はそれぞれの JSON 型で
/// シリアライズされます。
public enum ProbeValue: Sendable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)
    case vec2(Float, Float)
    case vec3(Float, Float, Float)
    case vec4(Float, Float, Float, Float)

    /// `frame.json` の `customTypes` に書き出す型タグ。
    ///
    /// `custom` の値はベクトルが裸の配列としてシリアライズされるため、
    /// AI エージェントは値だけでは `vec2` と「2 要素の配列」を区別できません。
    /// この型タグを併記することで、各 `probe()` 値の意図した型を明示します。
    var typeTag: String {
        switch self {
        case .double: return "double"
        case .int: return "int"
        case .string: return "string"
        case .bool: return "bool"
        case .vec2: return "vec2"
        case .vec3: return "vec3"
        case .vec4: return "vec4"
        }
    }
}

extension ProbeValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .bool(let v):
            try container.encode(v)
        case .vec2(let x, let y):
            try container.encode([x, y])
        case .vec3(let x, let y, let z):
            try container.encode([x, y, z])
        case .vec4(let x, let y, let z, let w):
            try container.encode([x, y, z, w])
        }
    }
}
