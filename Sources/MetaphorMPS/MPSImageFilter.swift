import Metal
import MetalPerformanceShaders
import MetaphorCore

/// Provides hardware-optimized image filters using Metal Performance Shaders.
///
/// Leverages Apple Silicon's hardware-accelerated kernels to achieve faster
/// image processing than hand-written compute shaders.
///
/// ```swift
/// let mps = createMPSFilter()
/// mps.gaussianBlur(image, sigma: 5.0)
/// ```
///
/// - Important: The standalone API that takes an `MImage` **synchronously waits**
///   for GPU completion (`waitUntilCompleted`) on every call. If applying multiple
///   filters in series every frame inside `draw()`, use the `encode`-family API
///   (the variants that take a `commandBuffer:`) that encodes into an existing
///   command buffer instead.
@MainActor
public final class MPSImageFilterWrapper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // カーネルキャッシュ
    private var gaussianCache: [Float: MPSImageGaussianBlur] = [:]
    private var sobelKernel: MPSImageSobel?
    private var laplacianKernel: MPSImageLaplacian?
    private var areaMinCache: [Int: MPSImageAreaMin] = [:]
    private var areaMaxCache: [Int: MPSImageAreaMax] = [:]
    private var medianCache: [Int: MPSImageMedian] = [:]

    // テクスチャプール
    private var texturePool: [String: MTLTexture] = [:]
    /// The identifier of the output texture that the most recent in-place apply handed to MImage.
    /// Kept so that on the next call, if the texture being replaced is confirmed to be
    /// this filter's own previous output, it can be reclaimed (#251).
    private var lastInPlaceOutputID: ObjectIdentifier?

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    // MARK: - スタンドアロン API（MImage）

    /// Applies a hardware-optimized Gaussian blur to an image.
    /// - Parameters:
    ///   - image: The image to blur.
    ///   - sigma: The blur radius, in pixels.
    public func gaussianBlur(_ image: MImage, sigma: Float) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies Sobel edge detection to an image.
    /// - Parameter image: The image to process.
    public func sobel(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies a Laplacian filter to an image.
    /// - Parameter image: The image to process.
    public func laplacian(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies morphological erosion (area min) to an image.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - radius: The erosion radius, in pixels. Values outside
    ///     `0...max(width, height) - 1` are clamped into range.
    public func erode(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = areaKernelSize(radius: radius, source: src, api: "erode")
        let kernel = getOrCreateAreaMin(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies morphological dilation (area max) to an image.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - radius: The dilation radius, in pixels. Values outside
    ///     `0...max(width, height) - 1` are clamped into range.
    public func dilate(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = areaKernelSize(radius: radius, source: src, api: "dilate")
        let kernel = getOrCreateAreaMax(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies a median filter to an image.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - diameter: The filter kernel diameter. Even values are rounded up to the next
    ///     odd number, and the result is clamped into the range the device supports
    ///     (`MPSImageMedian.minKernelDiameter()...maxKernelDiameter()`, 3...127 on Apple Silicon).
    public func median(_ image: MImage, diameter: Int = 3) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateMedian(diameter: diameter)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    /// Applies binary threshold processing to an image.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - value: The threshold value (0.0-1.0).
    public func threshold(_ image: MImage, value: Float = 0.5) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateThreshold(value: value)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, src: src, dst: dst, commandBuffer: cb)
    }

    // MARK: - エンコード API（PostProcessPipeline 統合）

    /// Encodes a Gaussian blur operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - sigma: The blur radius, in pixels.
    public func encodeGaussianBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        sigma: Float
    ) {
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes a Sobel edge detection operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    public func encodeSobel(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes a Laplacian filter operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    public func encodeLaplacian(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes a morphological erosion operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - radius: The erosion radius, in pixels. Values outside
    ///     `0...max(source.width, source.height) - 1` are clamped into range.
    public func encodeErode(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        radius: Int
    ) {
        let size = areaKernelSize(radius: radius, source: source, api: "erode")
        let kernel = getOrCreateAreaMin(size: size)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes a morphological dilation operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - radius: The dilation radius, in pixels. Values outside
    ///     `0...max(source.width, source.height) - 1` are clamped into range.
    public func encodeDilate(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        radius: Int
    ) {
        let size = areaKernelSize(radius: radius, source: source, api: "dilate")
        let kernel = getOrCreateAreaMax(size: size)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes a median filter operation into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - diameter: The filter kernel diameter. Even values are rounded up to the next
    ///     odd number, and the result is clamped into the range the device supports
    ///     (`MPSImageMedian.minKernelDiameter()...maxKernelDiameter()`, 3...127 on Apple Silicon).
    public func encodeMedian(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        diameter: Int = 3
    ) {
        let kernel = getOrCreateMedian(diameter: diameter)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Encodes binary threshold processing into a command buffer.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - value: The threshold value (0.0-1.0).
    public func encodeThreshold(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        value: Float = 0.5
    ) {
        let kernel = getOrCreateThreshold(value: value)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    // MARK: - キャッシュ管理

    private static let maxGaussianCacheSize = 32
    private static let maxAreaCacheSize = 16

    /// Clears all cached MPS kernels and textures.
    public func clearCache() {
        gaussianCache.removeAll()
        areaMinCache.removeAll()
        areaMaxCache.removeAll()
        medianCache.removeAll()
        texturePool.removeAll()
    }

    // MARK: - プライベート: カーネルサイズのクランプ（#893）

    /// erode / dilate の半径を丸めて、MPS へ渡してよいカーネル幅にします。
    ///
    /// `radius * 2 + 1` を検証せずに `MPSImageAreaMin` / `MPSImageAreaMax` へ渡すと、
    /// `throws` でも Optional でも表現できない 2 通りの壊れ方をします（いずれも実測）。
    ///
    /// - **負の半径**: カーネル幅が負のまま `kernelWidth:`（`NSUInteger`）へ渡り、
    ///   巨大な符号なし値として解釈されます。abort すらせず `waitUntilCompleted()` から
    ///   二度と戻らないため、`erode(image, radius: -1)` はプロセスごと固まります。
    /// - **巨大な半径**: `radius * 2 + 1` が `Int` をオーバーフローし、MPS に届く前に
    ///   Swift の算術トラップ（SIGTRAP）でプロセスが落ちます（`radius: Int.max`）。
    ///
    /// 上限は「テクスチャの長辺 - 1」に置きます。`edgeMode = .clamp` なので、
    /// 窓 `[x - r, x + r]` が全画素でテクスチャ全体を覆う `r >= max(width, height) - 1` に
    /// 達した時点で出力は全画素が全体の min / max に飽和し、それ以上 `r` を増やしても
    /// **絵は 1 ピクセルも変わりません**。よってこのクランプは効きすぎになりません。
    private func areaKernelSize(radius: Int, source: MTLTexture, api: String) -> Int {
        let limit = max(0, max(source.width, source.height) - 1)
        let clamped = min(max(radius, 0), limit)
        if clamped != radius {
            metaphorWarning(
                "MPSImageFilter: \(api) radius must be within 0...\(limit) for a "
                + "\(source.width)x\(source.height) texture (got \(radius)); using \(clamped)")
        }
        return clamped * 2 + 1
    }

    /// median の直径を、奇数かつデバイスが受け付ける範囲へ丸めます。
    ///
    /// `MPSImageMedian` は範囲外の直径を戻り値ではなくアサーションで返す
    /// （`Kernel diameter (1001) is larger than the supported max median filter
    /// diameter allowed (127)` で `Abort trap: 6`）ため、`init` へ渡す前に丸めます。
    /// 上下限はデバイスに問い合わせます（Apple Silicon では 3...127）。
    private static func clampedMedianDiameter(_ diameter: Int) -> Int {
        // 上下限が偶数で返っても範囲から出ないよう、下限は切り上げ・上限は切り下げで奇数にする
        let lower = MPSImageMedian.minKernelDiameter() | 1
        let upperRaw = MPSImageMedian.maxKernelDiameter()
        let upper = upperRaw.isMultiple(of: 2) ? upperRaw - 1 : upperRaw
        let odd = diameter | 1 // 偶数は 1 つ上の奇数へ（負数も奇数のまま下限で拾われる）
        return min(max(odd, lower), max(lower, upper))
    }

    // MARK: - プライベート: カーネルキャッシュ

    private func getOrCreateGaussian(sigma: Float) -> MPSImageGaussianBlur {
        // sigma をアニメーションさせると毎フレーム別キーになり、カーネル生成と
        // 無差別 eviction が繰り返されるため、視覚的に区別できない粒度
        // （0.01）へ量子化してキャッシュヒット率を上げる
        let quantized = (sigma * 100).rounded() / 100
        if let cached = gaussianCache[quantized] { return cached }
        if gaussianCache.count >= Self.maxGaussianCacheSize {
            let keysToRemove = Array(gaussianCache.keys).prefix(gaussianCache.count / 2)
            for key in keysToRemove {
                gaussianCache.removeValue(forKey: key)
            }
        }
        let kernel = MPSImageGaussianBlur(device: device, sigma: quantized)
        kernel.edgeMode = .clamp
        gaussianCache[quantized] = kernel
        return kernel
    }

    private func getOrCreateSobel() -> MPSImageSobel {
        if let cached = sobelKernel { return cached }
        let kernel = MPSImageSobel(device: device)
        sobelKernel = kernel
        return kernel
    }

    private func getOrCreateLaplacian() -> MPSImageLaplacian {
        if let cached = laplacianKernel { return cached }
        let kernel = MPSImageLaplacian(device: device)
        laplacianKernel = kernel
        return kernel
    }

    private func getOrCreateAreaMin(size: Int) -> MPSImageAreaMin {
        if let cached = areaMinCache[size] { return cached }
        if areaMinCache.count >= Self.maxAreaCacheSize {
            let keysToRemove = Array(areaMinCache.keys).prefix(areaMinCache.count / 2)
            for key in keysToRemove { areaMinCache.removeValue(forKey: key) }
        }
        let kernel = MPSImageAreaMin(device: device, kernelWidth: size, kernelHeight: size)
        kernel.edgeMode = .clamp
        areaMinCache[size] = kernel
        return kernel
    }

    private func getOrCreateAreaMax(size: Int) -> MPSImageAreaMax {
        if let cached = areaMaxCache[size] { return cached }
        if areaMaxCache.count >= Self.maxAreaCacheSize {
            let keysToRemove = Array(areaMaxCache.keys).prefix(areaMaxCache.count / 2)
            for key in keysToRemove { areaMaxCache.removeValue(forKey: key) }
        }
        let kernel = MPSImageAreaMax(device: device, kernelWidth: size, kernelHeight: size)
        kernel.edgeMode = .clamp
        areaMaxCache[size] = kernel
        return kernel
    }

    private func getOrCreateMedian(diameter: Int) -> MPSImageMedian {
        let d = Self.clampedMedianDiameter(diameter)
        if d != diameter {
            metaphorWarning(
                "MPSImageFilter: median diameter must be an odd number within "
                + "\(MPSImageMedian.minKernelDiameter())...\(MPSImageMedian.maxKernelDiameter()) "
                + "(got \(diameter)); using \(d)")
        }
        if let cached = medianCache[d] { return cached }
        if medianCache.count >= Self.maxAreaCacheSize {
            let keysToRemove = Array(medianCache.keys).prefix(medianCache.count / 2)
            for key in keysToRemove { medianCache.removeValue(forKey: key) }
        }
        let kernel = MPSImageMedian(device: device, kernelDiameter: d)
        // `MPSUnaryImageKernel` の既定は `.zero`（画像の外を 0 として読む）。median は
        // 「窓の中の値を 1 つ選ぶ」フィルタなので出力は入力に無い値にならないはずなのに、
        // 既定のままだと窓の過半が画像外になる縁で中央値が 0 になり、**入力に存在しない黒**が
        // 出ていた（直径 9 なら四隅から 4 画素ぶん）。同じファイルの gaussianBlur /
        // erode / dilate は `.clamp` を明示しており、median だけ取り残されていた（#920）
        kernel.edgeMode = .clamp
        medianCache[d] = kernel
        return kernel
    }

    private func getOrCreateThreshold(value: Float) -> MPSImageThresholdBinary {
        // 閾値カーネルは軽量なため、異なる値で毎回作成する（キャッシュしない）
        MPSImageThresholdBinary(
            device: device,
            thresholdValue: value,
            maximumValue: 1.0,
            linearGrayColorTransform: nil
        )
    }

    // MARK: - プライベート: ヘルパー

    private func prepareInPlace(_ image: MImage) -> (MTLTexture, MTLTexture, MTLCommandBuffer)? {
        let src = image.texture
        let w = src.width, h = src.height
        // 出力は入力と同じ pixelFormat で作る（bgra8Unorm 固定だと rgba16Float 等の
        // MImage へのフィルタ適用でフォーマットが暗黙に変わり精度が落ちる）
        guard let dst = getOrCreateTexture(
                  width: w, height: h, pixelFormat: src.pixelFormat, tag: "mps_output"),
              let cb = commandQueue.makeCommandBuffer() else { return nil }
        return (src, dst, cb)
    }

    private func finalize(image: MImage, src: MTLTexture, dst: MTLTexture, commandBuffer: MTLCommandBuffer) {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let w = dst.width, h = dst.height
        image.replaceTexture(dst)
        // in-place 適用後のテクスチャ回収（ping-pong、#251）。MImage へ渡した出力は
        // プールから外し、置き換えられた旧テクスチャが「前回この filter が出力した
        // もの」であれば次回の出力先としてプールへ戻す。これで毎フレームの適用が
        // 2 枚のスワップに収まり、呼び出しごとのフルサイズ private テクスチャ
        // 新規確保を避ける。他所から来たテクスチャ（loadImage 等）は別 MImage・
        // 呼び出し側と共有されている可能性があるため取り込まない（前回出力との
        // 同一性チェックが descriptor 一致の保証も兼ねる）
        let key = "\(w)_\(h)_\(dst.pixelFormat.rawValue)_mps_output"
        if let last = lastInPlaceOutputID, ObjectIdentifier(src) == last {
            texturePool[key] = src
        } else {
            texturePool.removeValue(forKey: key)
        }
        // サイズ・フォーマット変更時に旧 ping-pong 相手が残留しないよう掃除
        for staleKey in texturePool.keys where staleKey.hasSuffix("_mps_output") && staleKey != key {
            texturePool.removeValue(forKey: staleKey)
        }
        lastInPlaceOutputID = ObjectIdentifier(dst)
    }

    private func getOrCreateTexture(
        width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm, tag: String
    ) -> MTLTexture? {
        let key = "\(width)_\(height)_\(pixelFormat.rawValue)_\(tag)"
        if let cached = texturePool[key] { return cached }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        texturePool[key] = tex
        return tex
    }
}
