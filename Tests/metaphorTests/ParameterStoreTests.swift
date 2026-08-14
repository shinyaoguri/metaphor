import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - テスト用の宣言ホスト

/// `@Param` を宣言したスケッチの代役。`ParameterStore.discover(in:)` は
/// Mirror で走査するだけなので、GPU / ウィンドウ無しで試験できる。
@MainActor
private final class ParamHost {
    @Param(min: 10, max: 200) var radius: Float = 50
    @Param var showGrid: Bool = true
    @Param("blend", choices: ["add", "multiply"]) var mode: String = "add"
    @Param var tint: Color = Color(r: 1, g: 1, b: 1, alpha: 1)
    @Param var origin: Vec2 = Vec2(0, 0)
    @Param(min: 1, max: 512) var count: Int = 4
}

/// 継承したスケッチでも基底クラスの宣言が拾えることの確認用。
@MainActor
private class BaseHost {
    @Param var inherited: Float = 1
}

@MainActor
private final class DerivedHost: BaseHost {
    @Param var own: Float = 2
}

// MARK: - 宣言と読み書き

@Suite("Parameter Store")
@MainActor
struct ParameterStoreTests {

    private func makeStore(_ host: Any) -> ParameterStore {
        let store = ParameterStore()
        store.discover(in: host)
        return store
    }

    @Test("プロパティ名が既定のパラメータ名になり、明示名が優先される")
    func discoveryNamesProperties() {
        let store = makeStore(ParamHost())
        // 宣言順を保つ（params.json の並びが決定的であること）。
        #expect(store.names == ["radius", "showGrid", "blend", "tint", "origin", "count"])
        #expect(store.descriptor("radius")?.type == "float")
        #expect(store.descriptor("blend")?.choices == ["add", "multiply"])
        #expect(store.descriptor("mode") == nil)  // 明示名で置き換わっている
    }

    @Test("基底クラスの @Param も基底 → 派生の順で登録される")
    func discoveryWalksSuperclasses() {
        let store = makeStore(DerivedHost())
        #expect(store.names == ["inherited", "own"])
    }

    @Test("宣言が無ければストアは空（プラグインも自動登録されない）")
    func emptyStoreWhenNoParams() {
        final class NoParams { var plain = 1 }
        let store = makeStore(NoParams())
        #expect(store.isEmpty)
    }

    @Test("外部からの書き込みが値に反映され、revision が進む")
    func setValueAppliesAndBumpsRevision() {
        let host = ParamHost()
        let store = makeStore(host)
        let before = store.revision

        #expect(store.setValue(.float(120), for: "radius") == .applied)
        #expect(host.radius == 120)
        #expect(store.revision == before + 1)
        #expect(store.value("radius") == .float(120))
    }

    @Test("min / max の範囲外はクランプされる")
    func setValueClampsToRange() {
        let host = ParamHost()
        let store = makeStore(host)

        #expect(store.setValue(.float(1_000), for: "radius") == .applied)
        #expect(host.radius == 200)
        #expect(store.setValue(.float(-5), for: "radius") == .applied)
        #expect(host.radius == 10)
    }

    @Test("型が違う値・未知の名前・choices 外は拒否される")
    func setValueRejectsInvalid() {
        let host = ParamHost()
        let store = makeStore(host)
        let before = store.revision

        #expect(store.setValue(.bool(true), for: "radius") == .typeMismatch)
        #expect(store.setValue(.float(1), for: "nonexistent") == .unknownName)
        #expect(store.setValue(.string("subtract"), for: "blend") == .rejectedChoice)
        #expect(host.radius == 50)
        #expect(host.mode == "add")
        // 拒否された書き込みでは revision は動かない（外部が「変化なし」を判別できる）。
        #expect(store.revision == before)
    }

    @Test("コードからの代入でも revision が進む（GUI / AI と同じストア）")
    func codeAssignmentBumpsRevision() {
        let host = ParamHost()
        let store = makeStore(host)
        let before = store.revision

        host.radius = 77
        #expect(store.revision == before + 1)
        #expect(store.value("radius") == .float(77))
    }

