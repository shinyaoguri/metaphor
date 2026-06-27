import Foundation

/// `current/sequence/sequence.json` のスキーマ。
///
/// `capture_sequence`（`ProbeRequest.frames >= 2`）で書き出される連続フレーム列の
/// 索引です。AI エージェントは個々の `frame.NNNN.png` を見る前に、まずこの manifest を
/// 読んで「何枚・どの時刻・どのサイズ・contact sheet はどれか」を把握できます。
///
/// 完了規約: シーケンス出力のうち **`sequence.json` を最後に** 原子的に書き出します。
/// したがって consumer は「`sequence.json` が存在し、`id` がリクエストと一致し、
/// `frames.count == frameCount` であれば ready」と判定できます（単一フレームの
/// `frame.json` mtime ポーリングと同型）。
///
/// `frame.json` と同じく additive・前方互換を原則とし、独自の `schemaVersion` を持ちます。
/// 各フレームの軽量統計（`stats`）は重複を避けるため個々の `frame.NNNN.json` 側に置き、
/// この manifest はフレーム番号・時刻・参照サイズの一覧に徹します。
struct ProbeSequenceManifest: Encodable, Sendable {
    /// この manifest スキーマのバージョン（`frame.json` とは独立）。
    let schemaVersion: Int

    /// 対応するリクエストの id。
    let id: String

    /// オプションのリクエストラベル。
    let label: String?

    /// 実際に書き出したフレーム数（クランプ・degrade 後）。
    let frameCount: Int

    /// リクエストされたフレーム数（クランプ前。透明性のため）。
    let requestedFrames: Int

    /// 採取間隔（ストライド）。
    let every: Int

    /// 参照解像度（最初に採取したフレームのサイズ）。
    let size: ProbeFrameMetadata.Size

    /// contact sheet のファイル名（`current/sequence/` からの相対）。書けない場合は nil。
    let contactSheet: String?

    /// シーケンス全体に対する警告（例: noLoop により単一フレームに degrade）。
    let warnings: [String]

    /// フレームごとのエントリ（採取順）。
    let frames: [Entry]

    /// 連続フレーム列の 1 枚分のエントリ。
    struct Entry: Encodable, Sendable {
        /// 0 始まりの採取インデックス。
        let index: Int

        /// PNG ファイル名（`current/sequence/` からの相対）。
        let file: String

        /// メタデータ JSON ファイル名（`current/sequence/` からの相対）。
        let metadata: String

        /// 採取時点のスケッチのフレーム番号。
        let frame: Int

        /// スケッチ開始からの経過時間（秒、実測）。
        let time: Double
    }
}
