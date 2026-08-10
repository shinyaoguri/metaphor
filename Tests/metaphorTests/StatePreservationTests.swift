import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - テスト用スケッチ

/// 状態を持つスケッチの代役。`saveState()` / `restoreState(_:)` の往復を試験する。
@MainActor
private final class StatefulSketch: Sketch {
    struct Payload: Codable, Equatable {
        var particles: [Float]
        var label: String
    }

    var payload = Payload(particles: [1, 2, 3], label: "alive")
    /// `restoreState(_:)` が呼ばれた回数（`setup()` 後に 1 回だけであることの確認用）。
    var restoreCallCount = 0

    func saveState() -> Data? { encodeState(payload) }

    func restoreState(_ data: Data) {
        restoreCallCount += 1
        guard let restored: Payload = decodeState(data) else { return }
        payload = restored
    }
}

/// 状態を持たないスケッチ（`saveState()` 既定実装 = `nil`）。
@MainActor
private final class StatelessSketch: Sketch {}

// MARK: - 保存側（StatePlugin）

@Suite("State preservation: save")
@MainActor
struct StatePluginSaveTests {

    private func makePlugin(in dir: URL) -> StatePlugin {
        StatePlugin(config: SketchStateConfig(
            directory: dir.path,
            saveRequestFilePath: dir.appendingPathComponent("save-request.json").path
        ))
    }

    private func writeSaveRequest(id: String, to dir: URL) throws {
        try JSONSerialization.data(withJSONObject: ["id": id])
            .write(to: dir.appendingPathComponent("save-request.json"))
    }

    private func readStateFile(in dir: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("state.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("save-request で saveState() が呼ばれ、id をエコーした state.json が書かれる")
    func saveRequestWritesStateWithEcho() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let sketch = StatefulSketch()
            let plugin = makePlugin(in: dir)
            plugin.onAttach(sketch: sketch)

            try writeSaveRequest(id: "save-1", to: dir)
            plugin.tick(elapsedSeconds: 12.5)

            let file = try readStateFile(in: dir)
            #expect(file["schemaVersion"] as? Int == 1)
            #expect(file["savedRequestId"] as? String == "save-1")
            let runtime = try #require(file["runtime"] as? [String: Any])
            #expect(runtime["elapsedSeconds"] as? Double == 12.5)
            // context 未接続なので frameCount は 0（時計の復元は GPU 側スイートで確認）。
            #expect(runtime["frameCount"] as? Int == 0)

            let user = try #require(file["user"] as? [String: Any])
            #expect(user["encoding"] as? String == "base64")
            let encoded = try #require(user["data"] as? String)
            let payloadData = try #require(Data(base64Encoded: encoded))
            let payload = try JSONDecoder().decode(StatefulSketch.Payload.self, from: payloadData)
            #expect(payload == StatefulSketch.Payload(particles: [1, 2, 3], label: "alive"))
        }
    }

    @Test("saveState() が nil でも state.json は書かれる（runtime だけが載る）")
    func statelessSketchStillAnswers() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let plugin = makePlugin(in: dir)
            plugin.onAttach(sketch: StatelessSketch())

            try writeSaveRequest(id: "save-2", to: dir)
            plugin.tick(elapsedSeconds: 3)

            let file = try readStateFile(in: dir)
            #expect(file["savedRequestId"] as? String == "save-2")
            #expect(file["user"] == nil)  // consumer は無応答でタイムアウトせずに済む
        }
    }

    @Test("リクエストが無いフレームでは state.json を書かない")
    func idleTicksDoNotWrite() {
        TempFileHelper.withTemporaryDirectory { dir in
            let plugin = makePlugin(in: dir)
            plugin.onAttach(sketch: StatefulSketch())

            for tick in 0..<10 { plugin.tick(elapsedSeconds: Double(tick)) }

            #expect(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("state.json").path
            ) == false)
        }
    }

    @Test("同じ id のリクエストは再処理されない")
    func sameRequestIdIsNotReprocessed() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let sketch = StatefulSketch()
            let plugin = makePlugin(in: dir)
            plugin.onAttach(sketch: sketch)

            try writeSaveRequest(id: "same", to: dir)
            plugin.tick(elapsedSeconds: 1)
            #expect(try readStateFile(in: dir)["savedRequestId"] as? String == "same")

            // 状態を変えて、同じ id のファイルを触り直す（mtime だけ更新）。
            sketch.payload.label = "changed"
            try writeSaveRequest(id: "same", to: dir)
            plugin.tick(elapsedSeconds: 2)

            let runtime = try #require(try readStateFile(in: dir)["runtime"] as? [String: Any])
            #expect(runtime["elapsedSeconds"] as? Double == 1)  // 1 回目のまま
        }
    }

    @Test("壊れた save-request は無視され、後続の正しいリクエストは処理される")
    func malformedRequestIsIgnored() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let plugin = makePlugin(in: dir)
            plugin.onAttach(sketch: StatefulSketch())

            let requestURL = dir.appendingPathComponent("save-request.json")
            try Data("{ not json".utf8).write(to: requestURL)
            plugin.tick(elapsedSeconds: 1)
            #expect(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("state.json").path
            ) == false)

            try writeSaveRequest(id: "after-garbage", to: dir)
            plugin.tick(elapsedSeconds: 2)
            #expect(try readStateFile(in: dir)["savedRequestId"] as? String == "after-garbage")
        }
    }

    @Test("自動登録はヘッドレスで有効・METAPHOR_STATE で上書きできる")
    func autoRegistrationRules() {
        #expect(StatePlugin.shouldAutoRegister(env: [:]) == false)
        #expect(StatePlugin.shouldAutoRegister(env: ["METAPHOR_VIEWER": "1"]) == true)
        #expect(StatePlugin.shouldAutoRegister(env: ["METAPHOR_STATE": "1"]) == true)
        #expect(StatePlugin.shouldAutoRegister(
            env: ["METAPHOR_VIEWER": "1", "METAPHOR_STATE": "0"]
        ) == false)
    }
}

