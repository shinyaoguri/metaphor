import Testing

@testable import MetaphorCore

/// CPU フィルタの全タイプ。MPS 系は CPU 経路では no-op だが、
/// 「不整合バッファでも落ちない」契約は同じなので一緒に叩く。
///
/// `@Test(arguments:)` は Suite の外（nonisolated）から評価されるため、
/// `@MainActor` な Suite の static プロパティには置けない。
private let allFilters: [FilterType] = [
    .threshold(0.5), .gray, .invert, .posterize(4), .blur(2),
    .erode, .dilate, .edgeDetect, .sharpen(1.5), .sepia, .pixelate(3),
    .mpsBlur(sigma: 2), .mpsSobel, .mpsLaplacian, .mpsErode(radius: 1),
    .mpsDilate(radius: 1), .mpsMedian(diameter: 3), .mpsThreshold(0.5),
]

/// `pixels` の長さが `width * height * 4` に一致しない不正な入力。
///
/// `applyToPixels()` は public なので、MImage を経由せず外部バッファへ直接使える。
/// 修正前は入り口で何も検証しておらず、
/// - 4 の倍数でない長さ → 4 バイト刻みフィルタが `pixels[i + 1]` で範囲外
/// - 長さと寸法の不一致 → 空間フィルタが `(y * width + x) * 4` で範囲外
/// - 負の寸法 → `0..<height` が逆順 Range でトラップ
/// のいずれもプロセスを終了させていた（`throws` では拾えない）。
private struct MalformedBuffer: Sendable, CustomTestStringConvertible {
    let name: String
    let count: Int
    let width: Int
    let height: Int

    var testDescription: String { name }
}

private let malformedBuffers: [MalformedBuffer] = [
    MalformedBuffer(name: "4 の倍数でない (1)", count: 1, width: 1, height: 1),
    MalformedBuffer(name: "4 の倍数でない (5)", count: 5, width: 1, height: 1),
    MalformedBuffer(name: "4 の倍数でない (7)", count: 7, width: 1, height: 1),
    MalformedBuffer(name: "長さが寸法より短い", count: 16, width: 4, height: 4),
    MalformedBuffer(name: "長さが寸法より長い", count: 256, width: 4, height: 4),
    MalformedBuffer(name: "負の幅", count: 16, width: -2, height: 2),
    MalformedBuffer(name: "負の高さ", count: 16, width: 2, height: -2),
    MalformedBuffer(name: "寸法の積がオーバーフロー", count: 16, width: Int.max, height: Int.max),
]

/// 不整合な RGBA バッファでも `applyToPixels()` が落ちないことを固定する（Issue #582）。
@Suite("ImageFilter バッファ検証")
@MainActor
struct ImageFilterBufferGuardTests {

    @Test("寸法と長さが一致しない入力は no-op（クラッシュしない）",
          arguments: malformedBuffers, allFilters)
    fileprivate func malformedBuffersAreNoOp(buffer: MalformedBuffer, filter: FilterType) {
        let original = [UInt8](repeating: 128, count: buffer.count)
        var pixels = original
        ImageFilter.applyToPixels(filter, pixels: &pixels, width: buffer.width, height: buffer.height)
        #expect(pixels == original, "\(buffer.name)")
    }

    @Test("0 寸法・空バッファは no-op", arguments: allFilters)
    func emptyBufferIsNoOp(filter: FilterType) {
        var pixels: [UInt8] = []
        ImageFilter.applyToPixels(filter, pixels: &pixels, width: 0, height: 0)
        #expect(pixels.isEmpty)
    }

    @Test("整合した RGBA バッファは従来どおり処理される")
    func validBufferStillFilters() {
        // 4x4 のグラデーション（invert / blur が確実に値を変える）
        var pixels = [UInt8]()
        for i in 0..<16 {
            pixels.append(contentsOf: [UInt8(i * 16), UInt8(255 - i * 16), 64, 255])
        }
        let original = pixels

        ImageFilter.applyToPixels(.invert, pixels: &pixels, width: 4, height: 4)
        #expect(pixels[0] == 255 - original[0])
        #expect(pixels[3] == original[3], "アルファは保持される")

        // 空間フィルタも整合入力では動く
        var blurred = original
        ImageFilter.applyToPixels(.blur(1), pixels: &blurred, width: 4, height: 4)
        #expect(blurred != original)
        #expect(blurred.count == original.count)
    }
}
