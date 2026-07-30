import Foundation

/// JSON データを動的に表現する値型。
///
/// Processing の `JSONObject` / `JSONArray` に相当します。``Sketch/loadJSON(_:)`` の
/// 戻り値として、スキーマを Swift の型で定義せずに JSON を読み書きできます。
///
/// subscript は失敗しても `.null` を返すため、深い階層へ安全にチェーンできます:
///
/// ```swift
/// let json = try loadJSON("data.json")
/// for bubble in json["bubbles"].arrayValue {
///     let x = bubble["position"]["x"].doubleValue
///     let label = bubble["label"].stringValue
/// }
/// ```
///
/// 構築はリテラルから直接行えます:
///
/// ```swift
/// var bubble: JSONValue = [
///     "position": ["x": 100, "y": 200],
///     "diameter": 43.5,
///     "label": "Happy",
/// ]
/// bubble["label"] = "Sad"
/// ```
///
/// スキーマが既知の場合は `Codable` 版 ``Sketch/loadJSON(_:as:)`` の利用を推奨します。
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - パース / シリアライズ

    /// JSON テキスト（UTF-8 データ）をパースします。
    ///
    /// - Parameter data: JSON ドキュメントのバイト列
    /// - Throws: ``MetaphorError/data(_:)`` パースに失敗した場合
    public init(data: Data) throws {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw MetaphorError.data(.parseFailed(detail: "invalid JSON: \(error.localizedDescription)"))
        }
        self = Self.fromJSONObject(raw)
    }

    /// JSON テキスト（文字列）をパースします。
    ///
    /// - Parameter string: JSON ドキュメント文字列
    /// - Throws: ``MetaphorError/data(_:)`` パースに失敗した場合
    public init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }

    /// JSON テキストとしてシリアライズします。
    ///
    /// - Parameter pretty: `true` の場合はインデント付きで整形（キーはソートされ決定的）
    /// - Returns: UTF-8 の JSON データ
    public func serialized(pretty: Bool = true) -> Data {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
        if pretty { options.insert(.prettyPrinted) }
        // toJSONObject() は JSON 互換値のみを返すため、シリアライズは失敗しない
        return (try? JSONSerialization.data(withJSONObject: toJSONObject(), options: options)) ?? Data()
    }

    private static func fromJSONObject(_ raw: Any) -> JSONValue {
        switch raw {
        case is NSNull:
            return .null
        case let number as NSNumber:
            // JSONSerialization は Bool も NSNumber で返すため、CFType で判別する
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map(fromJSONObject))
        case let dict as [String: Any]:
            return .object(dict.mapValues(fromJSONObject))
        default:
            return .null
        }
    }

    private func toJSONObject() -> Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .number(let n): n
        case .string(let s): s
        case .array(let a): a.map { $0.toJSONObject() }
        case .object(let o): o.mapValues { $0.toJSONObject() }
        }
    }

    // MARK: - subscript アクセス

    /// オブジェクトのキーで値を取得・設定します。オブジェクトでない場合の取得は `.null`。
    ///
    /// 設定時、自身がオブジェクトでなければオブジェクトへ置き換わります。
    public subscript(key: String) -> JSONValue {
        get {
            guard case .object(let dict) = self else { return .null }
            return dict[key] ?? .null
        }
        set {
            var dict: [String: JSONValue] = if case .object(let d) = self { d } else { [:] }
            dict[key] = newValue
            self = .object(dict)
        }
    }

    /// 配列のインデックスで値を取得・設定します。配列でない・範囲外の取得は `.null`。
    ///
    /// 設定時の範囲外インデックスは無視されます（警告のみ）。
    public subscript(index: Int) -> JSONValue {
        get {
            guard case .array(let array) = self, array.indices.contains(index) else { return .null }
            return array[index]
        }
        set {
            guard case .array(var array) = self, array.indices.contains(index) else {
                metaphorWarning("JSONValue: cannot set index \(index) (not an array or out of bounds)")
                return
            }
            array[index] = newValue
            self = .array(array)
        }
    }

    // MARK: - 配列操作

    /// 配列の末尾に値を追加します。自身が `.null` の場合は単一要素の配列になります。
    ///
    /// 配列以外（`.null` 除く）への追加は無視されます（警告のみ）。
    public mutating func append(_ value: JSONValue) {
        switch self {
        case .array(var array):
            array.append(value)
            self = .array(array)
        case .null:
            self = .array([value])
        default:
            metaphorWarning("JSONValue: cannot append to non-array value")
        }
    }

    /// 配列から指定インデックスの要素を削除します。
    ///
    /// 配列でない・範囲外の場合は無視されます（警告のみ）。
    public mutating func remove(at index: Int) {
        guard case .array(var array) = self, array.indices.contains(index) else {
            metaphorWarning("JSONValue: cannot remove index \(index) (not an array or out of bounds)")
            return
        }
        array.remove(at: index)
        self = .array(array)
    }

    // MARK: - 型付きアクセサ（optional）

    /// 文字列なら値、それ以外は nil
    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// 数値なら Double 値、それ以外は nil
    public var double: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// 数値なら Float 値、それ以外は nil
    public var float: Float? { double.map(Float.init) }

    /// 数値なら整数へ切り捨てた値、それ以外は nil
    public var int: Int? { double.map(Int.init) }

    /// 真偽値なら値、それ以外は nil
    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// 配列なら要素、それ以外は nil
    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// オブジェクトなら辞書、それ以外は nil
    public var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// `.null` かどうか
    public var isNull: Bool { self == .null }

    // MARK: - 型付きアクセサ（デフォルト値つき）

    /// 文字列値（それ以外は空文字列）
    public var stringValue: String { string ?? "" }

    /// Double 値（それ以外は 0）
    public var doubleValue: Double { double ?? 0 }

    /// Float 値（それ以外は 0）
    public var floatValue: Float { float ?? 0 }

    /// 整数値（それ以外は 0）
    public var intValue: Int { int ?? 0 }

    /// 真偽値（それ以外は false）
    public var boolValue: Bool { bool ?? false }

    /// 配列要素（それ以外は空配列）
    public var arrayValue: [JSONValue] { array ?? [] }

    /// オブジェクト辞書（それ以外は空辞書）
    public var objectValue: [String: JSONValue] { object ?? [:] }

    /// 配列・オブジェクトの要素数（それ以外は 0）
    public var count: Int {
        switch self {
        case .array(let a): a.count
        case .object(let o): o.count
        default: 0
        }
    }
}

// MARK: - 値からの構築

extension JSONValue {
    /// 浮動小数点値から `.number` を構築します。
    public init(_ value: some BinaryFloatingPoint) { self = .number(Double(value)) }

    /// 整数値から `.number` を構築します。
    public init(_ value: some BinaryInteger) { self = .number(Double(value)) }

    /// 文字列から `.string` を構築します。
    public init(_ value: String) { self = .string(value) }

    /// 真偽値から `.bool` を構築します。
    public init(_ value: Bool) { self = .bool(value) }
}

// MARK: - リテラル構築

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}