// MARK: - 復元側

@Suite("State preservation: restore")
@MainActor
struct StateRestoreTests {

    private func writeState(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func validStateObject(payload: Data?) -> [String: Any] {
        var object: [String: Any] = [
            "schemaVersion": 1,
            "savedRequestId": "save-1",
            "runtime": ["frameCount": 900, "elapsedSeconds": 15.0],
        ]
        if let payload {
            object["user"] = ["encoding": "base64", "data": payload.base64EncodedString()]
        }
        return object
    }

    @Test("METAPHOR_RESTORE_STATE の state.json から時計とペイロードを読む")
    func loadsClockAndPayload() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("state.json")
            try writeState(validStateObject(payload: Data("hello".utf8)), to: url)

            let restored = try #require(
                SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": url.path])
            )
            #expect(restored.frameCount == 900)
            #expect(restored.elapsedSeconds == 15.0)
            #expect(restored.payload == Data("hello".utf8))
        }
    }

    @Test("環境変数が無ければ何も読まない")
    func noEnvMeansNoRestore() {
        #expect(SketchStateRestore.load(env: [:]) == nil)
        #expect(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": ""]) == nil)
    }

    @Test("ファイル欠損・壊れた JSON・未知の schemaVersion は初期状態へフォールバックする")
    func brokenInputsFallBack() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let missing = dir.appendingPathComponent("nope.json")
            #expect(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": missing.path]) == nil)

            let broken = dir.appendingPathComponent("broken.json")
            try Data("{ not json".utf8).write(to: broken)
            #expect(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": broken.path]) == nil)

            let future = dir.appendingPathComponent("future.json")
            try writeState(
                ["schemaVersion": 99, "runtime": ["frameCount": 1, "elapsedSeconds": 1.0]], to: future
            )
            #expect(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": future.path]) == nil)
        }
    }

    @Test("未知の encoding・壊れた base64 ではペイロードだけ捨て、時計は復元する")
    func unknownEncodingKeepsClock() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let unknown = dir.appendingPathComponent("unknown-encoding.json")
            try writeState([
                "schemaVersion": 1,
                "runtime": ["frameCount": 12, "elapsedSeconds": 0.5],
                "user": ["encoding": "protobuf", "data": "AAAA"],
            ], to: unknown)
            let a = try #require(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": unknown.path]))
            #expect(a.payload == nil)
            #expect(a.frameCount == 12)

            let badBase64 = dir.appendingPathComponent("bad-base64.json")
            try writeState([
                "schemaVersion": 1,
                "runtime": ["frameCount": 7, "elapsedSeconds": 0.25],
                "user": ["encoding": "base64", "data": "!!! not base64 !!!"],
            ], to: badBase64)
            let b = try #require(SketchStateRestore.load(env: ["METAPHOR_RESTORE_STATE": badBase64.path]))
            #expect(b.payload == nil)
            #expect(b.frameCount == 7)
        }
    }

    @Test("encodeState / decodeState は往復し、形の違うデータでは nil を返す")
    func codableHelpersRoundTrip() {
        let sketch = StatefulSketch()
        let data = sketch.encodeState(StatefulSketch.Payload(particles: [9], label: "x")) ?? Data()
        let decoded: StatefulSketch.Payload? = sketch.decodeState(data)
        #expect(decoded == StatefulSketch.Payload(particles: [9], label: "x"))

        // スケッチを書き換えて状態の形が変わった場合（リロード中の日常）。
        let mismatched: StatefulSketch.Payload? = sketch.decodeState(Data(#"{"other":1}"#.utf8))
        #expect(mismatched == nil)
    }
}

// MARK: - 保存 → 復元の往復（SketchRunner の適用経路）

@Suite("State preservation: round trip", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct StateRoundTripTests {

    /// GPU 付きの `SketchContext` を組み、スケッチに結線する（ProbeParamsSectionTests と同型）。
    private func makeContext(for sketch: any Sketch) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        sketch._context = context
        return (renderer, context)
    }

    @Test("保存した状態が次のプロセスの restoreState() に届く")
    func statePayloadSurvivesReload() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            // 1 回目のプロセス: 状態を変えてから保存要求に応答する。
            let first = StatefulSketch()
            let (_, firstContext) = try makeContext(for: first)
            firstContext.frameCount = 240
            first.payload = StatefulSketch.Payload(particles: [7, 8], label: "before reload")

            let plugin = StatePlugin(config: SketchStateConfig(
                directory: dir.path,
                saveRequestFilePath: dir.appendingPathComponent("save-request.json").path
            ))
            plugin.onAttach(sketch: first)
            try JSONSerialization.data(withJSONObject: ["id": "reload-1"])
                .write(to: dir.appendingPathComponent("save-request.json"))
            plugin.tick(elapsedSeconds: 42.0)

            // 2 回目のプロセス: METAPHOR_RESTORE_STATE で復元する。
            let second = StatefulSketch()
            let (secondRenderer, secondContext) = try makeContext(for: second)
            let env = ["METAPHOR_RESTORE_STATE": dir.appendingPathComponent("state.json").path]

            SketchRunner.applyRestoredState(
                sketch: second, context: secondContext, renderer: secondRenderer,
                config: SketchConfig(preserveClock: true), env: env
            )

            #expect(second.payload == StatefulSketch.Payload(particles: [7, 8], label: "before reload"))
            #expect(second.restoreCallCount == 1)
            // preserveClock: 時計も引き継ぐ。
            #expect(secondContext.frameCount == 240)
            #expect(secondRenderer.clockOffset == 42.0)
            #expect(secondRenderer.elapsedTime >= 42.0)
        }
    }

    @Test("preserveClock が既定（false）なら状態だけ復元し、時計は 0 から始まる")
    func clockIsNotRestoredByDefault() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let stateURL = dir.appendingPathComponent("state.json")
            try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1,
                "savedRequestId": "reload-2",
                "runtime": ["frameCount": 500, "elapsedSeconds": 30.0],
                "user": [
                    "encoding": "base64",
                    "data": Data(#"{"particles":[5],"label":"kept"}"#.utf8).base64EncodedString(),
                ],
            ]).write(to: stateURL)

            let sketch = StatefulSketch()
            let (renderer, context) = try makeContext(for: sketch)
            SketchRunner.applyRestoredState(
                sketch: sketch, context: context, renderer: renderer,
                config: SketchConfig(), env: ["METAPHOR_RESTORE_STATE": stateURL.path]
            )

            #expect(sketch.payload.label == "kept")
            #expect(context.frameCount == 0)
            #expect(renderer.clockOffset == 0)
        }
    }

    @Test("復元が無ければ restoreState() は呼ばれない")
    func noRestoreLeavesSketchUntouched() throws {
        let sketch = StatefulSketch()
        let (renderer, context) = try makeContext(for: sketch)
        SketchRunner.applyRestoredState(
            sketch: sketch, context: context, renderer: renderer,
            config: SketchConfig(preserveClock: true), env: [:]
        )
        #expect(sketch.restoreCallCount == 0)
        #expect(renderer.clockOffset == 0)
    }
}

