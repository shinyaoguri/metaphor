@preconcurrency import Metal
import MetalPerformanceShaders
import MetaphorCore

/// Metal Performance Shaders を使用したハードウェア最適化画像フィルタを提供します。
///
/// Apple Silicon のハードウェアアクセラレーションカーネルを活用し、
/// 手書きのコンピュートシェーダーよりも高速な画像処理を実現します。
///
/// ```swift
/// let mps = createMPSFilter()
/// mps.gaussianBlur(image, sigma: 5.0)
/// ```
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
    private var thresholdKernel: MPSImageThresholdBinary?

    // テクスチャプール
    private var texturePool: [String: MTLTexture] = [:]

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    // MARK: - スタンドアロン API（MImage）

    /// ハードウェア最適化されたガウシアンブラーを画像に適用します。
    /// - Parameters:
    ///   - image: ブラーを適用する画像。
    ///   - sigma: ブラー半径（ピクセル単位）。
    public func gaussianBlur(_ image: MImage, sigma: Float) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// Sobel エッジ検出を画像に適用します。
    /// - Parameter image: 処理する画像。
    public func sobel(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// ラプラシアンフィルタを画像に適用します。
    /// - Parameter image: 処理する画像。
    public func laplacian(_ image: MImage) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// モルフォロジー収縮（エリアミン）を画像に適用します。
    /// - Parameters:
    ///   - image: 処理する画像。
    ///   - radius: 収縮半径（ピクセル単位）。
    public func erode(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMin(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// モルフォロジー膨張（エリアマックス）を画像に適用します。
    /// - Parameters:
    ///   - image: 処理する画像。
    ///   - radius: 膨張半径（ピクセル単位）。
    public func dilate(_ image: MImage, radius: Int = 1) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let size = radius * 2 + 1
        let kernel = getOrCreateAreaMax(size: size)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// メディアンフィルタを画像に適用します。
    /// - Parameters:
    ///   - image: 処理する画像。
    ///   - diameter: フィルタカーネルの直径（奇数、最小3）。
    public func median(_ image: MImage, diameter: Int = 3) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateMedian(diameter: diameter)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    /// バイナリ閾値処理を画像に適用します。
    /// - Parameters:
    ///   - image: 処理する画像。
    ///   - value: 閾値（0.0〜1.0）。
    public func threshold(_ image: MImage, value: Float = 0.5) {
        guard let (src, dst, cb) = prepareInPlace(image) else { return }
        let kernel = getOrCreateThreshold(value: value)
        kernel.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        finalize(image: image, dst: dst, commandBuffer: cb)
    }

    // MARK: - エンコード API（PostProcessPipeline 統合）

    /// ガウシアンブラー操作をコマンドバッファにエンコードします。
    /// - Parameters:
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    ///   - sigma: ブラー半径（ピクセル単位）。
    func encodeGaussianBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        sigma: Float
    ) {
        let kernel = getOrCreateGaussian(sigma: sigma)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// Sobel エッジ検出操作をコマンドバッファにエンコードします。
    /// - Parameters:
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    func encodeSobel(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateSobel()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// ラプラシアンフィルタ操作をコマンドバッファにエンコードします。
    /// - Parameters:
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    func encodeLaplacian(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let kernel = getOrCreateLaplacian()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
    }

    /// モルフォロジー収縮操作をコマンドバッファにエンコードします。
    /// - Parameters:
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    ///   - radius: 収縮半径（ピクセル単位）。
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

    /// モルフォロジー膨張操作をコマンドバッファにエンコードします。
    /// - Parameters:
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    ///   - radius: 膨張半径（ピクセル単位）。
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

    // MARK: - キャッシュ管理

    private static let maxGaussianCacheSize = 32
    private static let maxAreaCacheSize = 16

    /// キャッシュ済みの MPS カーネルとテクスチャをすべてクリアします。
    public func clearCache() {
        gaussianCache.removeAll()
        areaMinCache.removeAll()
        areaMaxCache.removeAll()
        medianCache.removeAll()
        texturePool.removeAll()
    }

    // MARK: - プライベート: カーネルキャッシュ

    private func getOrCreateGaussian(sigma: Float) -> MPSImageGaussianBlur {
        if let cached = gaussianCache[sigma] { return cached }
        if gaussianCache.count >= Self.maxGaussianCacheSize {
            let keysToRemove = Array(gaussianCache.keys).prefix(gaussianCache.count / 2)
            for key in keysToRemove {
                gaussianCache.removeValue(forKey: key)
            }
        }
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
        let d = max(3, diameter | 1) // 奇数でなければならない、最小3
        if let cached = medianCache[d] { return cached }
        if medianCache.count >= Self.maxAreaCacheSize {
            let keysToRemove = Array(medianCache.keys).prefix(medianCache.count / 2)
            for key in keysToRemove { medianCache.removeValue(forKey: key) }
        }
        let kernel = MPSImageMedian(device: device, kernelDiameter: d)
        medianCache[d] = kernel
        return kernel
    }

    private func getOrCreateThreshold(value: Float) -> MPSImageThresholdBinary {
        // 閾値カーネルは軽量なため、異なる値で再作成
        let kernel = MPSImageThresholdBinary(
            device: device,
            thresholdValue: value,
            maximumValue: 1.0,
            linearGrayColorTransform: nil
        )
        thresholdKernel = kernel
        return kernel
    }

    // MARK: - プライベート: ヘルパー

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
