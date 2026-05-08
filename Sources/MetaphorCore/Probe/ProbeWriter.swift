import Foundation
import Metal

/// PNG / JSON のディスク書き出しを担当するヘルパー。
///
/// `commandBuffer.addCompletedHandler` の中（Metal 内部キュー）から呼ばれるため、
/// メインアクター隔離されない `enum` の `static` メソッドとして実装しています。
enum ProbeWriter {
    /// ステージングテクスチャの内容を `<directory>/frame.png` に原子的に書き出します。
    ///
    /// 書き込みは `frame.png.tmp` 経由で行い、最後に `rename` で確定するため、
    /// AI エージェント側が中途半端な PNG を読む可能性はありません。
    static func writeSnapshot(
        staging: MTLTexture,
        width: Int,
        height: Int,
        directory: String,
        metadata: ProbeFrameMetadata?
    ) {
        let dirURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )

        let finalPNG = dirURL.appendingPathComponent("frame.png")
        let tmpPNG = dirURL.appendingPathComponent("frame.png.tmp")

        MetaphorRenderer.writePNG(
            texture: staging, width: width, height: height, path: tmpPNG.path
        )
        atomicReplace(tmp: tmpPNG, final: finalPNG)

        guard let metadata else { return }

        let finalJSON = dirURL.appendingPathComponent("frame.json")
        let tmpJSON = dirURL.appendingPathComponent("frame.json.tmp")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: tmpJSON)
            atomicReplace(tmp: tmpJSON, final: finalJSON)
        } catch {
            print("[metaphor] Probe: failed to write frame.json: \(error)")
        }
    }

    /// 一時ファイルから本番パスへの原子的なリネーム。
    private static func atomicReplace(tmp: URL, final: URL) {
        try? FileManager.default.removeItem(at: final)
        do {
            try FileManager.default.moveItem(at: tmp, to: final)
        } catch {
            print("[metaphor] Probe: failed to rename \(tmp.lastPathComponent) -> \(final.lastPathComponent): \(error)")
        }
    }
}
