import Metal

// MARK: - Filter Type

/// 画像フィルタの種類（Processing互換 + 拡張）
public enum FilterType: Sendable {
    /// 閾値フィルタ（0.0〜1.0）
    case threshold(Float)
    /// グレースケール変換
    case gray
    /// 色反転
    case invert
    /// ポスタライズ（2〜255段階）
    case posterize(Int)
    /// ぼかし（半径）
    case blur(Int)
    /// 収縮（暗い部分を拡大）
    case erode
    /// 膨張（明るい部分を拡大）
    case dilate
    /// エッジ検出（Sobelフィルタ）
    case edgeDetect
    /// シャープ化（amount: 強度、0.5〜3.0推奨）
    case sharpen(Float)
    /// セピア調
    case sepia
    /// ピクセレート（ブロックサイズ）
    case pixelate(Int)
}

// MARK: - Image Filter (CPU)

/// MImageのpixels配列に対してフィルタを適用するユーティリティ
///
/// 使用前にloadPixels()、使用後にupdatePixels()が必要。
@MainActor
public enum ImageFilter {

    /// MImageにフィルタを適用（loadPixels→処理→updatePixels を一括実行）
    public static func apply(_ filter: FilterType, to image: MImage) {
        image.loadPixels()
        guard !image.pixels.isEmpty else { return }
        applyToPixels(filter, pixels: &image.pixels, width: Int(image.width), height: Int(image.height))
        image.updatePixels()
    }

    /// ピクセル配列に直接フィルタを適用
    public static func applyToPixels(_ filter: FilterType, pixels: inout [UInt8], width: Int, height: Int) {
        switch filter {
        case .threshold(let level):
            applyThreshold(pixels: &pixels, level: level)
        case .gray:
            applyGray(pixels: &pixels)
        case .invert:
            applyInvert(pixels: &pixels)
        case .posterize(let levels):
            applyPosterize(pixels: &pixels, levels: max(2, min(255, levels)))
        case .blur(let radius):
            applyBlur(pixels: &pixels, width: width, height: height, radius: max(1, radius))
        case .erode:
            applyErodeOrDilate(pixels: &pixels, width: width, height: height, erode: true)
        case .dilate:
            applyErodeOrDilate(pixels: &pixels, width: width, height: height, erode: false)
        case .edgeDetect:
            applyEdgeDetect(pixels: &pixels, width: width, height: height)
        case .sharpen(let amount):
            applySharpen(pixels: &pixels, width: width, height: height, amount: amount)
        case .sepia:
            applySepia(pixels: &pixels)
        case .pixelate(let blockSize):
            applyPixelate(pixels: &pixels, width: width, height: height, blockSize: max(1, blockSize))
        }
    }

    // MARK: - Private Filter Implementations

