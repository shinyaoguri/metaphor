import Foundation
import Metal
import CoreGraphics
import ImageIO

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
    ///
    /// `scale`（CONTRACT.md 契約点 4）が 1 未満のときは PNG を縮小して書き出し、
    /// `frame.json` の `size` もスケール後の値になります。
    static func writeSnapshot(
        staging: MTLTexture,
        width: Int,
        height: Int,
        scale: Float = 1.0,
        directory: String,
        metadata: ProbeFrameMetadata?
    ) {
        writeNamed(
            staging: staging, width: width, height: height, scale: scale,
            directory: directory, baseName: "frame", metadata: metadata
        )
    }

    /// 連続キャプチャの 1 フレームを `<directory>/frame.NNNN.{png,json}` に書き出します。
    ///
    /// 単一フレームの ``writeSnapshot(staging:width:height:scale:directory:metadata:)`` と
    /// 同一の経路（同じ読み出し・解析・原子書き出し）を、索引付きファイル名で使います。
    static func writeSequenceFrame(
        staging: MTLTexture,
        width: Int,
        height: Int,
        scale: Float = 1.0,
        directory: String,
        index: Int,
        metadata: ProbeFrameMetadata?
    ) {
        writeNamed(
            staging: staging, width: width, height: height, scale: scale,
            directory: directory, baseName: sequenceBaseName(index),
            metadata: metadata
        )
    }

    /// `scale` を出力に適用できる範囲へ正規化します。
    ///
    /// 非有限・0 以下・1 超はフルサイズ（1.0）扱い。契約上 scale は縮小のための
    /// パラメータであり、拡大やゼロ除算相当の値は意味を持たないため。
    static func normalizeScale(_ scale: Float) -> Float {
        guard scale.isFinite, scale > 0, scale < 1 else { return 1.0 }
        return scale
    }

    /// `scale` 適用後の出力サイズ（最小 1px）。プラグイン側（manifest の参照サイズ）と
    /// 書き出し側で同じ丸めを共有するための単一の計算点。
    static func scaledSize(width: Int, height: Int, scale: Float) -> (width: Int, height: Int) {
        let s = normalizeScale(scale)
        guard s < 1 else { return (width, height) }
        return (
            max(1, Int((Float(width) * s).rounded())),
            max(1, Int((Float(height) * s).rounded()))
        )
    }

    /// シーケンスフレームのベース名（拡張子なし）。`writeSequenceFrame` と manifest で共有。
    static func sequenceBaseName(_ index: Int) -> String {
        String(format: "frame.%04d", index)
    }

    /// ステージング内容を `<directory>/<baseName>.{png,json}` に原子的に書き出す共通本体。
    private static func writeNamed(
        staging: MTLTexture,
        width: Int,
        height: Int,
        scale: Float,
        directory: String,
        baseName: String,
        metadata: ProbeFrameMetadata?
    ) {
        let dirURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )

        // BGRA で読み出して RGBA に並べ替える（CG スケーリングと PNG エンコードは
        // RGBA 前提。以降の解析もこの並びで行う）。
        var pixels = readBGRA(from: staging, width: width, height: height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }

        // scale < 1 なら縮小（契約点 4: 出力画像のスケール）。
        var outWidth = width
        var outHeight = height
        if normalizeScale(scale) < 1,
           let scaled = scaleRGBA(pixels: pixels, width: width, height: height, scale: scale) {
            (pixels, outWidth, outHeight) = scaled
        }

        let analysis = analyze(pixels: pixels, width: outWidth, height: outHeight)

        let finalPNG = dirURL.appendingPathComponent("\(baseName).png")
        let tmpPNG = dirURL.appendingPathComponent("\(baseName).png.tmp")
        encodePNG(rgba: &pixels, width: outWidth, height: outHeight, to: tmpPNG)
        atomicReplace(tmp: tmpPNG, final: finalPNG)

        guard let metadata else { return }

        let enriched = ProbeFrameMetadata(
            schemaVersion: metadata.schemaVersion,
            id: metadata.id,
            label: metadata.label,
            sourceStamp: metadata.sourceStamp,
            frame: metadata.frame,
            time: metadata.time,
            // 実際に書き出した PNG のサイズ（scale 適用後）を書く
            size: ProbeFrameMetadata.Size(width: outWidth, height: outHeight),
            custom: metadata.custom,
            customTypes: metadata.customTypes,
            warnings: metadata.warnings + analysis.warnings,
            stats: analysis.stats
        )

        let finalJSON = dirURL.appendingPathComponent("\(baseName).json")
        let tmpJSON = dirURL.appendingPathComponent("\(baseName).json.tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(enriched)
            try data.write(to: tmpJSON)
            atomicReplace(tmp: tmpJSON, final: finalJSON)
        } catch {
            print("[metaphor] Probe: failed to write \(baseName).json: \(error)")
        }
    }

    /// 既に書き出した連続フレーム PNG 群から contact sheet（一覧モンタージュ）を合成し、
    /// `<directory>/contact_sheet.png` に原子的に書き出します。
    ///
    /// フレームはディスクから読み直して合成します（フレームごとの readback 完了ハンドラが
    /// コミット順に直列実行されるため、最後のフレームのハンドラから呼べば全 PNG が出揃って
    /// いることが保証されます）。各セルにはアスペクト比を保ってレターボックス配置します
    /// （途中リサイズでサイズが混在しても崩れない）。
    ///
    /// - Returns: 書き出した contact sheet の相対ファイル名。失敗時は nil。
    static func writeContactSheet(
        directory: String,
        frameFiles: [String],
        refWidth: Int,
        refHeight: Int
    ) -> String? {
        let count = frameFiles.count
        guard count > 0, refWidth > 0, refHeight > 0 else { return nil }

        // セルサイズ: 参照アスペクトを保ったまま長辺を上限に収める。
        let maxCellLongSide = 320
        let longSide = max(refWidth, refHeight)
        let cellScale = min(1.0, Double(maxCellLongSide) / Double(longSide))
        let cellW = max(1, Int((Double(refWidth) * cellScale).rounded()))
        let cellH = max(1, Int((Double(refHeight) * cellScale).rounded()))

        let cols = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        let sheetW = cols * cellW
        let sheetH = rows * cellH

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: sheetW,
            height: sheetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 背景（暗いグレー）。
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // CG の原点は左下。上→下・左→右に並べ、画像が上下反転しないよう CTM を反転。
        ctx.translateBy(x: 0, y: CGFloat(sheetH))
        ctx.scaleBy(x: 1, y: -1)

        let dirURL = URL(fileURLWithPath: directory)
        for (i, name) in frameFiles.enumerated() {
            let url = dirURL.appendingPathComponent(name)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let col = i % cols
            let row = i / cols
            let cell = CGRect(
                x: col * cellW, y: row * cellH, width: cellW, height: cellH
            )
            ctx.draw(img, in: aspectFit(imageW: img.width, imageH: img.height, into: cell))
        }

        guard let sheet = ctx.makeImage() else { return nil }

        let name = "contact_sheet.png"
        let finalURL = dirURL.appendingPathComponent(name)
        let tmpURL = dirURL.appendingPathComponent(name + ".tmp")
        guard let dest = CGImageDestinationCreateWithURL(
            tmpURL as CFURL, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, sheet, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        atomicReplace(tmp: tmpURL, final: finalURL)
        return name
    }

    /// シーケンス manifest を `<directory>/sequence.json` に原子的に書き出します。
    ///
    /// 完了規約により、シーケンス出力のうち **最後に** 呼ぶこと。
    static func writeManifest(directory: String, manifest: ProbeSequenceManifest) {
        let dirURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )
        let finalURL = dirURL.appendingPathComponent("sequence.json")
        let tmpURL = dirURL.appendingPathComponent("sequence.json.tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: tmpURL)
            atomicReplace(tmp: tmpURL, final: finalURL)
        } catch {
            print("[metaphor] Probe: failed to write sequence.json: \(error)")
        }
    }

    // MARK: - Helpers

    /// 矩形 `rect` の中にアスペクト比を保って収めた矩形を返します（レターボックス）。
    private static func aspectFit(imageW: Int, imageH: Int, into rect: CGRect) -> CGRect {
        guard imageW > 0, imageH > 0 else { return rect }
        let scale = min(rect.width / CGFloat(imageW), rect.height / CGFloat(imageH))
        let w = CGFloat(imageW) * scale
        let h = CGFloat(imageH) * scale
        return CGRect(
            x: rect.minX + (rect.width - w) / 2,
            y: rect.minY + (rect.height - h) / 2,
            width: w, height: h
        )
    }

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

    /// RGBA8 ピクセル列を CGContext 経由で縮小します。
    ///
    /// - Returns: (縮小後ピクセル, 幅, 高さ)。失敗時は nil（呼び出し側はフルサイズで続行）。
    private static func scaleRGBA(
        pixels: [UInt8], width: Int, height: Int, scale: Float
    ) -> ([UInt8], Int, Int)? {
        let (outW, outH) = scaledSize(width: width, height: height, scale: scale)
        guard outW < width || outH < height else { return nil }

        var src = pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let srcCtx = CGContext(
            data: &src,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = srcCtx.makeImage() else {
            print("[metaphor] Probe: failed to build image for scaling — writing full size")
            return nil
        }

        var dst = [UInt8](repeating: 0, count: outW * outH * 4)
        let ok = dst.withUnsafeMutableBytes { buf -> Bool in
            guard let dstCtx = CGContext(
                data: buf.baseAddress,
                width: outW,
                height: outH,
                bitsPerComponent: 8,
                bytesPerRow: outW * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            dstCtx.interpolationQuality = .high
            dstCtx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
            return true
        }
        guard ok else {
            print("[metaphor] Probe: failed to scale frame — writing full size")
            return nil
        }
        return (dst, outW, outH)
    }

    /// RGBA8 ピクセルから PNG をエンコードして指定パスに書きます。
    private static func encodePNG(
        rgba: inout [UInt8], width: Int, height: Int, to url: URL
    ) {
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
                // ピクセルは writeNamed で RGBA に並べ替え済み
                let r = Float(pixels[i]) / 255.0
                let g = Float(pixels[i + 1]) / 255.0
                let b = Float(pixels[i + 2]) / 255.0
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
