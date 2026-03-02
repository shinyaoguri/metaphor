@preconcurrency import Metal
import MetalPerformanceShaders

/// MPS 最適化画像フィルタ
///
/// Apple Silicon のハードウェア最適化カーネルを使い、
/// 手書きコンピュートシェーダーより高速な画像処理を提供する。
///
/// ```swift
/// let mps = createMPSFilter()
/// mps.gaussianBlur(image, sigma: 5.0)
/// ```
@MainActor
public final class MPSImageFilterWrapper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Kernel cache
    private var gaussianCache: [Float: MPSImageGaussianBlur] = [:]
    private var sobelKernel: MPSImageSobel?
    private var laplacianKernel: MPSImageLaplacian?
    private var areaMinCache: [Int: MPSImageAreaMin] = [:]
    private var areaMaxCache: [Int: MPSImageAreaMax] = [:]
    private var medianCache: [Int: MPSImageMedian] = [:]
    private var thresholdKernel: MPSImageThresholdBinary?

    // Texture pool
    private var texturePool: [String: MTLTexture] = [:]

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    // MARK: - Standalone API (MImage)

    /// ガウシアンブラーを適用（ハードウェア最適化）
    public func gaussianBlur(_ image: MImage, sigma: Float) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// Sobel エッジ検出を適用
    public func sobel(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// ラプラシアンフィルタを適用
    public func laplacian(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// 収縮（morphological min）
    public func erode(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMin(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// 膨張（morphological max）
    public func dilate(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMax(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// メディアンフィルタ
    public func median(_ image: MImage, diameter: Int = 3) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateMedian(diameter: diameter)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// 閾値二値化
    public func threshold(_ image: MImage, value: Float = 0.5) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateThreshold(value: value)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    // MARK: - Encode API (PostProcessPipeline integration)

    /// ガウシアンブラーをコマンドバッファにエンコード
    func encodeGaussianBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        sigma: Float
    ) {
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Sobel エッジ検出をエンコード
    func encodeSobel(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// ラプラシアンをエンコード
    func encodeLaplacian(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// モルフォロジー（erode）をエンコード
    func encodeErode(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        radius: Int
    ) {
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMin(size: size)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// モルフォロジー（dilate）をエンコード
    func encodeDilate(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        radius: Int
    ) {
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMax(size: size)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    // MARK: - Private: Kernel Caching

    private func getOrCreateGaussian(sigma: Float) -> MPSImageGaussianBlur {
        if let cached = gaussianCache[sigma] { return cached }
        let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
        kernel.edgeMode = .clamp
        gaussianCache[sigma] = kernel
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
        let kernel = MPSImageAreaMin(device: device, kernelWidth: size, kernelHeight: size)
        kernel.edgeMode = .clamp
        areaMinCache[size] = kernel
        return kernel
    }

    private func getOrCreateAreaMax(size: Int) -> MPSImageAreaMax {
        if let cached = areaMaxCache[size] { return cached }
        let kernel = MPSImageAreaMax(device: device, kernelWidth: size, kernelHeight: size)
        kernel.edgeMode = .clamp
        areaMaxCache[size] = kernel
        return kernel
    }

    private func getOrCreateMedian(diameter: Int) -> MPSImageMedian {
        let d = max(3, diameter | 1) // must be odd, minimum 3
        if let cached = medianCache[d] { return cached }
        let kernel = MPSImageMedian(device: device, kernelDiameter: d)
        medianCache[d] = kernel
        return kernel
    }

    private func getOrCreateThreshold(value: Float) -> MPSImageThresholdBinary {
        // Threshold kernels are cheap; recreate for different values
        let kernel = MPSImageThresholdBinary(
            device: device,
            thresholdValue: value,
            maximumValue: 1.0,
            linearGrayColorTransform: nil
        )
        thresholdKernel = kernel
        return kernel
    }

    // MARK: - Private: Helpers

    private func prepareInPlace(_ image: MImage) -> (MTLTexture, MTLTexture, MTLCommandBuffer)? {
        let src = image.texture
        let w = src.width, h = src.height
        guard let dst = getOrCreateTexture(width: w, height: h, tag: "mps_output"),
              let cb = commandQueue.makeCommandBuffer() else { return nil }
        return (src, dst, cb)
    }

    private func finalize(image: MImage, dst: MTLTexture, commandBuffer: MTLCommandBuffer) {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let w = dst.width, h = dst.height
        image.replaceTexture(dst)
        texturePool.removeValue(forKey: "\(w)_\(h)_mps_output")
    }

    private func getOrCreateTexture(width: Int, height: Int, tag: String) -> MTLTexture? {
        let key = "\(width)_\(height)_\(tag)"
        if let cached = texturePool[key] { return cached }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
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
