import Testing
import Metal
import MetalPerformanceShaders
@testable import MetaphorCore
@testable import MetaphorMPS

// MARK: - median の edgeMode (Issue #920)

/// `median` が画像の外を「黒」として読まないことを固定する。
///
/// `MPSUnaryImageKernel` の既定の `edgeMode` は `.zero`（画像の外は 0）。
/// 同じファイルの `gaussianBlur` / `erode` / `dilate` は `.clamp` を明示していたのに
/// `median` だけ設定が抜けており、**median を掛けただけで縁が暗く落ちて**いました。
///
/// median は「窓の中の値を 1 つ選ぶ」フィルタなので、出力は入力に無い値になりません。
/// ところが画像の外から 0 を借りてくると、窓の半分以上が 0 になる縁で中央値が 0 に
/// なり、**入力に存在しない黒**が出ます。他の 3 つと揃えるという以前に、
/// フィルタ自身の性質に反しています。
@Suite("median の edgeMode", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MedianEdgeModeTests {

    private static let side = 32
    private static let level: UInt8 = 200

    private func makeTexture(_ device: MTLDevice, bytes: [UInt8]?) throws -> MTLTexture {
        let side = Self.side
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: desc))
        if let bytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                withBytes: bytes, bytesPerRow: side * 4)
        }
        return texture
    }

    private func readBack(_ texture: MTLTexture) -> [UInt8] {
        let side = Self.side
        var out = [UInt8](repeating: 0, count: side * side * 4)
        out.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!, bytesPerRow: side * 4,
                from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        }
        return out
    }

    /// `source` を 1 回だけフィルタして出力画素を読み戻す。
    private func run(
        source pixels: [UInt8],
        _ body: (MPSImageFilterWrapper, MTLCommandBuffer, MTLTexture, MTLTexture) -> Void
    ) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        let wrapper = MPSImageFilterWrapper(device: device, commandQueue: queue)
        let source = try makeTexture(device, bytes: pixels)
        let destination = try makeTexture(device, bytes: nil)
        let cb = try #require(queue.makeCommandBuffer())
        body(wrapper, cb, source, destination)
        cb.commit()
        cb.waitUntilCompleted()
        return readBack(destination)
    }

    /// 全画素が同じ明るさの画像。
    private static func uniform() -> [UInt8] {
        [UInt8](repeating: level, count: side * side * 4)
    }

    /// 最も暗い画素の値（縁が落ちていればここに出る）。
    private func darkest(_ pixels: [UInt8]) -> UInt8 { pixels.min() ?? 0 }

    // MARK: 縁が暗くならないこと

    /// 一様な画像は median を掛けても一様なまま。
    ///
    /// 修正前は四隅から `diameter / 2` 画素ぶんが 0 に落ちていた
    /// （直径 9 なら窓 81 サンプルのうち 56 が画像外の 0 になり、中央値が 0 になる）。
    @Test("一様な画像に median を掛けても縁が暗くならない", arguments: [3, 5, 9, 15])
    func medianKeepsUniformImageUniform(diameter: Int) throws {
        let out = try run(source: Self.uniform()) { wrapper, cb, src, dst in
            wrapper.encodeMedian(
                commandBuffer: cb, source: src, destination: dst, diameter: diameter)
        }
        #expect(darkest(out) == Self.level,
                "直径 \(diameter): 入力に無い暗い画素が出た（最小値 \(darkest(out))）")
        #expect(out == Self.uniform())
    }

    /// 同じファイルの 4 フィルタが縁の扱いで揃っていること。
    /// `median` だけ既定の `.zero` のまま取り残されていたのが Issue #920。
    @Test("一様な画像では 4 つのフィルタが同じ答えを返す")
    func allFiltersAgreeOnUniformImage() throws {
        let uniform = Self.uniform()

        let blurred = try run(source: uniform) { wrapper, cb, src, dst in
            wrapper.encodeGaussianBlur(commandBuffer: cb, source: src, destination: dst, sigma: 3)
        }
        let eroded = try run(source: uniform) { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: 4)
        }
        let dilated = try run(source: uniform) { wrapper, cb, src, dst in
            wrapper.encodeDilate(commandBuffer: cb, source: src, destination: dst, radius: 4)
        }
        let medianed = try run(source: uniform) { wrapper, cb, src, dst in
            wrapper.encodeMedian(commandBuffer: cb, source: src, destination: dst, diameter: 9)
        }

        // gaussian は畳み込みなので厳密一致は求めず、暗く落ちていないことだけ見る
        #expect(darkest(blurred) >= Self.level - 1, "gaussianBlur で縁が落ちた")
        #expect(darkest(eroded) == Self.level, "erode で縁が落ちた")
        #expect(darkest(dilated) == Self.level, "dilate で縁が落ちた")
        #expect(darkest(medianed) == Self.level, "median で縁が落ちた")
    }

    // MARK: フィルタとしては効いたままであること

    /// 縁を直したせいで中身が効かなくなっていないこと。
    /// 1 画素の外れ値は消え、暗部が窓より大きければ残る。
    ///
    /// 暗くするのは RGB の 3 チャンネルだけにする。`MPSImageMedian` はアルファを
    /// 中央値の対象にせずそのまま通すため（実測）、アルファまで 0 にすると
    /// 「消えなかった」ように見えてしまう。
    @Test("median は中身のフィルタとしてはこれまでどおり効く")
    func medianStillFilters() throws {
        var speckled = Self.uniform()
        let center = (16 * Self.side + 16) * 4
        for channel in 0..<3 { speckled[center + channel] = 0 }

        let despeckled = try run(source: speckled) { wrapper, cb, src, dst in
            wrapper.encodeMedian(commandBuffer: cb, source: src, destination: dst, diameter: 3)
        }
        #expect(despeckled == Self.uniform(), "1 画素の外れ値が中央値で消えていない")

        // 窓より大きい暗部（5x5）は直径 3 では残り、直径 9 では消える = 直径が効いている
        var blotched = Self.uniform()
        for y in 14..<19 {
            for x in 14..<19 {
                for channel in 0..<3 { blotched[(y * Self.side + x) * 4 + channel] = 0 }
            }
        }
        let kept = try run(source: blotched) { wrapper, cb, src, dst in
            wrapper.encodeMedian(commandBuffer: cb, source: src, destination: dst, diameter: 3)
        }
        let erased = try run(source: blotched) { wrapper, cb, src, dst in
            wrapper.encodeMedian(commandBuffer: cb, source: src, destination: dst, diameter: 9)
        }
        #expect(kept[center] == 0, "直径 3 では 5x5 の暗部が残るはず")
        #expect(erased[center] == Self.level, "直径 9 では 5x5 の暗部が消えるはず")
    }
}