    @Test("set-request は名前順に適用され、拒否理由が warnings に載る")
    func applySetRequestCollectsWarnings() {
        let host = ParamHost()
        let store = makeStore(host)

        let request = ParameterSetRequest(
            id: "req-1",
            values: [
                "radius": 120.5,
                "showGrid": false,
                "blend": "subtract",     // choices 外 → 拒否
                "count": true,           // 型不一致 → 拒否
                "nope": 1,               // 未知 → 拒否
            ]
        )
        let applied = store.apply(request)

        #expect(applied == 2)
        #expect(host.radius == 120.5)
        #expect(host.showGrid == false)
        #expect(host.mode == "add")
        #expect(host.count == 4)
        let warnings = store.lastWarnings.joined(separator: "\n")
        #expect(warnings.contains("blend"))
        #expect(warnings.contains("count"))
        #expect(warnings.contains("nope"))
        #expect(store.appliedRequestId == "req-1")
    }

    @Test("set-request の値は宣言された型で解釈される（vec2 / color は配列）")
    func applySetRequestDecodesCompositeTypes() {
        let host = ParamHost()
        let store = makeStore(host)

        store.apply(ParameterSetRequest(
            id: "req-2",
            values: ["origin": [320, 180], "tint": [1, 0.5, 0.25, 1]]
        ))

        #expect(host.origin == Vec2(320, 180))
        #expect(host.tint == Color(r: 1, g: 0.5, b: 0.25, alpha: 1))
    }

    @Test("永続値は名前 + 型が一致するものだけ復元される")
    func persistedValuesRestoreByNameAndType() throws {
        let host = ParamHost()
        let store = makeStore(host)

        let json = """
        {
          "schemaVersion": 1,
          "revision": 7,
          "warnings": [],
          "params": [
            {"name": "radius", "type": "float", "value": 150},
            {"name": "showGrid", "type": "int", "value": 3},
            {"name": "gone", "type": "float", "value": 1},
            {"name": "count", "type": "int", "value": 9999}
          ]
        }
        """
        let file = try #require(ParameterFile.decode(from: Data(json.utf8)))
        store.applyPersisted(file)

        #expect(host.radius == 150)          // 復元される
        #expect(host.showGrid == true)       // 型が違うので破棄（既定値のまま）
        #expect(host.count == 512)           // 復元時も min/max でクランプ
        #expect(store.revision == 7)         // revision は永続値を引き継ぐ
    }

    @Test("壊れた params.json / 未知の schemaVersion は無視される")
    func decodeRejectsBrokenFiles() {
        #expect(ParameterFile.decode(from: Data("{ not json".utf8)) == nil)
        #expect(ParameterFile.decode(
            from: Data(#"{"schemaVersion":99,"revision":1,"warnings":[],"params":[]}"#.utf8)
        ) == nil)
        #expect(ParameterSetRequest.decode(from: Data(#"{"values":{}}"#.utf8)) == nil)
    }
}

// MARK: - ファイル契約（.metaphor/params/）

@Suite("Parameter Store files", .serialized)
@MainActor
struct ParameterPluginFileTests {

    /// 書き出しは専用キュー上で非同期に行われるため、出現/更新をポーリングで待つ。
    private func waitForFile(_ url: URL, timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private func waitForParams(
        _ url: URL, until predicate: (ParameterFile) -> Bool, timeout: TimeInterval = 3.0
    ) -> ParameterFile? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let file = ParameterFile.decode(from: data),
               predicate(file) {
                return file
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func makePlugin(in dir: URL) -> ParameterPlugin {
        ParameterPlugin(config: ParameterStoreConfig(
            directory: dir.path,
            setRequestFilePath: dir.appendingPathComponent("set-request.json").path,
            writeDebounce: 0.05
        ))
    }

    @Test("attach で宣言（型・レンジ・choices）が params.json に書き出される")
    func attachWritesDeclarations() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let host = ParamHost()
            let store = ParameterStore()
            makePlugin(in: dir).attach(store: store, sketch: host)

            let paramsURL = dir.appendingPathComponent("params.json")
            #expect(waitForFile(paramsURL))

            let file = try #require(ParameterFile.decode(from: try Data(contentsOf: paramsURL)))
            #expect(file.schemaVersion == ParameterFile.currentSchemaVersion)
            #expect(file.params.map(\.name) == ["radius", "showGrid", "blend", "tint", "origin", "count"])
            let radius = try #require(file.params.first)
            #expect(radius.min == 10)
            #expect(radius.max == 200)
            #expect(file.params.first { $0.name == "blend" }?.choices == ["add", "multiply"])
        }
    }

