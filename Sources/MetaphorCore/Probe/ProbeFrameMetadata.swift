import Foundation

/// `frame.json` のスキーマ。`frame.png` と一緒に書き出され、
/// AI エージェントが「見た目」と並行して内部状態を観測するための
/// 構造化メタデータです。
struct ProbeFrameMetadata: Encodable {
    /// JSON スキーマのバージョン。後方互換性のため将来増やす想定。
    let schemaVersion: Int

    /// 対応するリクエストの id。
    let id: String

    /// オプションのリクエストラベル。
    let label: String?

    /// レンダリングされたフレーム番号。
    let frame: Int

    /// スケッチ開始からの経過時間（秒）。
    let time: Double

    /// オフスクリーン解像度。
    let size: Size

    /// `Sketch.probe(_:_:)` で記録されたユーザー定義値。
    let custom: [String: ProbeValue]

    /// プラグインが検出した警告（例: blank frame）。
    let warnings: [String]

    struct Size: Encodable {
        let width: Int
        let height: Int
    }
}
