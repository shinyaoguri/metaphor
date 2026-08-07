import Foundation
import simd

/// Parameter Store が保持できる値の型セット（v1）。
///
/// `ProbeValue` と同じ「値 + 型タグ」の組み立て方を踏襲します。JSON では値だけが
/// 裸で書かれる（`vec2` は 2 要素配列）ため、`params.json` の各エントリは
/// `type` フィールドで型タグを併記します。
///
/// 型セットは `float` / `int` / `bool` / `string` / `color` / `vec2` / `vec3`。
/// `Float` と `Double` はどちらも `float` タグに写ります（wire は JSON number）。
public enum ParamValue: Sendable, Equatable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case string(String)
    case color(Float, Float, Float, Float)
    case vec2(Float, Float)
    case vec3(Float, Float, Float)

    /// `params.json` の `type` フィールドに書き出す型タグ。
    public var typeTag: String {
        switch self {
        case .float: return "float"
        case .int: return "int"
        case .bool: return "bool"
        case .string: return "string"
        case .color: return "color"
        case .vec2: return "vec2"
        case .vec3: return "vec3"
        }
    }

    /// 数値成分（`min` / `max` のクランプ対象）。数値でない型は `nil`。
    var numericComponents: [Double]? {
        switch self {
        case .float(let v): return [v]
        case .int(let v): return [Double(v)]
        case .color(let r, let g, let b, let a): return [Double(r), Double(g), Double(b), Double(a)]
        case .vec2(let x, let y): return [Double(x), Double(y)]
        case .vec3(let x, let y, let z): return [Double(x), Double(y), Double(z)]
        case .bool, .string: return nil
        }
    }

    /// 数値成分を差し替えた同型の値を返します（クランプ結果の再構成用）。
    func withNumericComponents(_ c: [Double]) -> ParamValue {
        switch self {
        case .float: return .float(c[0])
        case .int: return .int(Int(c[0].rounded()))
        case .color: return .color(Float(c[0]), Float(c[1]), Float(c[2]), Float(c[3]))
        case .vec2: return .vec2(Float(c[0]), Float(c[1]))
        case .vec3: return .vec3(Float(c[0]), Float(c[1]), Float(c[2]))
        case .bool, .string: return self
        }
    }
}

extension ParamValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .float(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .color(let r, let g, let b, let a): try container.encode([r, g, b, a])
        case .vec2(let x, let y): try container.encode([x, y])
        case .vec3(let x, let y, let z): try container.encode([x, y, z])
        }
    }
}

extension ParamValue {
    /// `JSONSerialization` が返す素の JSON 値を、**期待する型タグ**に沿って解釈します。
    ///
    /// set-request / params.json の値は型情報を持たない裸の JSON なので、宣言済み
    /// パラメータの型を正典として読み取ります（型が合わない値は `nil` = 拒否）。
    /// 数値は JSON 上 `Int` / `Double` のどちらにもなり得るため、`NSNumber` 経由で
    /// 受けます（`bool` との取り違えを避けるため `Bool` は明示的に先に判定）。
    static func from(json: Any, typeTag: String) -> ParamValue? {
        switch typeTag {
        case "bool":
            guard let n = json as? NSNumber, isBoolean(n) else { return nil }
            return .bool(n.boolValue)
        case "string":
            guard let s = json as? String else { return nil }
            return .string(s)
        case "float":
            guard let d = number(json) else { return nil }
            return .float(d)
        case "int":
            guard let d = number(json) else { return nil }
            return .int(Int(d.rounded()))
        case "color":
            guard let a = floatArray(json, count: 4) else { return nil }
            return .color(a[0], a[1], a[2], a[3])
        case "vec2":
            guard let a = floatArray(json, count: 2) else { return nil }
            return .vec2(a[0], a[1])
        case "vec3":
            guard let a = floatArray(json, count: 3) else { return nil }
            return .vec3(a[0], a[1], a[2])
        default:
            return nil
        }
    }

