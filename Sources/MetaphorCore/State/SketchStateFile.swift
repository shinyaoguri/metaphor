import Foundation

/// `.metaphor/state/state.json` の wire 形式（producer = スケッチが唯一の書き手）。
///
/// wire 形式の正典は `contract/state.schema.json`（CONTRACT.md 契約点 8）。
/// この Swift 型が意味の正典で、スキーマはそれを機械可読に写したものです。
///
/// ```jsonc
/// {
///   "schemaVersion": 1,
///   "savedRequestId": "01J…",       // 応答した save-request の id エコー
///   "runtime": {                     // metaphor 自身が復元する時計
///     "frameCount": 1024,
///     "elapsedSeconds": 17.06
///   },
///   "user": {                        // saveState() の opaque ペイロード（省略可）
///     "encoding": "base64",
///     "data": "eyJwYXJ0aWNsZXMiOltdfQ=="
///   }
/// }
/// ```
///
/// `user` 節は**エンベロープだけが契約**で、`data` の中身はスケッチ作者のものです
/// （consumer は運ぶだけで解釈しない）。
struct SketchStateFile: Encodable {
    /// 現行スキーマバージョン。additive 変更では上げません（CONTRACT.md 契約点 8）。
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// 応答した save-request の `id`（consumer はこのエコーで ready を検知する）。
    let savedRequestId: String?
    /// metaphor 自身が復元する実行時状態（時計）。
    let runtime: Runtime
    /// `Sketch/saveState()` が返したペイロード（`nil` を返したスケッチでは省略）。
    let user: User?

    /// 時計。`config.preserveClock` が `true` のときだけ復元に使われます。
    struct Runtime: Encodable {
        /// 保存時点でレンダリング済みのフレーム数。
        let frameCount: Int
        /// スケッチ開始からの経過秒数。
        let elapsedSeconds: Double
    }

    /// opaque ペイロードのエンベロープ。
    struct User: Encodable {
        /// `data` のエンコーディング。現行は `base64` のみ。
        let encoding: String
        /// ペイロード本体。
        let data: String

        init(payload: Data) {
            self.encoding = "base64"
            self.data = payload.base64EncodedString()
        }
    }

    init(savedRequestId: String?, frameCount: Int, elapsedSeconds: Double, payload: Data?) {
        self.schemaVersion = Self.currentSchemaVersion
        self.savedRequestId = savedRequestId
        self.runtime = Runtime(frameCount: frameCount, elapsedSeconds: elapsedSeconds)
        self.user = payload.map(User.init(payload:))
    }
}

/// 読み取り側（新しいプロセスの復元経路）が扱う `state.json` の内容。
///
/// 書き出しと違い、読み取りは **壊れていても落ちない**ことが最優先です
/// （開発ツールの都合でスケッチが起動しないのは本末転倒）。未知の
/// `schemaVersion`・欠損キー・不正な base64 はすべて `nil` / 既定値へ倒します。
struct RestoredSketchState {
    let frameCount: Int
    let elapsedSeconds: Double
    let payload: Data?

    /// `state.json` をデコードします。復元できない内容では `nil` を返し、
    /// 呼び出し側は通常起動（初期状態）へフォールバックします。
    static func decode(from data: Data) -> RestoredSketchState? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let schemaVersion = dict["schemaVersion"] as? Int,
              schemaVersion == SketchStateFile.currentSchemaVersion else {
            return nil
        }
        let runtime = dict["runtime"] as? [String: Any]
        var payload: Data?
        if let user = dict["user"] as? [String: Any],
           let encoding = user["encoding"] as? String,
           let encoded = user["data"] as? String {
            // 未知のエンコーディングは「ペイロード無し」として扱う（時計だけは復元できる）。
            if encoding == "base64" {
                payload = Data(base64Encoded: encoded)
                if payload == nil {
                    metaphorDiagnostic("state: user.data の base64 を復号できませんでした（無視）")
                }
            } else {
                metaphorDiagnostic("state: 未知の user.encoding '\(encoding)' を無視します")
            }
        }
        return RestoredSketchState(
            frameCount: runtime?["frameCount"] as? Int ?? 0,
            elapsedSeconds: runtime?["elapsedSeconds"] as? Double ?? 0,
            payload: payload
        )
    }
}

/// `.metaphor/state/save-request.json` の wire 形式
///（consumer = metaphor-cli / AI ツールが `.tmp` → rename でアトミックに書く）。
///
/// ```json
/// { "id": "01J…" }
/// ```
///
/// `id` はリクエストごとに必ず変えてください（producer は同一 id を再処理しません）。
struct SketchStateSaveRequest {
    let id: String

    static func decode(from data: Data) -> SketchStateSaveRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let id = dict["id"] as? String else {
            return nil
        }
        return SketchStateSaveRequest(id: id)
    }
}

/// `state.json` の原子的な書き出し。
///
/// `params.json` と違い**同期**で書きます。consumer（`metaphor watch`）はこの
/// ファイルの `savedRequestId` エコーを見てから子プロセスを kill するため、
/// 書き出しの完了がそのままリロードの待ち時間になるからです。書くのは
/// リロード直前の 1 回だけで、フレームループの定常コストではありません。
enum SketchStateWriter {
    /// スナップショットを `<directory>/state.json` へ原子的に書き出します。
    ///
    /// - Returns: 書き出せたら `true`。
    @discardableResult
    static func write(_ file: SketchStateFile, directory: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else {
            metaphorDiagnostic("state: state.json のエンコードに失敗しました")
            return false
        }
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let finalURL = dirURL.appendingPathComponent("state.json")
            let tmpURL = dirURL.appendingPathComponent("state.json.tmp")
            try data.write(to: tmpURL)
            metaphorAtomicReplace(tmp: tmpURL, final: finalURL, label: "State")
            return true
        } catch {
            print("[metaphor] State: failed to write state.json: \(error)")
            return false
        }
    }
}
