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
        let analysis = analyze(pixels: pixels, width: width, height: height)

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
            warnings: metadata.warnings + analysis.warnings,
            stats: analysis.stats
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

    /// `analyze` の結果。blank 等の警告と、AI 向けの軽量画像統計をまとめて返します。
    struct Analysis {
        let warnings: [String]
        let stats: ProbeFrameMetadata.Stats
    }

    /// 32x32 グリッドサンプルを 1 パスで走査し、blank 警告と画像統計
    /// （平均色・輝度・コンテンツ被覆率・バウンディングボックス）を計算します。
    ///
    /// 統計は「PNG をデコードせずに済む数値シグナル」を狙ったもので、
    /// AI エージェントがスナップショット間の差分を引き算で得るためにも使えます。
    /// 背景色は四隅サンプルの平均で近似し、そこから十分離れたサンプルを
    /// 「コンテンツ」とみなします（フルブリードな背景では目安程度の精度）。
    private static func analyze(
        pixels: [UInt8], width: Int, height: Int
    ) -> Analysis {
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
        let meanLuminance = 0.2126 * meanR + 0.7152 * meanG + 0.0722 * meanB

        var variance: Float = 0
        for k in 0..<n {
            let dr = samplesR[k] - meanR
            let dg = samplesG[k] - meanG
            let db = samplesB[k] - meanB
            variance += dr * dr + dg * dg + db * db
        }
        variance *= invN

        // 背景色 = 四隅サンプルの平均。idx = sy * samplesPerSide + sx。
        let last = samplesPerSide - 1
        let corners = [0, last, last * samplesPerSide, last * samplesPerSide + last]
        var bgR: Float = 0, bgG: Float = 0, bgB: Float = 0
        for c in corners {
            bgR += samplesR[c]; bgG += samplesG[c]; bgB += samplesB[c]
        }
        bgR /= 4; bgG /= 4; bgB /= 4

        // 背景から十分離れたサンプルを「コンテンツ」とみなす。
        // 閾値 0.10（RGB ユークリッド距離、約 ±15/255）= 目に見える差。
        let contentThresholdSq: Float = 0.10 * 0.10
        var contentCount = 0
        var minSx = samplesPerSide, maxSx = -1
        var minSy = samplesPerSide, maxSy = -1
        for sy in 0..<samplesPerSide {
            for sx in 0..<samplesPerSide {
                let k = sy * samplesPerSide + sx
                let dr = samplesR[k] - bgR
                let dg = samplesG[k] - bgG
                let db = samplesB[k] - bgB
                if dr * dr + dg * dg + db * db > contentThresholdSq {
                    contentCount += 1
                    if sx < minSx { minSx = sx }
                    if sx > maxSx { maxSx = sx }
                    if sy < minSy { minSy = sy }
                    if sy > maxSy { maxSy = sy }
                }
            }
        }

        let side = Float(samplesPerSide)
        let contentBounds: ProbeFrameMetadata.Bounds? = contentCount > 0
            ? ProbeFrameMetadata.Bounds(
                x: Float(minSx) / side,
                y: Float(minSy) / side,
                width: Float(maxSx - minSx + 1) / side,
                height: Float(maxSy - minSy + 1) / side
            )
            : nil

        let stats = ProbeFrameMetadata.Stats(
            meanColor: [meanR, meanG, meanB],
            meanLuminance: meanLuminance,
            contentFraction: Float(contentCount) * invN,
            contentBounds: contentBounds,
            sampleGrid: samplesPerSide
        )

        var warnings: [String] = []
        // 全画素がほぼ同色なら blank。閾値 0.0001 はおおよそ
        // 1 channel あたり ±0.005 (約 ±1/255) 程度の揺らぎまで「flat」と判定。
        if variance < 0.0001 {
            warnings.append("frame appears nearly blank (variance=\(String(format: "%.6f", variance)))")
        }

        return Analysis(warnings: warnings, stats: stats)
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
