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
        directory: String
    ) {
        let dirURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )

        let finalURL = dirURL.appendingPathComponent("frame.png")
        let tmpURL = dirURL.appendingPathComponent("frame.png.tmp")

        MetaphorRenderer.writePNG(
            texture: staging, width: width, height: height, path: tmpURL.path
        )

        try? FileManager.default.removeItem(at: finalURL)
        do {
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        } catch {
            print("[metaphor] Probe: failed to rename frame.png.tmp -> frame.png: \(error)")
        }
    }
}
