import Foundation

/// AI エージェントが書き込むスナップショットリクエスト。
///
/// `request.json` の形式は次の通り。
///
/// ```json
/// {
///   "id": "01HXYZ...",
///   "label": "baseline",
///   "scale": 1.0
/// }
/// ```
///
/// - `id` は 1 リクエストごとに変更してください。同じ `id` のリクエストは
///   重複扱いとなり再処理されません。
/// - `label` と `scale` は任意項目です。
struct ProbeRequest: Codable, Sendable {
    /// リクエストの一意な識別子。同じ id は 1 度しか処理されません。
    let id: String

    /// オプションの注釈。`frame.json` にそのまま転記されます。
    let label: String?

    /// 出力画像のスケール。`nil` のときはプラグイン設定の `defaultScale` を使用。
    let scale: Float?
}
