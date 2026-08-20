import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers

/// ゴールデンイメージ回帰の基盤（Issue #330）。
///
/// レンダリング結果のフレームバッファ**全体**を保持し、
/// - SHA256 ハッシュ（同一環境での再現性チェック = 決定論の全画素版）
/// - 閾値つきピクセル比較（環境差を許容するゴールデン照合）
/// - 不一致時の PNG 書き出し（actual / expected / diff）
///
/// を提供する。`RenderTestHelper` が「1 ピクセルを読む」道具なのに対し、
/// こちらは「フレーム全体を固定する」道具。
///
/// ```swift
/// let image = try GoldenImage.readback(texture: tex, commandQueue: queue)
/// print(image.sha256)
/// try GoldenImageStore.verify(image, name: "shapes-2d", in: goldenDirectory)
/// ```
///
/// ゴールデンの更新手順は `docs/ai/README.md`「ゴールデンイメージ回帰」を参照。
public struct GoldenImage: Sendable, Equatable {

    /// 画像の幅（ピクセル）。
    public let width: Int
    /// 画像の高さ（ピクセル）。
    public let height: Int
    /// RGBA8、行優先、左上原点、非プリマルチプライ。
    public let rgba: [UInt8]

    /// RGBA8 バイト列から生成します。
    ///
    /// - Throws: バイト数が `width * height * 4` と一致しない場合 ``GoldenImageError/byteCountMismatch(expected:actual:)``
    public init(width: Int, height: Int, rgba: [UInt8]) throws {
        let expected = width * height * 4
        guard width > 0, height > 0, rgba.count == expected else {
            throw GoldenImageError.byteCountMismatch(expected: expected, actual: rgba.count)
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// Metal の読み戻し結果（BGRA8）を RGBA8 に並べ替えて生成します。
    ///
    /// - Throws: バイト数が `width * height * 4` と一致しない場合
    ///   ``GoldenImageError/byteCountMismatch(expected:actual:)``
    public static func fromBGRA(_ bgra: [UInt8], width: Int, height: Int) throws -> GoldenImage {
        let expected = width * height * 4
        guard bgra.count == expected else {
            throw GoldenImageError.byteCountMismatch(expected: expected, actual: bgra.count)
        }
        var rgba = [UInt8](repeating: 0, count: expected)
        for i in stride(from: 0, to: expected, by: 4) {
            rgba[i + 0] = bgra[i + 2]
            rgba[i + 1] = bgra[i + 1]
            rgba[i + 2] = bgra[i + 0]
            rgba[i + 3] = bgra[i + 3]
        }
        return try GoldenImage(width: width, height: height, rgba: rgba)
    }

    // MARK: - ハッシュ

    /// フレームバッファ全体の SHA256（16 進小文字）。
    ///
    /// 解像度が異なる画像が偶然同じバイト列になっても衝突しないよう、
    /// 寸法をヘッダとして混ぜてから画素を流し込む。
    public var sha256: String {
        var hasher = SHA256()
        hasher.update(data: Data("metaphor-golden/RGBA8/\(width)x\(height)\n".utf8))
        rgba.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 全画素が不透明（A=255）かどうか。
    ///
    /// 以前はゴールデンの前提条件（非不透明画素があると PNG 往復が非可逆）でしたが、
    /// 非可逆だったのは**バッファを premultiplied と宣言していたから**で、straight を
    /// straight として宣言すれば往復はバイト一致します（#850）。今は診断・検査用の情報。
    public var isOpaque: Bool {
        for i in stride(from: 3, to: rgba.count, by: 4) where rgba[i] != 255 { return false }
        return true
    }

    // MARK: - 比較

    /// もう一方の画像と画素単位で比較します。
    ///
    /// - Parameter channelTolerance: この値**以下**のチャンネル差は「許容範囲内」とみなす。
    public func compare(to other: GoldenImage, channelTolerance: Int = 0) -> GoldenComparison {
        guard width == other.width, height == other.height else {
            return GoldenComparison(
                sizeMatches: false,
                totalPixels: width * height,
                differingPixels: width * height,
                exceedingPixels: width * height,
                maxChannelDiff: 255,
                meanAbsoluteDiff: 255
            )
        }
        var differing = 0
        var exceeding = 0
        var maxDiff = 0
        var sumDiff = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            var pixelMax = 0
            for c in 0..<4 {
                let d = Int(rgba[i + c]) > Int(other.rgba[i + c])
                    ? Int(rgba[i + c]) - Int(other.rgba[i + c])
                    : Int(other.rgba[i + c]) - Int(rgba[i + c])
                sumDiff += d
                if d > pixelMax { pixelMax = d }
            }
            if pixelMax > 0 { differing += 1 }
            if pixelMax > channelTolerance { exceeding += 1 }
            if pixelMax > maxDiff { maxDiff = pixelMax }
        }
        let total = width * height
        return GoldenComparison(
            sizeMatches: true,
            totalPixels: total,
            differingPixels: differing,
            exceedingPixels: exceeding,
            maxChannelDiff: maxDiff,
            meanAbsoluteDiff: Double(sumDiff) / Double(total * 4)
        )
    }

    /// 許容差分の範囲内で一致するか。
    public func matches(_ other: GoldenImage, tolerance: GoldenTolerance) -> GoldenComparison {
        compare(to: other, channelTolerance: tolerance.maxChannelDiff)
    }

    /// 差分を可視化した画像を生成します（差の大きさを増幅した赤/黄のヒートマップ）。
    ///
    /// 1 でも差があれば見えるよう `amplification` 倍して 255 で飽和させる。
    public func diffImage(against other: GoldenImage, amplification: Int = 16) -> GoldenImage? {
        guard width == other.width, height == other.height else { return nil }
        var out = [UInt8](repeating: 0, count: rgba.count)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            var pixelMax = 0
            for c in 0..<4 {
                let d = abs(Int(rgba[i + c]) - Int(other.rgba[i + c]))
                if d > pixelMax { pixelMax = d }
            }
            let v = UInt8(min(255, pixelMax * amplification))
            out[i + 0] = v
            out[i + 1] = v / 4
            out[i + 2] = 0
            out[i + 3] = 255
        }
        return try? GoldenImage(width: width, height: height, rgba: out)
    }

    // MARK: - PNG 入出力

    /// PNG としてエンコードします。
    ///
    /// 色管理による値のズレを避けるため、書き込み・読み込みとも
    /// `CGColorSpaceCreateDeviceRGB()` で統一する（往復一致は
    /// `GoldenImageTests` の PNG ラウンドトリップテストで固定）。
    ///
    /// ``rgba`` は straight（非プリマルチプライ）なので、`CGImageAlphaInfo.last` で
    /// **そのとおりに宣言する**。以前は `premultipliedLast` と宣言していたため、
    /// ImageIO が PNG（straight）へ書くときに α で割って飽和させ、非不透明画素の
    /// 往復が壊れていた（α=128 の白で誤差 127。#850）。α=255 では両者は同値なので、
    /// 既存のゴールデン PNG はバイト単位で変わらない。
    ///
    /// - Throws: `CGImage` 化・PNG エンコードに失敗した場合
    ///   ``GoldenImageError/pngEncodingFailed``
    public func pngData() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            throw GoldenImageError.pngEncodingFailed
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw GoldenImageError.pngEncodingFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GoldenImageError.pngEncodingFailed
        }
        return data as Data
    }

    /// PNG ファイルを読み込みます。
    ///
    /// 8bit RGBA（straight）としてデコードできた PNG は**生サンプルをそのまま**採る。
    /// `CGContext` は straight alpha を扱えず `premultipliedLast` しか選べないため、
    /// 描き込ませると α が掛かって非不透明画素が変わってしまう（#850）。
    /// その形に載らない PNG だけ `CGContext` 経由で読み、CPU で割り戻す。
    ///
    /// - Throws: ``GoldenImageError``。読み込みに失敗した場合は
    ///   ``GoldenImageError/fileReadFailed(url:detail:)``、PNG として解釈できない
    ///   場合は ``GoldenImageError/pngDecodingFailed(_:)``。
    public static func load(pngAt url: URL) throws -> GoldenImage {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GoldenImageError.fileReadFailed(url: url, detail: error.localizedDescription)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw GoldenImageError.pngDecodingFailed(url)
        }
        if let straight = straightSamples(of: cgImage) {
            return try GoldenImage(width: cgImage.width, height: cgImage.height, rgba: straight)
        }
        return try GoldenImage(
            width: cgImage.width, height: cgImage.height,
            rgba: try premultipliedSamples(of: cgImage, url: url)
        )
    }

    /// 8bit RGBA（straight）としてデコード済みの `CGImage` から生サンプルを取り出します。
    /// 形が合わなければ `nil`（呼び出し側が `CGContext` 経由へ落ちる）。
    private static func straightSamples(of image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.alphaInfo == .last,
              let data = image.dataProvider?.data as Data? else { return nil }
        let w = image.width
        let h = image.height
        let stride = image.bytesPerRow
        guard data.count >= stride * h else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeBytes { src in
            let base = src.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<h {
                let row = base + y * stride
                bytes.withUnsafeMutableBytes { dst in
                    dst.baseAddress!.advanced(by: y * w * 4)
                        .copyMemory(from: row, byteCount: w * 4)
                }
            }
        }
        return bytes
    }

    /// `CGContext`（`premultipliedLast` しか選べない）で読んで straight へ割り戻します。
    private static func premultipliedSamples(of image: CGImage, url: URL) throws -> [UInt8] {
        let w = image.width
        let h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw GoldenImageError.pngDecodingFailed(url) }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Int(bytes[i + 3])
            guard a != 0, a != 255 else { continue }
            for ch in 0..<3 {
                bytes[i + ch] = UInt8(min(255, (Int(bytes[i + ch]) * 255 + a / 2) / a))
            }
        }
        return bytes
    }

    /// PNG ファイルとして書き出します（親ディレクトリは自動作成）。
    ///
    /// - Throws: ``GoldenImageError``。PNG 化に失敗した場合は
    ///   ``GoldenImageError/pngEncodingFailed``、書き出しに失敗した場合は
    ///   ``GoldenImageError/fileWriteFailed(url:detail:)``。
    public func write(pngTo url: URL) throws {
        let data = try pngData()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw GoldenImageError.fileWriteFailed(url: url, detail: error.localizedDescription)
        }
    }

    // MARK: - GPU 読み戻し

    /// Metal テクスチャ全体を CPU に読み戻して ``GoldenImage`` を作ります。
    ///
    /// プライベートストレージのオフスクリーンテクスチャをそのまま
    /// `getBytes` できないため、shared ステージングテクスチャへブリットしてから読む。
    ///
    /// - Throws: ``GoldenImageError``。BGRA8/RGBA8 以外のフォーマットなら
    ///   ``GoldenImageError/unsupportedPixelFormat(_:)``、ステージングテクスチャ・
    ///   コマンドバッファ・ブリットエンコーダを作れない場合は
    ///   ``GoldenImageError/stagingTextureCreationFailed``。
    ///   GPU 実行が完了しない場合は ``TestHelperError``。
    @MainActor
    public static func readback(
        texture: MTLTexture,
        commandQueue: MTLCommandQueue
    ) throws -> GoldenImage {
        guard texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .rgba8Unorm else {
            throw GoldenImageError.unsupportedPixelFormat(texture.pixelFormat)
        }
        let w = texture.width
        let h = texture.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let staging = texture.device.makeTexture(descriptor: desc) else {
            throw GoldenImageError.stagingTextureCreationFailed
        }
        guard let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder()
        else {
            throw GoldenImageError.stagingTextureCreationFailed
        }
        blit.copy(
            from: texture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: staging,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        try MetalTestHelper.commit(cb)

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(
            &bytes, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
        )
        return texture.pixelFormat == .bgra8Unorm
            ? try fromBGRA(bytes, width: w, height: h)
            : try GoldenImage(width: w, height: h, rgba: bytes)
    }
}

