import Foundation

/// 外部（AI エージェント / GUI）からの書き込み結果。
public enum ParamSetOutcome: Sendable, Equatable {
    /// 適用された（クランプされた場合は `clampedTo` に実際の値の説明が入る）。
    case applied
    /// 宣言されていない名前。
    case unknownName
    /// 宣言された型と違う JSON 値。
    case typeMismatch
    /// `choices` に無い文字列。
    case rejectedChoice
}

/// `@Param` で宣言されたパラメータの実体を束ねるストア。
///
/// スケッチ 1 つにつき 1 つ（``SketchContext/params``）。人間の GUI（D2）と
/// 外部からの `set-request.json`（``ParameterPlugin``）は、どちらもこのストアを
/// 叩く**対称なクライアント**です。二重の状態を持ちません。
///
/// 競合ポリシーは **last-writer-wins**。値が変わるたびに ``revision`` が単調増加し、
/// `params.json` に書き出されるため、外部は「自分の書き込みが反映されたか」を
/// `appliedRequestId` と `revision` で確認できます。
@MainActor
public final class ParameterStore {
    /// 値が変わるたびに増える単調カウンタ。`params.json` にエコーされます。
    public private(set) var revision: Int = 0

    /// 宣言順のパラメータ名（`params.json` の並び順 = 宣言順で決定的）。
    public private(set) var names: [String] = []

    private var entries: [String: AnyParam] = [:]

    /// 直近に処理した set-request の id（`params.json` の `appliedRequestId`）。
    private(set) var appliedRequestId: String?

    /// 直近の set-request 処理で出た警告（拒否・クランプの理由）。
    private(set) var lastWarnings: [String] = []

    public init() {}

    /// パラメータが 1 つも宣言されていないか。
    public var isEmpty: Bool { entries.isEmpty }

    // MARK: - 宣言の発見と登録

