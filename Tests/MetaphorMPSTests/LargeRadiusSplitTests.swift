import Testing
import Metal
import MetalPerformanceShaders
@testable import MetaphorCore
@testable import MetaphorMPS

// MARK: - 大きな erode / dilate 半径の分割適用 (Issue #919)

/// カーネル幅が 483（半径 241）以上になると `MPSImageAreaMin` / `MPSImageAreaMax` の
/// GPU コマンドが完了しなくなる（`waitUntilCompleted()` から CPU 0% でブロックしたまま
/// 戻らない。abort でもコマンドバッファのエラーでもないのでログすら出ない）。
/// 実測ではテクスチャの大きさと無関係で、幅 481 = 半径 240 までは 64x64 でも
/// 2048x2048 でも 12〜59ms で返ります。
///
/// #893 のクランプは半径を「長辺 - 1」までしか縮めないので、長辺 242px 以上の
/// キャンバスなら**正当な引数のまま**踏めます。そこで崖より手前で切って多段に分けます。
/// 平坦な構造要素の erosion / dilation は `erode(r1 + r2) == erode(r2) ∘ erode(r1)` と
/// 分解でき、`edgeMode = .clamp` でも成り立つので、分けても**絵は変わりません**。
@Suite("大きな半径の分割適用", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MPSLargeRadiusSplitTests {

    /// 半径 511 まで #893 のクランプに掛からない大きさ。
    private static let side = 512

    /// 決定的な模様（一様だと分割の誤りが見えない）。
    private static func pattern() -> [UInt8] {
        var px = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                px[i] = UInt8((x &* 37 &+ y &* 91) % 256)
                px[i + 1] = UInt8((x &* 13 &+ y &* 7) % 256)
                px[i + 2] = UInt8((x &+ y) % 256)
                px[i + 3] = 255
            }
        }
        return px
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

    /// ライブラリの API を 1 回まわす。
    private func filtered(
        _ body: (MPSImageFilterWrapper, MTLCommandBuffer, MTLTexture, MTLTexture) -> Void
    ) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        let wrapper = MPSImageFilterWrapper(device: device, commandQueue: queue)
        let source = try makeTexture(device, bytes: Self.pattern())
        let destination = try makeTexture(device, bytes: nil)
        let cb = try #require(queue.makeCommandBuffer())
        body(wrapper, cb, source, destination)
        cb.commit()
        cb.waitUntilCompleted()
        return readBack(destination)
    }

    /// 突き合わせ用の真値。MPS のカーネルを直に組んで半径を順に当てる。
    ///
    /// 崖（半径 241）より下の半径しか使わないので、この経路は必ず返ってくる。
    private func reference(radii: [Int], max: Bool = false) throws -> [UInt8] {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        var current = try makeTexture(device, bytes: Self.pattern())
        for radius in radii {
            let out = try makeTexture(device, bytes: nil)
            let size = radius * 2 + 1
            let kernel: MPSUnaryImageKernel = max
                ? MPSImageAreaMax(device: device, kernelWidth: size, kernelHeight: size)
                : MPSImageAreaMin(device: device, kernelWidth: size, kernelHeight: size)
            kernel.edgeMode = .clamp
            let cb = try #require(queue.makeCommandBuffer())
            kernel.encode(commandBuffer: cb, sourceTexture: current, destinationTexture: out)
            cb.commit()
            cb.waitUntilCompleted()
            current = out
        }
        return readBack(current)
    }

    // MARK: 分割の割り振り

    @Test("上限以下の半径は 1 パスのまま", arguments: [0, 1, 3, 20, 119, 120])
    func smallRadiusStaysSinglePass(radius: Int) {
        #expect(MPSImageFilterWrapper.areaRadiusPasses(radius) == [radius])
    }

    @Test("上限を超える半径は上限以下のパスへ均される", arguments: [121, 240, 241, 300, 511, 8191])
    func largeRadiusSplitsEvenly(radius: Int) {
        let passes = MPSImageFilterWrapper.areaRadiusPasses(radius)
        #expect(passes.count > 1, "分割されていない")
        #expect(passes.reduce(0, +) == radius, "合計が元の半径と違う: \(passes)")
        #expect(passes.allSatisfy { $0 <= 120 && $0 > 0 }, "上限を超えるパスがある: \(passes)")
    }

    // MARK: 分けても絵が変わらないこと

    /// 崖の直前（半径 240 = カーネル幅 481）。1 段で当てた真値と突き合わせる。
    /// ここが一致すれば、分割が数学どおりに効いていると言える。
    @Test("分割した erode は 1 段で当てたのと同じ絵")
    func splitErodeMatchesSinglePass() throws {
        let split = try filtered { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: 240)
        }
        #expect(MPSImageFilterWrapper.areaRadiusPasses(240).count == 2, "この検査は分割前提")
        #expect(split == (try reference(radii: [240])))
    }

    @Test("分割した dilate は 1 段で当てたのと同じ絵")
    func splitDilateMatchesSinglePass() throws {
        let split = try filtered { wrapper, cb, src, dst in
            wrapper.encodeDilate(commandBuffer: cb, source: src, destination: dst, radius: 240)
        }
        #expect(split == (try reference(radii: [240], max: true)))
    }

    /// 崖の向こう側（半径 300）。修正前はここで固まっていた。
    /// 真値は崖より下の半径だけを 2 段に分けて作る。
    @Test("崖を越える半径でも返ってきて、段を分けた真値と一致する")
    func aboveCliffRadiusReturns() throws {
        let split = try filtered { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: 300)
        }
        #expect(split == (try reference(radii: [240, 60])))
    }

    /// パス数が偶数のときも奇数のときも、最後の書き込みが destination に来ること。
    /// ping-pong の偶奇を取り違えると、ここで中間結果が返る。
    @Test("パス数の偶奇によらず最終結果が返る", arguments: [121, 241, 300, 361])
    func pingPongParityIsCorrect(radius: Int) throws {
        let split = try filtered { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: radius)
        }
        let passes = MPSImageFilterWrapper.areaRadiusPasses(radius)
        #expect(split == (try reference(radii: passes)),
                "パス数 \(passes.count)（\(passes)）で結果が食い違う")
    }

    // MARK: 効きすぎていないこと

    /// よくある小さい半径は経路もコストも変わらない（1 パスのまま素通り）。
    @Test("小さい半径はこれまでどおり 1 パスで同じ絵", arguments: [0, 1, 5, 120])
    func smallRadiusUnchanged(radius: Int) throws {
        let out = try filtered { wrapper, cb, src, dst in
            wrapper.encodeErode(commandBuffer: cb, source: src, destination: dst, radius: radius)
        }
        #expect(out == (try reference(radii: [radius])))
    }
}