// MARK: - 比較結果

/// ``GoldenImage/compare(to:channelTolerance:)`` の結果。
public struct GoldenComparison: Sendable {
    /// 寸法が一致したか（false なら他のフィールドは最悪値）。
    public let sizeMatches: Bool
    /// 総ピクセル数。
    public let totalPixels: Int
    /// 1 でも差があるピクセル数。
    public let differingPixels: Int
    /// 許容チャンネル差を超えたピクセル数。
    public let exceedingPixels: Int
    /// 最大チャンネル差（0〜255）。
    public let maxChannelDiff: Int
    /// 全チャンネルの平均絶対差。
    public let meanAbsoluteDiff: Double

    /// 完全一致（1 ビットも違わない）か。
    public var isIdentical: Bool { sizeMatches && differingPixels == 0 }

    /// 許容差を超えたピクセルの割合。
    public var exceedingRatio: Double {
        totalPixels == 0 ? 0 : Double(exceedingPixels) / Double(totalPixels)
    }

    /// 失敗メッセージ用の要約。
    public var summary: String {
        guard sizeMatches else { return "画像サイズが不一致" }
        return String(
            format: "maxChannelDiff=%d, 差分ピクセル=%d/%d (%.4f%%), 許容超過=%d (%.4f%%), meanAbsDiff=%.3f",
            maxChannelDiff, differingPixels, totalPixels,
            totalPixels == 0 ? 0 : Double(differingPixels) / Double(totalPixels) * 100,
            exceedingPixels, exceedingRatio * 100, meanAbsoluteDiff
        )
    }
}