    /// スケッチのプロパティを Mirror で走査し、`@Param` を宣言順に登録します。
    ///
    /// プロパティラッパーの格納名は `_radius` のようにアンダースコア始まりなので、
    /// 先頭の `_` を落とした `radius` を既定の名前にします（`@Param("myName")` の
    /// 明示名が優先）。継承したスケッチにも効くよう、基底クラス側から順に走査します。
    func discover(in object: Any) {
        var mirrors: [Mirror] = []
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            mirrors.append(current)
            mirror = current.superclassMirror
        }
        for current in mirrors.reversed() {
            for child in current.children {
                guard let param = child.value as? AnyParam else { continue }
                let fallback = (child.label ?? "").hasPrefix("_")
                    ? String((child.label ?? "").dropFirst())
                    : (child.label ?? "")
                register(param, name: param.explicitName ?? fallback)
            }
        }
    }

    /// パラメータを登録します。名前が空・重複のときは警告して無視します。
    func register(_ param: AnyParam, name: String) {
        guard !name.isEmpty else {
            metaphorDiagnostic("params: 名前を解決できない @Param を無視しました")
            return
        }
        guard entries[name] == nil else {
            metaphorDiagnostic("params: 名前が重複した @Param を無視しました: \(name)")
            return
        }
        entries[name] = param
        names.append(name)
        param.bind(name: name, store: self)
    }

    // MARK: - 読み書き

    /// 現在値を返します。未宣言の名前は `nil`。
    public func value(_ name: String) -> ParamValue? {
        entries[name]?.currentParamValue
    }

    /// 宣言情報（型・レンジ・選択肢）を返します。
    public func descriptor(_ name: String) -> ParamDescriptor? {
        entries[name].map { $0.descriptor(name: name) }
    }

    /// 外部クライアント（GUI / AI）からの書き込み。
    ///
    /// 宣言された型と一致しない値は拒否し、`min` / `max` があれば数値成分を
    /// クランプします。`choices` を持つ `string` は範囲外を拒否します。
    /// 適用されたときだけ ``revision`` が進みます。
    @discardableResult
    public func setValue(_ value: ParamValue, for name: String) -> ParamSetOutcome {
        guard let param = entries[name] else { return .unknownName }
        guard value.typeTag == param.typeTag else { return .typeMismatch }

        let descriptor = param.descriptor(name: name)
        if let choices = descriptor.choices, case .string(let s) = value, !choices.contains(s) {
            return .rejectedChoice
        }

        let clamped = ParameterStore.clamp(value, min: descriptor.min, max: descriptor.max)
        guard param.applyFromStore(clamped) else { return .typeMismatch }
        revision += 1
        return .applied
    }

    /// 数値成分を `min` / `max` の範囲へ収めます（範囲指定が無ければ素通し）。
    static func clamp(_ value: ParamValue, min lower: Double?, max upper: Double?) -> ParamValue {
        guard lower != nil || upper != nil, let components = value.numericComponents else {
            return value
        }
        let adjusted = components.map { component -> Double in
            var v = component
            if let lower { v = Swift.max(v, lower) }
            if let upper { v = Swift.min(v, upper) }
            return v
        }
        return adjusted == components ? value : value.withNumericComponents(adjusted)
    }

    /// `@Param` へのコードからの代入で呼ばれます（クランプなし・last-writer-wins）。
    func parameterDidChange(_ param: AnyParam) {
        revision += 1
    }

    // MARK: - ファイル入出力の橋渡し

    /// `params.json` へ書き出すスナップショットを組み立てます（宣言順）。
    func fileSnapshot() -> ParameterFile {
        ParameterFile(
            schemaVersion: ParameterFile.currentSchemaVersion,
            revision: revision,
            appliedRequestId: appliedRequestId,
            warnings: lastWarnings,
            params: names.compactMap { name in
                guard let param = entries[name] else { return nil }
                let descriptor = param.descriptor(name: name)
                return ParameterFile.Entry(
                    name: name,
                    type: descriptor.type,
                    value: param.currentParamValue,
                    min: descriptor.min,
                    max: descriptor.max,
                    choices: descriptor.choices
                )
            }
        )
    }

    /// 永続化された値を適用します（名前 + 型が一致するものだけ採用）。
    ///
    /// 起動時に 1 度だけ呼ばれ、`setup()` / `draw()` は最初から復元値を見ます。
    /// `revision` は永続ファイルの値を引き継ぎ、以後も単調増加します。
    func applyPersisted(_ file: ParameterFile) {
        for entry in file.params {
            guard let param = entries[entry.name] else { continue }
            guard entry.type == param.typeTag, entry.value.typeTag == param.typeTag else {
                metaphorDiagnostic("params: 型が変わったため永続値を破棄しました: \(entry.name)")
                continue
            }
            let descriptor = param.descriptor(name: entry.name)
            if let choices = descriptor.choices, case .string(let s) = entry.value,
               !choices.contains(s) {
                metaphorDiagnostic("params: choices に無い永続値を破棄しました: \(entry.name)=\(s)")
                continue
            }
            param.applyFromStore(
                ParameterStore.clamp(entry.value, min: descriptor.min, max: descriptor.max)
            )
        }
        revision = Swift.max(revision, file.revision)
    }

    /// set-request を適用し、`appliedRequestId` と警告を更新します。
    ///
    /// - Returns: 適用された名前の数（0 でも `appliedRequestId` は更新する。
    ///   外部は「届いたが全部拒否された」ことを警告から判別できる）。
    @discardableResult
    func apply(_ request: ParameterSetRequest) -> Int {
        var warnings: [String] = []
        var applied = 0
        // 名前順に処理して、同一リクエスト内の適用順を決定的にする。
        for name in request.values.keys.sorted() {
            guard let raw = request.values[name] else { continue }
            guard let param = entries[name] else {
                warnings.append("unknown parameter '\(name)'")
                continue
            }
            guard let value = ParamValue.from(json: raw, typeTag: param.typeTag) else {
                warnings.append("type mismatch for '\(name)' (expected \(param.typeTag))")
                continue
            }
            switch setValue(value, for: name) {
            case .applied:
                applied += 1
            case .rejectedChoice:
                let choices = param.descriptor(name: name).choices ?? []
                warnings.append(
                    "value not in choices for '\(name)' (allowed: \(choices.joined(separator: ", ")))"
                )
            case .typeMismatch:
                warnings.append("type mismatch for '\(name)' (expected \(param.typeTag))")
            case .unknownName:
                warnings.append("unknown parameter '\(name)'")
            }
        }
        appliedRequestId = request.id
        lastWarnings = warnings
        return applied
    }

    /// 起動時の書き出しで revision を 1 つ進めます。
    ///
    /// プロセスが変われば宣言そのもの（新しい `@Param`・レンジの変更）が変わり得るため、
    /// 「`params.json` の内容が変わったら revision も変わる」という外部の期待を保ちます。
    func bumpRevisionForStartup() {
        revision += 1
    }
}