    @Test("前回の値が次の起動で復元される（setup() 前に適用済み）")
    func persistedValuesSurviveRestart() {
        TempFileHelper.withTemporaryDirectory { dir in
            // 1 回目の起動: 値を変えて書き出す。
            let first = ParamHost()
            let firstStore = ParameterStore()
            let firstPlugin = makePlugin(in: dir)
            firstPlugin.attach(store: firstStore, sketch: first)
            first.radius = 137
            firstPlugin.tick(now: 0)
            firstPlugin.tick(now: 10)  // デバウンス経過

            let paramsURL = dir.appendingPathComponent("params.json")
            #expect(waitForParams(paramsURL, until: { file in
                file.params.contains { $0.name == "radius" && $0.value == .float(137) }
            }) != nil)

            // 2 回目の起動: 同じディレクトリで attach すると復元される。
            let second = ParamHost()
            #expect(second.radius == 50)  // コード既定値
            makePlugin(in: dir).attach(store: ParameterStore(), sketch: second)
            #expect(second.radius == 137)
        }
    }

    @Test("set-request.json が次の tick で適用され、id と revision がエコーされる")
    func setRequestIsAppliedAndEchoed() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let host = ParamHost()
            let store = ParameterStore()
            let plugin = makePlugin(in: dir)
            plugin.attach(store: store, sketch: host)

            let requestURL = dir.appendingPathComponent("set-request.json")
            let payload: [String: Any] = ["id": "set-1", "values": ["radius": 88, "blend": "multiply"]]
            try JSONSerialization.data(withJSONObject: payload).write(to: requestURL)

            plugin.tick(now: 1)
            #expect(host.radius == 88)
            #expect(host.mode == "multiply")

            let file = try #require(waitForParams(
                dir.appendingPathComponent("params.json"),
                until: { $0.appliedRequestId == "set-1" }
            ))
            #expect(file.revision == store.revision)
            #expect(file.warnings.isEmpty)
        }
    }

    @Test("同じ id のリクエストは再処理されない")
    func setRequestIsNotReprocessed() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let host = ParamHost()
            let plugin = makePlugin(in: dir)
            plugin.attach(store: ParameterStore(), sketch: host)

            let requestURL = dir.appendingPathComponent("set-request.json")
            let payload: [String: Any] = ["id": "same", "values": ["radius": 88]]
            try JSONSerialization.data(withJSONObject: payload).write(to: requestURL)
            plugin.tick(now: 1)
            #expect(host.radius == 88)

            // コードで書き換えてから、同じ id のファイルを触り直す（mtime だけ更新）。
            host.radius = 20
            try JSONSerialization.data(withJSONObject: payload).write(to: requestURL)
            plugin.tick(now: 2)
            #expect(host.radius == 20)
        }
    }

    @Test("拒否された set-request も appliedRequestId と warnings で応答する")
    func rejectedSetRequestStillEchoes() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let host = ParamHost()
            let plugin = makePlugin(in: dir)
            plugin.attach(store: ParameterStore(), sketch: host)

            let requestURL = dir.appendingPathComponent("set-request.json")
            let payload: [String: Any] = ["id": "bad-1", "values": ["radius": "not a number"]]
            try JSONSerialization.data(withJSONObject: payload).write(to: requestURL)
            plugin.tick(now: 1)

            let file = try #require(waitForParams(
                dir.appendingPathComponent("params.json"),
                until: { $0.appliedRequestId == "bad-1" }
            ))
            #expect(file.warnings.contains { $0.contains("radius") })
            #expect(host.radius == 50)
        }
    }

    @Test("変更が無いフレームでは params.json を書き直さない")
    func idleTicksDoNotRewrite() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let plugin = makePlugin(in: dir)
            plugin.attach(store: ParameterStore(), sketch: ParamHost())
            let paramsURL = dir.appendingPathComponent("params.json")
            #expect(waitForFile(paramsURL))
            let before = try FileManager.default.attributesOfItem(atPath: paramsURL.path)[.modificationDate] as? Date

            for tick in 0..<10 { plugin.tick(now: Double(tick)) }
            Thread.sleep(forTimeInterval: 0.2)

            let after = try FileManager.default.attributesOfItem(atPath: paramsURL.path)[.modificationDate] as? Date
            #expect(before == after)
        }
    }

    @Test("METAPHOR_PARAMS=0 と宣言ゼロでは自動登録されない")
    func autoRegistrationRespectsOptOut() {
        final class NoParams: Sketch {
            init() {}
            func draw() {}
        }
        #expect(ParameterPlugin.shouldAutoRegister(sketch: NoParams(), env: [:]) == false)

        final class WithParams: Sketch {
            init() {}
            @Param var radius: Float = 1
            func draw() {}
        }
        #expect(ParameterPlugin.shouldAutoRegister(sketch: WithParams(), env: [:]) == true)
        #expect(ParameterPlugin.shouldAutoRegister(
            sketch: WithParams(), env: ["METAPHOR_PARAMS": "0"]
        ) == false)
    }
}