// MARK: - 許容差

/// ゴールデン照合の許容差。
///
/// 判定は「チャンネル差が `maxChannelDiff` を**超える**ピクセルの割合が
/// `maxExceedingRatio` 以下」。GPU 世代差による極小のラスタライズ揺れを
/// 吸収しつつ、意図しない見た目の変化（形・色が変わる）は確実に落とす。
public struct GoldenTolerance: Sendable {
    /// 許容する最大チャンネル差（この値以下の差は無視）。
    public var maxChannelDiff: Int
    /// 許容差を超えてよいピクセルの割合（0.0〜1.0）。
    public var maxExceedingRatio: Double

    public init(maxChannelDiff: Int, maxExceedingRatio: Double) {
        self.maxChannelDiff = maxChannelDiff
        self.maxExceedingRatio = maxExceedingRatio
    }

    /// 完全一致のみ許容（1 ビットも違わない）。
    public static let exact = GoldenTolerance(maxChannelDiff: 0, maxExceedingRatio: 0)

    /// 既定。GPU 世代差の量子化揺れ（±2/255）だけを吸収し、
    /// それを超える画素は 1 つも許さない。
    ///
    /// 実測（Issue #330）: 2D 図形・ブレンドモード・シャドウ・ポストプロセスの各シーンは
    /// GitHub Actions の macOS ランナーと手元の Apple Silicon で**バイト単位で一致**した
    /// （maxChannelDiff=0）。この許容差は現時点では使われていない安全余裕。
    public static let `default` = GoldenTolerance(maxChannelDiff: 2, maxExceedingRatio: 0)

