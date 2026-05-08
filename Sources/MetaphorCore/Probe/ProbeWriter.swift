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
    /// `metadata` が渡された場合は `frame.json` も同様に書き出します。
    /// この関数の中でステージングのバイト列を 1 度だけ読み、PNG 化と
    /// blank フレーム解析に使い回します。
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

        let pixels = readBGRA(from: staging, width: width, height: height)
        let warnings = analyze(pixels: pixels, width: width, height: height)

        let finalPNG = dirURL.appendingPathComponent("frame.png")
        let tmpPNG = dirURL.appendingPathComponent("frame.png.tmp")
        encodePNG(pixels: pixels, width: width, height: height, to: tmpPNG)
        atomicReplace(tmp: tmpPNG, final: finalPNG)

        guard let metadata else { return }

        let enriched = ProbeFrameMetadata(
            schemaVersion: metadata.schemaVersion,
            id: metadata.id,
            label: metadata.label,
            frame: metadata.frame,
            time: metadata.time,
            size: metadata.size,
            custom: metadata.custom,
            warnings: metadata.warnings + warnings
        )

        let finalJSON = dirURL.appendingPathComponent("frame.json")
        let tmpJSON = dirURL.appendingPathComponent("frame.json.tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(enriched)
            try data.write(to: tmpJSON)
            atomicReplace(tmp: tmpJSON, final: finalJSON)
        } catch {
            print("[metaphor] Probe: failed to write frame.json: \(error)")
        }
    }

    // MARK: - Helpers

    /// ステージングテクスチャから BGRA8 のバイト列を読み出します。
    private static func readBGRA(from texture: MTLTexture, width: Int, height: Int) -> [UInt8] {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return pixels
    }

    /// BGRA8 ピクセルから PNG をエンコードして指定パスに書きます。
    private static func encodePNG(
        pixels: [UInt8], width: Int, height: Int, to url: URL
    ) {
        var rgba = pixels
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let b = rgba[i]
            rgba[i] = rgba[i + 2]
            rgba[i + 2] = b
        }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            print("[metaphor] Probe: failed to encode PNG at \(url.path)")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    /// 32x32 グリッドサンプルで分散を計算し、低分散なら blank 警告を返します。
    private static func analyze(
        pixels: [UInt8], width: Int, height: Int
    ) -> [String] {
        let bytesPerRow = width * 4
        let samplesPerSide = 32
        let n = samplesPerSide * samplesPerSide

        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        var samplesR = [Float](repeating: 0, count: n)
        var samplesG = [Float](repeating: 0, count: n)
        var samplesB = [Float](repeating: 0, count: n)

        var idx = 0
        for sy in 0..<samplesPerSide {
            for sx in 0..<samplesPerSide {
                let x = min(width - 1, (sx * width) / samplesPerSide)
                let y = min(height - 1, (sy * height) / samplesPerSide)
                let i = y * bytesPerRow + x * 4
                let b = Float(pixels[i]) / 255.0
                let g = Float(pixels[i + 1]) / 255.0
                let r = Float(pixels[i + 2]) / 255.0
                samplesR[idx] = r
                samplesG[idx] = g
                samplesB[idx] = b
                sumR += r; sumG += g; sumB += b
                idx += 1
            }
        }

        let invN = 1.0 / Float(n)
        let meanR = sumR * invN
        let meanG = sumG * invN
        let meanB = sumB * invN

        var variance: Float = 0
        for k in 0..<n {
            let dr = samplesR[k] - meanR
            let dg = samplesG[k] - meanG
            let db = samplesB[k] - meanB
            variance += dr * dr + dg * dg + db * db
        }
        variance *= invN

        // 全画素がほぼ同色なら blank。閾値 0.0001 はおおよそ
        // 1 channel あたり ±0.005 (約 ±1/255) 程度の揺らぎまで「flat」と判定。
        if variance < 0.0001 {
            return ["frame appears nearly blank (variance=\(String(format: "%.6f", variance)))"]
        }
        return []
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