// MARK: - wire スキーマ適合（producer 側）

@Suite("Parameter Store wire-schema conformance")
@MainActor
struct ParameterSchemaConformanceTests {

    /// ParameterFileWriter と同一の encoder 設定。
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("params.json (full) は実 ParameterFile と構造一致する")
    func paramsFullMatchesExample() throws {
        let file = ParameterFile(
            schemaVersion: 1,
            revision: 42,
            appliedRequestId: "01J2ZK9M3QW8XV4T7YB0C5D6EF",
            warnings: ["unknown parameter 'radiuss'"],
            params: [
                .init(name: "radius", type: "float", value: .float(120), min: 10, max: 200, choices: nil),
                .init(name: "count", type: "int", value: .int(128), min: 1, max: 512, choices: nil),
                .init(name: "showGrid", type: "bool", value: .bool(false), min: nil, max: nil, choices: nil),
                .init(name: "mode", type: "string", value: .string("add"), min: nil, max: nil,
                      choices: ["add", "multiply"]),
                .init(name: "tint", type: "color", value: .color(1, 0.5, 0.25, 1), min: nil, max: nil, choices: nil),
                .init(name: "origin", type: "vec2", value: .vec2(640, 360), min: nil, max: nil, choices: nil),
                .init(name: "wind", type: "vec3", value: .vec3(0.1, 0, -0.2), min: nil, max: nil, choices: nil),
            ]
        )
        try assertStructurallyEqual(encode(file), loadContractExample("params.json"), path: "params")
    }

    @Test("params.json (minimal) は optional 省略時の構造と一致する")
    func paramsMinimalMatchesExample() throws {
        let file = ParameterFile(
            schemaVersion: 1,
            revision: 1,
            appliedRequestId: nil,
            warnings: [],
            params: [
                .init(name: "radius", type: "float", value: .float(50), min: nil, max: nil, choices: nil)
            ]
        )
        try assertStructurallyEqual(
            encode(file), loadContractExample("params-minimal.json"), path: "params-minimal"
        )
    }

    @Test("set-request.json の example は実デコーダで読める（consumer 出力の正典サンプル）")
    func setRequestExampleDecodes() throws {
        let example = try loadContractExample("param-set-request.json")
        let data = try JSONSerialization.data(withJSONObject: example)
        let request = try #require(ParameterSetRequest.decode(from: data))
        #expect(request.id == "01J2ZK9M3QW8XV4T7YB0C5D6EF")

        // 宣言済みホストへ適用して、example の全キーが実型で解釈できることを確認する。
        let host = ParamHost()
        let store = ParameterStore()
        store.discover(in: host)
        // example の "mode" は明示名 "blend" ではないため 1 件だけ未知になる想定。
        let applied = store.apply(request)
        #expect(applied == 5)
        #expect(host.radius == 120.5)
        #expect(host.count == 256)
        #expect(host.showGrid == true)
        #expect(host.origin == Vec2(320, 180))
        #expect(host.tint == Color(r: 1, g: 0.5, b: 0.25, alpha: 1))
    }
}
