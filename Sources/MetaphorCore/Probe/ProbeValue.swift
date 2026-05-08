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
