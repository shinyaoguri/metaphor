import Foundation

/// AI エージェントが書き込むスナップショットリクエスト。
///
/// `request.json` の形式は次の通り。
///
/// ```json
/// {
///   "id": "01HXYZ...",
///   "label": "baseline",
///   "scale": 1.0,
///   "frames": 8,
///   "every": 2
/// }
/// ```
///
/// - `id` は 1 リクエストごとに変更してください。同じ `id` のリクエストは
///   重複扱いとなり再処理されません。
/// - `label` / `scale` / `frames` / `every` は任意項目です。
/// - `frames` が省略または `<= 1` のときは従来どおり単一フレームを
///   `current/frame.{png,json}` に書き出します。`frames >= 2` のときは
///   `current/sequence/` 以下に連続フレーム列・contact sheet・manifest を
///   書き出します（時間軸の観測用）。
/// - `every` は何フレームおきに 1 枚採るか（ストライド、既定 1）。
struct ProbeRequest: Codable, Sendable {
    /// リクエストの一意な識別子。同じ id は 1 度しか処理されません。
    let id: String

    /// オプションの注釈。`frame.json` にそのまま転記されます。
    let label: String?

    /// 出力画像のスケール。`nil` のときはプラグイン設定の `defaultScale` を使用。
    /// 有効範囲は 0 < scale <= 1（縮小専用）。範囲外・非有限はフルサイズ扱い。
    let scale: Float?

    /// 連続キャプチャするフレーム数。`nil` / `<= 1` なら単一フレーム（従来動作）。
    let frames: Int?

    /// 採取間隔（ストライド）。`nil` なら 1（毎フレーム）。
    let every: Int?
}