    private static func applyThreshold(pixels: inout [UInt8], level: Float) {
        let threshold = UInt8(max(0, min(255, level * 255)))
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luma = UInt8((UInt16(pixels[i]) * 77 + UInt16(pixels[i + 1]) * 150 + UInt16(pixels[i + 2]) * 29) >> 8)
            let val: UInt8 = luma >= threshold ? 255 : 0
            pixels[i] = val
            pixels[i + 1] = val
            pixels[i + 2] = val
        }
    }

    private static func applyGray(pixels: inout [UInt8]) {
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luma = UInt8((UInt16(pixels[i]) * 77 + UInt16(pixels[i + 1]) * 150 + UInt16(pixels[i + 2]) * 29) >> 8)
            pixels[i] = luma
            pixels[i + 1] = luma
            pixels[i + 2] = luma
        }
    }

    private static func applyInvert(pixels: inout [UInt8]) {
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 255 - pixels[i]
            pixels[i + 1] = 255 - pixels[i + 1]
            pixels[i + 2] = 255 - pixels[i + 2]
        }
    }

    private static func applyPosterize(pixels: inout [UInt8], levels: Int) {
        let levelsF = Float(levels - 1)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8((Float(pixels[i]) / 255.0 * levelsF).rounded() / levelsF * 255)
            pixels[i + 1] = UInt8((Float(pixels[i + 1]) / 255.0 * levelsF).rounded() / levelsF * 255)
            pixels[i + 2] = UInt8((Float(pixels[i + 2]) / 255.0 * levelsF).rounded() / levelsF * 255)
        }
    }

    private static func applyBlur(pixels: inout [UInt8], width: Int, height: Int, radius: Int) {
        // Box blur（高速近似）
        var temp = pixels

        // 水平パス
        for y in 0..<height {
            for x in 0..<width {
                var rSum: Int = 0, gSum: Int = 0, bSum: Int = 0, aSum: Int = 0
                var count: Int = 0
                for dx in -radius...radius {
                    let sx = x + dx
                    guard sx >= 0, sx < width else { continue }
                    let i = (y * width + sx) * 4
                    rSum += Int(pixels[i])
                    gSum += Int(pixels[i + 1])
                    bSum += Int(pixels[i + 2])
                    aSum += Int(pixels[i + 3])
                    count += 1
                }
                let i = (y * width + x) * 4
                temp[i] = UInt8(rSum / count)
                temp[i + 1] = UInt8(gSum / count)
                temp[i + 2] = UInt8(bSum / count)
                temp[i + 3] = UInt8(aSum / count)
            }
        }

        // 垂直パス
        for y in 0..<height {
            for x in 0..<width {
                var rSum: Int = 0, gSum: Int = 0, bSum: Int = 0, aSum: Int = 0
                var count: Int = 0
                for dy in -radius...radius {
                    let sy = y + dy
                    guard sy >= 0, sy < height else { continue }
                    let i = (sy * width + x) * 4
                    rSum += Int(temp[i])
                    gSum += Int(temp[i + 1])
                    bSum += Int(temp[i + 2])
                    aSum += Int(temp[i + 3])
                    count += 1
                }
                let i = (y * width + x) * 4
                pixels[i] = UInt8(rSum / count)
                pixels[i + 1] = UInt8(gSum / count)
                pixels[i + 2] = UInt8(bSum / count)
                pixels[i + 3] = UInt8(aSum / count)
            }
        }
    }

    private static func applyEdgeDetect(pixels: inout [UInt8], width: Int, height: Int) {
        let temp = pixels
        for y in 0..<height {
            for x in 0..<width {
                var gx: Float = 0, gy: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let sx = max(0, min(width - 1, x + dx))
                        let sy = max(0, min(height - 1, y + dy))
                        let i = (sy * width + sx) * 4
                        let luma = Float(temp[i]) * 0.299 + Float(temp[i + 1]) * 0.587 + Float(temp[i + 2]) * 0.114
                        let wx = Float(dx) * (dy == 0 ? 2.0 : 1.0)
                        let wy = Float(dy) * (dx == 0 ? 2.0 : 1.0)
                        gx += luma * wx
                        gy += luma * wy
                    }
                }
                let edge = min(255, max(0, Int(sqrt(gx * gx + gy * gy))))
                let i = (y * width + x) * 4
                pixels[i] = UInt8(edge)
                pixels[i + 1] = UInt8(edge)
                pixels[i + 2] = UInt8(edge)
            }
        }
    }

    private static func applySharpen(pixels: inout [UInt8], width: Int, height: Int, amount: Float) {
        let temp = pixels
        for y in 0..<height {
            for x in 0..<width {
                let ci = (y * width + x) * 4
                var nr: Float = 0, ng: Float = 0, nb: Float = 0
                var count: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let sx = max(0, min(width - 1, x + dx))
                        let sy = max(0, min(height - 1, y + dy))
                        let i = (sy * width + sx) * 4
                        nr += Float(temp[i])
                        ng += Float(temp[i + 1])
                        nb += Float(temp[i + 2])
                        count += 1
                    }
                }
                nr /= count; ng /= count; nb /= count
                let r = Float(temp[ci]) + (Float(temp[ci]) - nr) * amount
                let g = Float(temp[ci + 1]) + (Float(temp[ci + 1]) - ng) * amount
                let b = Float(temp[ci + 2]) + (Float(temp[ci + 2]) - nb) * amount
                pixels[ci] = UInt8(max(0, min(255, r)))
                pixels[ci + 1] = UInt8(max(0, min(255, g)))
                pixels[ci + 2] = UInt8(max(0, min(255, b)))
            }
        }
    }

    private static func applySepia(pixels: inout [UInt8]) {
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i]), g = Float(pixels[i + 1]), b = Float(pixels[i + 2])
            pixels[i] = UInt8(min(255, r * 0.393 + g * 0.769 + b * 0.189))
            pixels[i + 1] = UInt8(min(255, r * 0.349 + g * 0.686 + b * 0.168))
            pixels[i + 2] = UInt8(min(255, r * 0.272 + g * 0.534 + b * 0.131))
        }
    }

    private static func applyPixelate(pixels: inout [UInt8], width: Int, height: Int, blockSize: Int) {
        let temp = pixels
        for y in 0..<height {
            for x in 0..<width {
                let bx = (x / blockSize) * blockSize
                let by = (y / blockSize) * blockSize
                let si = (by * width + bx) * 4
                let di = (y * width + x) * 4
                pixels[di] = temp[si]
                pixels[di + 1] = temp[si + 1]
                pixels[di + 2] = temp[si + 2]
                pixels[di + 3] = temp[si + 3]
            }
        }
    }

    private static func applyErodeOrDilate(pixels: inout [UInt8], width: Int, height: Int, erode: Bool) {
        let temp = pixels
        for y in 0..<height {
            for x in 0..<width {
                var bestR = erode ? UInt8(255) : UInt8(0)
                var bestG = erode ? UInt8(255) : UInt8(0)
                var bestB = erode ? UInt8(255) : UInt8(0)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let sx = x + dx
                        let sy = y + dy
                        guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                        let i = (sy * width + sx) * 4
                        if erode {
                            bestR = min(bestR, temp[i])
                            bestG = min(bestG, temp[i + 1])
                            bestB = min(bestB, temp[i + 2])
                        } else {
                            bestR = max(bestR, temp[i])
                            bestG = max(bestG, temp[i + 1])
                            bestB = max(bestB, temp[i + 2])
                        }
                    }
                }
                let i = (y * width + x) * 4
                pixels[i] = bestR
                pixels[i + 1] = bestG
                pixels[i + 2] = bestB
            }
        }
    }
}