    /// JSON の数値を `Double` として取り出します（`true` / `false` は数値として扱わない）。
    private static func number(_ json: Any) -> Double? {
        guard let n = json as? NSNumber, !isBoolean(n) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// `NSNumber` が真偽値か（`CFBoolean` か）を判定します。
    ///
    /// `JSONSerialization` は数値も真偽値も `NSNumber` で返し、しかも Swift の
    /// `is Bool` は **0 と 1 の数値まで true** になります（NSNumber のブリッジ）。
    /// そのため `[1, 0.5, 0.25, 1]` の `1` が真偽値と誤判定され、色やベクトルが
    /// 丸ごと拒否されました。型の判別は必ず `CFBoolean` で行います。
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func floatArray(_ json: Any, count: Int) -> [Float]? {
        guard let array = json as? [Any], array.count == count else { return nil }
        var out: [Float] = []
        out.reserveCapacity(count)
        for element in array {
            guard let d = number(element) else { return nil }
            out.append(Float(d))
        }
        return out
    }
}

// MARK: - Swift 型 ⇄ ParamValue

/// `@Param` で宣言できる Swift 型。
///
/// v1 の対応表: `Float` / `Double` → `float`、`Int` → `int`、`Bool` → `bool`、
/// `String` → `string`、``Color`` → `color`、`SIMD2<Float>`（``Vec2``）→ `vec2`、
/// `SIMD3<Float>`（``Vec3``）→ `vec3`。
public protocol ParamRepresentable {
    /// この型が写る型タグ（`params.json` の `type`）。
    static var paramTypeTag: String { get }

    /// ストアが保持する値表現へ変換します。
    var paramValue: ParamValue { get }

    /// ストアの値表現から復元します。型が合わないときは `nil`。
    init?(paramValue: ParamValue)
}

extension Float: ParamRepresentable {
    public static var paramTypeTag: String { "float" }
    public var paramValue: ParamValue { .float(Double(self)) }
    public init?(paramValue: ParamValue) {
        guard case .float(let v) = paramValue else { return nil }
        self = Float(v)
    }
}

extension Double: ParamRepresentable {
    public static var paramTypeTag: String { "float" }
    public var paramValue: ParamValue { .float(self) }
    public init?(paramValue: ParamValue) {
        guard case .float(let v) = paramValue else { return nil }
        self = v
    }
}

extension Int: ParamRepresentable {
    public static var paramTypeTag: String { "int" }
    public var paramValue: ParamValue { .int(self) }
    public init?(paramValue: ParamValue) {
        guard case .int(let v) = paramValue else { return nil }
        self = v
    }
}

extension Bool: ParamRepresentable {
    public static var paramTypeTag: String { "bool" }
    public var paramValue: ParamValue { .bool(self) }
    public init?(paramValue: ParamValue) {
        guard case .bool(let v) = paramValue else { return nil }
        self = v
    }
}

extension String: ParamRepresentable {
    public static var paramTypeTag: String { "string" }
    public var paramValue: ParamValue { .string(self) }
    public init?(paramValue: ParamValue) {
        guard case .string(let v) = paramValue else { return nil }
        self = v
    }
}

extension Color: ParamRepresentable {
    public static var paramTypeTag: String { "color" }
    public var paramValue: ParamValue { .color(r, g, b, a) }
    public init?(paramValue: ParamValue) {
        guard case .color(let r, let g, let b, let a) = paramValue else { return nil }
        self.init(r: r, g: g, b: b, a: a)
    }
}

extension SIMD2: ParamRepresentable where Scalar == Float {
    public static var paramTypeTag: String { "vec2" }
    public var paramValue: ParamValue { .vec2(x, y) }
    public init?(paramValue: ParamValue) {
        guard case .vec2(let x, let y) = paramValue else { return nil }
        self.init(x, y)
    }
}

extension SIMD3: ParamRepresentable where Scalar == Float {
    public static var paramTypeTag: String { "vec3" }
    public var paramValue: ParamValue { .vec3(x, y, z) }
    public init?(paramValue: ParamValue) {
        guard case .vec3(let x, let y, let z) = paramValue else { return nil }
        self.init(x, y, z)
    }
}