// MARK: - wire スキーマ適合（producer 側）

@Suite("State preservation wire-schema conformance")
@MainActor
struct SketchStateSchemaConformanceTests {

    /// SketchStateWriter と同一の encoder 設定。
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("state.json (full) は実 SketchStateFile と構造一致する")
    func stateFullMatchesExample() throws {
        let file = SketchStateFile(
            savedRequestId: "01JB8Z6QK3XN5T4W7Y2E9RCVHD",
            frameCount: 1024,
            elapsedSeconds: 17.0625,
            payload: Data(#"{"particles":[]}"#.utf8)
        )
        try assertStructurallyEqual(encode(file), loadContractExample("state.json"), path: "state")
    }

    @Test("state.json (minimal) は saveState() が nil のときの構造と一致する")
    func stateMinimalMatchesExample() throws {
        let file = SketchStateFile(
            savedRequestId: "01JB8Z6QK3XN5T4W7Y2E9RCVHD",
            frameCount: 0,
            elapsedSeconds: 0,
            payload: nil
        )
        try assertStructurallyEqual(
            encode(file), loadContractExample("state-minimal.json"), path: "state-minimal"
        )
    }

    @Test("save-request.json の example は実デコーダで読める（consumer 出力の正典サンプル）")
    func saveRequestExampleDecodes() throws {
        let example = try loadContractExample("state-save-request.json")
        let data = try JSONSerialization.data(withJSONObject: example)
        let request = try #require(SketchStateSaveRequest.decode(from: data))
        #expect(request.id == "01JB8Z6QK3XN5T4W7Y2E9RCVHD")
    }

    @Test("state.json の example は実デコーダで読める（復元経路の正典サンプル）")
    func stateExampleDecodes() throws {
        let example = try loadContractExample("state.json")
        let data = try JSONSerialization.data(withJSONObject: example)
        let restored = try #require(RestoredSketchState.decode(from: data))
        #expect(restored.frameCount == 1024)
        #expect(restored.elapsedSeconds == 17.0625)
        #expect(restored.payload == Data(#"{"particles":[]}"#.utf8))
    }
}
