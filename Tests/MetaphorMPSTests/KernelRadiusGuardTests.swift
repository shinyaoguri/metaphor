import Testing
import Metal
import MetalPerformanceShaders
@testable import MetaphorCore
@testable import MetaphorMPS

// MARK: - MPSImageFilter のカーネル半径 (Issue #893)

/// `erode` / `dilate` / `median` へ不正な半径・直径を渡したときの入口ガード。
///
/// 修正前は 3 通りの壊れ方をしていた。どれも `MPSImageFilterWrapper` の
/// メソッドが `Void` を返す以上、呼び出し側では表現も捕捉もできない:
///
/// - `erode(radius: -1)` … カーネル幅が負のまま `NSUInteger` へ渡り、
///   `waitUntilCompleted()` から**二度と戻らない**（abort ですらないハング）
/// - `erode(radius: Int.max)` … `radius * 2 + 1` が `Int` をオーバーフローして SIGTRAP
/// - `median(diameter: 1001)` … MPS のアサーションで `Abort trap: 6`
///   （`Kernel diameter (1001) is larger than the supported max ... (127)`）
@Suite("MPSImageFilter のカーネル半径", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MPSImageFilterKernelRadiusTests {

    /// 一辺 8px の検査用画像。中央付近に 1 点だけ暗い画素を置き、
    /// erode / dilate が実際に効いたかを画素で見分けられるようにする。
    private static let side = 8

    /// 全画素 200、`(1, 1)` だけ 0 の BGRA パターン。
    private static func makePattern() -> [UInt8] {
        var pixels = [UInt8](repeating: 200, count: side * side * 4)
        let idx = (1 * side + 1) * 4
        for channel in 0..<4 { pixels[idx + channel] = 0 }
        return pixels
    }

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

    /// `encode` 系 API を 1 回まわして出力画素を読み戻す。
    ///
    /// スタンドアロン API（`erode(_:radius:)`）の出力先は `.private` テクスチャなので
    /// 読み戻せない。同じクランプを通る `encodeErode` / `encodeDilate` / `encodeMedian`
    /// を `.shared` テクスチャで叩き、絵まで突き合わせる。
    private func run(
        _ device: MTLDevice, _ queue: MTLCommandQueue,
        _ body: (MPSImageFilterWrapper, MTLCommandBuffer, MTLTexture, MTLTexture) -> Void
    ) throws -> [UInt8] {
        let wrapper = MPSImageFilterWrapper(device: device, commandQueue: queue)
        let source = try makeTexture(device, bytes: Self.makePattern())
        let destination = try makeTexture(device, bytes: nil)
        let cb = try #require(queue.makeCommandBuffer())
        body(wrapper, cb, source, destination)
        cb.commit()
        cb.waitUntilCompleted()
        return readBack(destination)
    }

    private func erode(radius: Int) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        return try run(device, queue) { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: radius)
        }
    }

    private func dilate(radius: Int) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        return try run(device, queue) { wrapper, cb, src, dst in
            wrapper.encodeDilate(commandBuffer: cb, source: src, destination: dst, radius: radius)
        }
    }

    private func median(diameter: Int) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        return try run(device, queue) { wrapper, cb, src, dst in
            wrapper.encodeMedian(
                commandBuffer: cb, source: src, destination: dst, diameter: diameter)
        }
    }

    // MARK: 負の半径（修正前はプロセスが固まっていた）

    /// 半径 0 は 1x1 カーネル = 恒等。負の半径はそこへ丸める。
    @Test("負の erode 半径は 0 へ丸められる", arguments: [-1, -2, -8, Int.min])
    func negativeErodeRadiusClampsToZero(radius: Int) throws {
        #expect(try erode(radius: radius) == Self.makePattern())
    }

    @Test("負の dilate 半径は 0 へ丸められる", arguments: [-1, -2, -8, Int.min])
    func negativeDilateRadiusClampsToZero(radius: Int) throws {
        #expect(try dilate(radius: radius) == Self.makePattern())
    }

    // MARK: 巨大な半径（修正前は radius * 2 + 1 が Int をオーバーフローして SIGTRAP）

    /// 上限は「長辺 - 1」。`edgeMode = .clamp` の窓が全画素で画像全体を覆いきる半径なので、
    /// そこから先は何を渡しても出力は全画素が全体の min（erode）に飽和する。
    @Test("巨大な erode 半径は飽和した絵に落ち着く", arguments: [Int.max, 1 << 40, 1_000_000, 64])
    func hugeErodeRadiusSaturates(radius: Int) throws {
        let saturated = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        #expect(try erode(radius: radius) == saturated)
        // 上限そのもの（長辺 - 1）と同じ絵であること = クランプで絵が変わっていないこと
        #expect(try erode(radius: Self.side - 1) == saturated)
    }

    @Test("巨大な dilate 半径は飽和した絵に落ち着く", arguments: [Int.max, 1 << 40, 1_000_000, 64])
    func hugeDilateRadiusSaturates(radius: Int) throws {
        let saturated = [UInt8](repeating: 200, count: Self.side * Self.side * 4)
        #expect(try dilate(radius: radius) == saturated)
        #expect(try dilate(radius: Self.side - 1) == saturated)
    }

    // MARK: ガードが効きすぎていないこと

    /// 半径 0 は素通し、半径 1 は 3x3 の窓で 1 点の暗部を広げる。
    /// クランプが正当な半径まで潰していたら、この期待値と合わなくなる。
    @Test("正当な erode 半径はそのまま効く")
    func validErodeRadiusStillFilters() throws {
        #expect(try erode(radius: 0) == Self.makePattern(), "半径 0 は 1x1 カーネル = 恒等")

        let out = try erode(radius: 1)
        #expect(out != Self.makePattern(), "半径 1 は暗部を広げるので絵が変わる")
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let expected: UInt8 = (abs(x - 1) <= 1 && abs(y - 1) <= 1) ? 0 : 200
                let value = out[(y * Self.side + x) * 4]
                #expect(value == expected, "(\(x), \(y)) は \(expected) のはず")
            }
        }
    }

    @Test("正当な dilate 半径はそのまま効く")
    func validDilateRadiusStillFilters() throws {
        #expect(try dilate(radius: 0) == Self.makePattern(), "半径 0 は 1x1 カーネル = 恒等")
        // 1 点の暗部は 3x3 の最大値で埋め戻される
        #expect(try dilate(radius: 1) == [UInt8](repeating: 200, count: Self.side * Self.side * 4))
    }

    // MARK: median の直径（修正前は上限超えで Abort trap: 6）

    /// デバイスが返す上限（Apple Silicon では 127）を超える直径。
    @Test("上限を超える median の直径はデバイスの上限へ丸められる")
    func oversizedMedianDiameterClamps() throws {
        let cap = MPSImageMedian.maxKernelDiameter()
        #expect(try median(diameter: 1001) == (try median(diameter: cap)))
    }

    /// 0・負数・偶数。奇数かつ下限以上へ丸める（doc が宣言している契約）。
    @Test("下限未満と偶数の median の直径は丸められる", arguments: [(0, 3), (-1, 3), (Int.min, 3), (2, 3), (4, 5)])
    func belowMinimumMedianDiameterClamps(input: Int, expected: Int) throws {
        #expect(try median(diameter: input) == (try median(diameter: expected)))
    }

    /// ガードが効きすぎていないこと。範囲内の奇数はそのまま通り、
    /// 直径ごとに違う絵（= 違うカーネル）になる。
    @Test("正当な median の直径はそのまま効く")
    func validMedianDiameterStillFilters() throws {
        let d3 = try median(diameter: 3)
        // 1 点だけの外れ値は 3x3 の中央値では残らない（内側の画素で見る。
        // median の edgeMode は既定の `.zero` なので縁は画像の外の 0 を拾う）
        #expect(d3[(1 * Self.side + 1) * 4] == 200)
        // 直径が違えば違う絵になる = 3 も 5 も丸められずそのまま届いている
        #expect(try median(diameter: 5) != d3)
    }
}
