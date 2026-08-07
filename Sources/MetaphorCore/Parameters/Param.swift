import Foundation

/// パラメータの宣言情報（名前・型タグ・レンジ・選択肢）。
///
/// `params.json` の各エントリのメタ情報になり、外部ツール（GUI / AI）が
/// 「どんな値を書いてよいか」を知るための唯一の情報源です。
public struct ParamDescriptor: Sendable, Equatable {
    /// ストア内の一意な名前。既定はプロパティ名（`@Param var radius` → `radius`）。
    public let name: String
    /// 型タグ（`float` / `int` / `bool` / `string` / `color` / `vec2` / `vec3`）。
    public let type: String
    /// 下限（数値型のみ。外部からの書き込みはこの範囲にクランプされる）。
    public let min: Double?
    /// 上限（同上）。
    public let max: Double?
    /// `string` 型の合法値。指定時、範囲外の値は拒否される。
    public let choices: [String]?
}

/// 型を伏せた `@Param` への参照。``ParameterStore`` が登録・読み書きに使います。
@MainActor
protocol AnyParam: AnyObject {
    /// 明示名（`@Param("myName")`）。未指定なら `nil` で、Mirror が見つけた
    /// プロパティ名が採用される。
    var explicitName: String? { get }

    /// ストアへ登録された名前。未登録の間は `nil`。
    var registeredName: String? { get }

    /// 型タグ。
    var typeTag: String { get }

    /// 現在値。
    var currentParamValue: ParamValue { get }

    /// 宣言情報（登録名で組み立てる）。
    func descriptor(name: String) -> ParamDescriptor

    /// ストアへ登録します（名前の確定 + 変更通知先の設定）。
    func bind(name: String, store: ParameterStore)

    /// ストア経由で値を差し替えます。型が合わなければ `false`（呼び出し側が拒否を記録）。
    ///
    /// この経路は変更通知を発火しません（ストア側が revision を進めるため）。
    @discardableResult
    func applyFromStore(_ value: ParamValue) -> Bool
}

/// スケッチのプロパティを **Parameter Store のパラメータとして宣言**する
/// プロパティラッパー。
///
/// ```swift
/// @main final class MySketch: Sketch {
///     @Param(min: 10, max: 200) var radius: Float = 50
///     @Param var showGrid: Bool = true
///     @Param(choices: ["add", "multiply"]) var mode: String = "add"
///
///     func draw() {
///         circle(width / 2, height / 2, radius)
///     }
/// }
/// ```
///
/// 宣言したパラメータは:
///
/// - `.metaphor/params/params.json` に**永続化**され、次回起動時に復元される
///   （`setup()` / `draw()` は最初から復元値を見る）
/// - `.metaphor/params/set-request.json` を書くことで**外部（AI エージェント / ツール）から
///   変更**できる。再ビルド不要で次フレームに反映される
///
/// 有効化は自動です（`@Param` が 1 つでもあれば `ParameterPlugin` が登録される）。
/// 素の `swift run` でも永続化は効きます。オプトアウトは環境変数 `METAPHOR_PARAMS=0`。
///
/// - Note: 値の読み書きは通常のプロパティと同じで、ストア未登録でも動作します
///   （その場合は単なる格納プロパティとして振る舞う）。
@MainActor
@propertyWrapper
public final class Param<Value: ParamRepresentable>: AnyParam {
    private var storage: Value
    private weak var store: ParameterStore?

    let explicitName: String?
    private(set) var registeredName: String?

    /// 下限（数値型のみ）。
    public let min: Double?
    /// 上限（数値型のみ）。
    public let max: Double?
    /// `string` の合法値。
    public let choices: [String]?

    /// - Parameters:
    ///   - wrappedValue: コード上の既定値。永続値があれば起動時に上書きされる。
    ///   - name: ストア内の名前。省略時はプロパティ名（`_radius` → `radius`）。
    ///   - min: 下限。外部からの書き込みをクランプする（コードからの代入は素通し）。
    ///   - max: 上限。
    ///   - choices: `string` 型の合法値。範囲外の書き込みは拒否される。
    public init(
        wrappedValue: Value,
        _ name: String? = nil,
        min: Double? = nil,
        max: Double? = nil,
        choices: [String]? = nil
    ) {
        self.storage = wrappedValue
        self.explicitName = name
        self.min = min
        self.max = max
        self.choices = choices
    }

    public var wrappedValue: Value {
        get { storage }
        set {
            storage = newValue
            store?.parameterDidChange(self)
        }
    }

    /// `$radius` で宣言情報（レンジ・選択肢・登録名）へアクセスします。
    public var projectedValue: Param<Value> { self }

    // MARK: - AnyParam

    var typeTag: String { Value.paramTypeTag }

    var currentParamValue: ParamValue { storage.paramValue }

    func descriptor(name: String) -> ParamDescriptor {
        ParamDescriptor(name: name, type: Value.paramTypeTag, min: min, max: max, choices: choices)
    }

    func bind(name: String, store: ParameterStore) {
        self.registeredName = name
        self.store = store
    }

    @discardableResult
    func applyFromStore(_ value: ParamValue) -> Bool {
        guard let converted = Value(paramValue: value) else { return false }
        storage = converted
        return true
    }
}
