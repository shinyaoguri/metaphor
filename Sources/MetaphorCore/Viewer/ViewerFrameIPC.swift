import Foundation

/// viewer frame IPC（CONTRACT.md 契約点 5）の wire 型と JSON Lines の符号化。
///
/// 1 行 1 メッセージ（`\n` 区切り・UTF-8）。`t` で種別を見分け、**未知の `t` と未知のフィールドは無視する**
/// （契約点 3 の stdin 入力イベントと同じ前方互換規約）。構造の正典は `contract/viewer-*.schema.json` で、
/// `ViewerFrameIPCTests` が実型のエンコード結果と `contract/examples/viewer-*.json` の構造一致を守る。
enum ViewerFrameIPC {
    /// プロトコル版。キーの追加・enum の拡大は据え置き、リネーム / 削除 / 意味変更で bump
    /// （`schemaVersion` と同じ規則。CONTRACT.md 契約点 5 の補足）。`scripts/check-contract.sh` が
    /// このリテラルの生存を検査する。
    static let protocolVersion = 1

    // MARK: 子 → 親

    /// world（共有メモリ）の宣言。接続直後と resize 時に、共有メモリの fd を `SCM_RIGHTS` で添えて送る。
    struct Hello: Codable, Equatable, Sendable {
        var t: String = "hello"
        var protocolVersion: Int = ViewerFrameIPC.protocolVersion
        var pid: Int
        var metaphor: String
        var width: Int
        var height: Int
        var pixelFormat: String = "bgra8Unorm"
        var alpha: String = "premultiplied"
        var colorSpace: String = "sRGB"
        var orientation: String = "topLeft"
        var bytesPerRow: Int
        var slotBytes: Int
        var slots: Int
        var backing: String = "posix-shm"

        init(pid: Int, metaphor: String, layout: ViewerFrameLayout) {
            self.pid = pid
            self.metaphor = metaphor
            self.width = layout.width
            self.height = layout.height
            self.bytesPerRow = layout.bytesPerRow
            self.slotBytes = layout.slotBytes
            self.slots = layout.slots
        }
    }

    /// slot の内容が確定した（command buffer の完了ハンドラから送る）。
    struct Frame: Codable, Equatable, Sendable {
        var t: String = "frame"
        var slot: Int
        var seq: Int
        var frameCount: Int
        var time: Double

        init(slot: Int, seq: Int, frameCount: Int, time: Double) {
            self.slot = slot
            self.seq = seq
            self.frameCount = frameCount
            self.time = time
        }
    }

    /// 正常終了（任意）。
    struct Bye: Codable, Equatable, Sendable {
        var t: String = "bye"
    }

    // MARK: 親 → 子

    /// 親が slot の GPU 読みを終えた。
    struct Release: Codable, Equatable, Sendable {
        var t: String = "release"
        var slot: Int

        init(slot: Int) {
            self.slot = slot
        }
    }

    /// 子が受け取るメッセージ。
    enum Incoming: Equatable, Sendable {
        case release(slot: Int)
        /// 既知でない `t`（前方互換のため無視する）。
        case unknown(String)
    }

    /// 最低限の受信形（`t` 以外は任意。未知フィールドは `Decodable` が捨てる）。
    private struct RawIncoming: Decodable {
        let t: String
        let slot: Int?
    }

    // MARK: 符号化

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // キー順を固定して行の形を決定的にする（テスト・ログの読みやすさ。意味には影響しない）。
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// 1 行ぶんの JSON（末尾 `\n` 付き）。
    static func encodeLine<T: Encodable>(_ message: T) throws -> Data {
        var data = try encoder.encode(message)
        data.append(0x0A)
        return data
    }

    /// 1 行をデコードする。不正な JSON / `t` 欠落は `nil`（呼び出し側は読み飛ばす）。
    static func decodeIncoming(_ line: String) -> Incoming? {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawIncoming.self, from: data)
        else { return nil }
        switch raw.t {
        case "release":
            guard let slot = raw.slot else { return nil }
            return .release(slot: slot)
        default:
            return .unknown(raw.t)
        }
    }
}