    /// ライティング/ポストプロセスなど浮動小数の累積（pow/exp）があるシーン向け。
    ///
    /// 実測（Issue #330）: 環境差が出たのは PBR シーンのみで、**16384 画素中 1 画素が
    /// 1/255 ずれる**だけだった。ここはその実測値に対して振幅 4 倍・画素数 32 倍の
    /// 余裕を取った値。GPU 世代が増えて足りなくなったらログの実測値を根拠に見直す。
    public static let shaded = GoldenTolerance(maxChannelDiff: 4, maxExceedingRatio: 0.002)
}

// MARK: - ゴールデンの保存・照合

/// ゴールデン PNG の読み書きと照合。
///
/// - 一致 → パス（完全一致なら SHA256 も一致する）
/// - 不一致 → `actual` / `expected` / `diff` PNG を成果物ディレクトリへ書き出して失敗
/// - `METAPHOR_UPDATE_GOLDEN=1` → 照合せずゴールデンを上書き（意図した見た目変更時）
public enum GoldenImageStore {

    /// ゴールデン更新モードか（`METAPHOR_UPDATE_GOLDEN=1`）。
    public static var isUpdateMode: Bool {
        let value = ProcessInfo.processInfo.environment["METAPHOR_UPDATE_GOLDEN"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    /// 失敗時の成果物（actual / expected / diff PNG）の出力先。
    ///
    /// `METAPHOR_GOLDEN_ARTIFACT_DIR` で上書き可能。既定はカレントディレクトリ配下の
    /// `.build/golden-failures`（CI はここを artifact としてアップロードする）。
    public static var failureArtifactDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["METAPHOR_GOLDEN_ARTIFACT_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/golden-failures", isDirectory: true)
    }

    /// 実画像をゴールデンと照合します。
    ///
    /// - Parameters:
    ///   - actual: 今回レンダリングした画像
    ///   - name: ゴールデン名（`<name>.png` として保存）
    ///   - directory: ゴールデン PNG を置くディレクトリ
    ///   - tolerance: 許容差
    /// - Throws: ``GoldenImageError``。ゴールデン PNG の書き出しに失敗した場合は
    ///   ``GoldenImageError/pngEncodingFailed`` / ``GoldenImageError/fileWriteFailed(url:detail:)``、
    ///   既存ゴールデンの読み込みに失敗した場合は
    ///   ``GoldenImageError/fileReadFailed(url:detail:)`` /
    ///   ``GoldenImageError/pngDecodingFailed(_:)``。
    ///   不一致そのものはスローせず `Issue.record` で報告します。
    public static func verify(
        _ actual: GoldenImage,
        name: String,
        in directory: URL,
        tolerance: GoldenTolerance = .default,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let goldenURL = directory.appendingPathComponent("\(name).png")

        // 以前はここで「ゴールデンは不透明であること」を要求していた。PNG 往復が
        // 非可逆だったのはバッファを premultiplied と宣言していたからで、straight を
        // straight として書けば往復はバイト一致する（#850）。α<1 のシーンも照合できる。

        if isUpdateMode {
            try actual.write(pngTo: goldenURL)
            print("[golden] updated \(goldenURL.path) sha256=\(actual.sha256)")
            return
        }

        guard FileManager.default.fileExists(atPath: goldenURL.path) else {
            // 初回はゴールデンを作るが、レビュー無しに緑にはしない（CI では必ず失敗させる）。
            try actual.write(pngTo: goldenURL)
            Issue.record(
                """
                ゴールデン '\(name)' が存在しなかったので新規生成した: \(goldenURL.path)
                画像を目視で確認してコミットし、再実行すること（sha256=\(actual.sha256)）。
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        let expected = try GoldenImage.load(pngAt: goldenURL)
        let result = actual.matches(expected, tolerance: tolerance)
        // 環境差（CI の GPU と手元の GPU）がどれだけあるかを常時可視化する。
        // 許容差を将来詰める/緩める判断は、この実測ログを根拠にする。
        print("[golden] \(name) vs golden: \(result.summary)")
        // 「許容チャンネル差を超えたピクセルの割合」だけで判定する。
        // maxChannelDiff <= 許容値なら超過ピクセルは 0 になるので、この 1 条件で足りる。
        if result.sizeMatches && result.exceedingRatio <= tolerance.maxExceedingRatio { return }

        // 失敗時のデバッグ導線: actual / expected / diff を成果物として残す。
        let artifactDir = failureArtifactDirectory
        var paths: [String] = []
        do {
            let actualURL = artifactDir.appendingPathComponent("\(name).actual.png")
            let expectedURL = artifactDir.appendingPathComponent("\(name).expected.png")
            try actual.write(pngTo: actualURL)
            try expected.write(pngTo: expectedURL)
            paths.append(actualURL.path)
            paths.append(expectedURL.path)
            if let diff = actual.diffImage(against: expected) {
                let diffURL = artifactDir.appendingPathComponent("\(name).diff.png")
                try diff.write(pngTo: diffURL)
                paths.append(diffURL.path)
            }
        } catch {
            paths.append("(成果物の書き出しに失敗: \(error))")
        }

        Issue.record(
            """
            ゴールデン '\(name)' と不一致。
            \(result.summary)
            許容差: maxChannelDiff<=\(tolerance.maxChannelDiff), 超過ピクセル率<=\(tolerance.maxExceedingRatio)
            actual sha256=\(actual.sha256)
            expected sha256=\(expected.sha256)
            成果物: \(paths.joined(separator: ", "))
            意図した見た目変更なら METAPHOR_UPDATE_GOLDEN=1 swift test で更新して差分をレビューすること。
            """,
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - エラー

/// ``GoldenImage`` の入出力・変換エラー。
///
/// `GoldenImage` の throwing API はこの型だけを投げます（Foundation の生 `NSError` は
/// ``fileReadFailed(url:detail:)`` / ``fileWriteFailed(url:detail:)`` へ包みます）。
public enum GoldenImageError: Error, CustomStringConvertible {
    case byteCountMismatch(expected: Int, actual: Int)
    case pngEncodingFailed
    case pngDecodingFailed(URL)
    case unsupportedPixelFormat(MTLPixelFormat)
    case stagingTextureCreationFailed
    /// ファイルの読み込みに失敗した（不在・権限・I/O エラー）。
    case fileReadFailed(url: URL, detail: String)
    /// ファイルの書き出しに失敗した（権限・ディスク空き容量など）。
    case fileWriteFailed(url: URL, detail: String)

    public var description: String {
        switch self {
        case .byteCountMismatch(let expected, let actual):
            "RGBA8 バイト数が不一致: expected=\(expected) actual=\(actual)"
        case .pngEncodingFailed:
            "PNG エンコードに失敗"
        case .pngDecodingFailed(let url):
            "PNG デコードに失敗: \(url.path)"
        case .fileReadFailed(let url, let detail):
            "ファイルの読み込みに失敗: \(url.path): \(detail)"
        case .fileWriteFailed(let url, let detail):
            "ファイルの書き出しに失敗: \(url.path): \(detail)"
        case .unsupportedPixelFormat(let format):
            "未対応のピクセルフォーマット: \(format.rawValue)（bgra8Unorm / rgba8Unorm のみ）"
        case .stagingTextureCreationFailed:
            "読み戻し用ステージングリソースの作成に失敗"
        }
    }
}
