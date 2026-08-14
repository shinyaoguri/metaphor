import Foundation

/// `.metaphor/params/params.json` の wire 形式（producer = スケッチが唯一の書き手）。
///
/// wire 形式の正典は `contract/params.schema.json`（CONTRACT.md 契約点 7）。
/// この Swift 型が意味の正典で、スキーマはそれを機械可読に写したものです。
///
/// ```jsonc
/// {
///   "schemaVersion": 1,
///   "revision": 42,
///   "appliedRequestId": "01J…",   // 最後に適用した set-request の id
///   "warnings": [],               // 直近の set-request で拒否された理由
///   "params": [
///     {"name": "radius", "type": "float", "value": 120, "min": 10, "max": 200}
///   ]
/// }
/// ```
struct ParameterFile: Encodable {
    /// 現行スキーマバージョン。additive 変更では上げません（CONTRACT.md 契約点 7）。
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// 値が変わるたびに増える単調カウンタ。
    let revision: Int
    /// 最後に適用した set-request の id（未処理なら省略）。
    let appliedRequestId: String?
    /// 直近の set-request で拒否・クランプされた項目の説明（無ければ空配列）。
    let warnings: [String]
    /// 宣言順のパラメータ一覧。
    let params: [Entry]

    struct Entry: Encodable {
        let name: String
        let type: String
        let value: ParamValue
        let min: Double?
        let max: Double?
        let choices: [String]?
    }
}

extension ParameterFile {
    /// 永続化ファイルを読み取ります（型情報は各エントリの `type` が正典）。
    ///
    /// `JSONSerialization` で読むのは、`value` が型タグ依存の裸の JSON だからです
    /// （`Codable` の単一値コンテナでは型タグを先に読めない）。壊れたファイル・
    /// 未知の `schemaVersion` は `nil` を返し、呼び出し側はコード既定値のまま進みます。
    static func decode(from data: Data) -> ParameterFile? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let schemaVersion = dict["schemaVersion"] as? Int,
              schemaVersion == currentSchemaVersion else {
            return nil
        }
        let revision = dict["revision"] as? Int ?? 0
        let rawParams = dict["params"] as? [[String: Any]] ?? []
        let entries: [Entry] = rawParams.compactMap { raw in
            guard let name = raw["name"] as? String,
                  let type = raw["type"] as? String,
                  let rawValue = raw["value"],
                  let value = ParamValue.from(json: rawValue, typeTag: type) else {
                return nil
            }
            return Entry(
                name: name,
                type: type,
                value: value,
                min: raw["min"] as? Double,
                max: raw["max"] as? Double,
                choices: raw["choices"] as? [String]
            )
        }
        return ParameterFile(
            schemaVersion: schemaVersion,
            revision: revision,
            appliedRequestId: dict["appliedRequestId"] as? String,
            warnings: dict["warnings"] as? [String] ?? [],
            params: entries
        )
    }
}

/// `.metaphor/params/set-request.json` の wire 形式（consumer = AI エージェント /
/// ツールが `.tmp` → rename でアトミックに書く）。
///
/// ```json
/// { "id": "01J…", "values": { "radius": 120.0, "showGrid": false } }
/// ```
///
/// `values` の各値は**宣言された型に沿った裸の JSON**（`vec2` は 2 要素配列、
/// `color` は 4 要素配列）。型が合わない値は拒否され、理由が `params.json` の
/// `warnings` に載ります。`id` はリクエストごとに必ず変えてください
/// （producer は同一 id を再処理しません）。
struct ParameterSetRequest {
    let id: String
    /// パラメータ名 → 裸の JSON 値（型は宣言側が正典なので `Any` のまま持つ）。
    let values: [String: Any]

    static func decode(from data: Data) -> ParameterSetRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let id = dict["id"] as? String,
              let values = dict["values"] as? [String: Any] else {
            return nil
        }
        return ParameterSetRequest(id: id, values: values)
    }
}

/// `params.json` の原子的な書き出し（専用の直列キュー上で実行）。
///
/// エンコードはメインスレッド（値の読み出しと同じアクター）で行い、
/// ディスク I/O だけをキューへ逃がします。フレームループを塞がないためです。
enum ParameterFileWriter {
    private static let writeQueue = DispatchQueue(
        label: "org.metaphor.params.writer", qos: .utility
    )

    /// スナップショットを `<directory>/params.json` へ原子的に書き出します。
    ///
    /// - Parameters:
    ///   - file: 書き出す内容（呼び出し側でエンコード可能な値として確定済み）。
    ///   - directory: 出力ディレクトリ（存在しなければ作成）。
    static func write(_ file: ParameterFile, directory: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else {
            metaphorDiagnostic("params: params.json のエンコードに失敗しました")
            return
        }
        writeQueue.async {
            let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: dirURL, withIntermediateDirectories: true
                )
                let finalURL = dirURL.appendingPathComponent("params.json")
                let tmpURL = dirURL.appendingPathComponent("params.json.tmp")
                try data.write(to: tmpURL)
                metaphorAtomicReplace(tmp: tmpURL, final: finalURL, label: "Params")
            } catch {
                print("[metaphor] Params: failed to write params.json: \(error)")
            }
        }
    }
}
