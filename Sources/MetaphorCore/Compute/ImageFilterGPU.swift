@preconcurrency import Metal
import MetalPerformanceShaders

/// GPU 画像フィルターコンピュートカーネル用のユニフォームパラメータ
struct FilterParams {
    var width: UInt32
    var height: UInt32
    var param1: Float
    var param2: Float
}

/// GPU コンピュートシェーダーを使用して画像フィルターを適用します。
///
/// CPU ベースの `ImageFilter` に対する GPU アクセラレーション代替として機能します。
/// BGRA テクスチャをネイティブに処理し、`.private` ストレージモードのテクスチャをサポートします。
@MainActor
public final class ImageFilterGPU {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// 全フィルターカーネルを含むコンパイル済みシェーダーライブラリ
    private var library: MTLLibrary?

    /// 関数名をキーとするカーネルパイプラインキャッシュ
    private var kernelCache: [String: MTLComputePipelineState] = [:]

    /// サイズ文字列をキーとするテクスチャプール
    private var texturePool: [String: MTLTexture] = [:]

    /// 半径をキーとするガウシアンウェイトバッファキャッシュ
    private var weightBufferCache: [Int: MTLBuffer] = [:]

    /// ShaderLibrary 経由のプリコンパイル済みライブラリ参照
    private weak var shaderLibrary: ShaderLibrary?

    // MARK: - MPS カーネルキャッシュ

    private var gaussianCache: [Float: MPSImageGaussianBlur] = [:]
    private var sobelKernel: MPSImageSobel?
    private var laplacianKernel: MPSImageLaplacian?
    private var areaMinCache: [Int: MPSImageAreaMin] = [:]
    private var areaMaxCache: [Int: MPSImageAreaMax] = [:]
    private var medianCache: [Int: MPSImageMedian] = [:]
    private var thresholdKernel: MPSImageThresholdBinary?

    init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary? = nil) {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = shaderLibrary
    }

    // MARK: - キャッシュ管理

    /// テクスチャプール、ウェイトバッファ、コンパイル済みカーネルを含む全キャッシュをクリアします。
    public func clearCache() {
        texturePool.removeAll()
        weightBufferCache.removeAll()
        kernelCache.removeAll()
        gaussianCache.removeAll()
        sobelKernel = nil
        laplacianKernel = nil
        areaMinCache.removeAll()
        areaMaxCache.removeAll()
        medianCache.removeAll()
        thresholdKernel = nil
    }

    /// 指定されたサイズに一致しないテクスチャプールエントリを削除します。
    private func pruneTexturePool(keepWidth: Int, keepHeight: Int) {
        let keepPrefix = "\(keepWidth)_\(keepHeight)_"
        texturePool = texturePool.filter { $0.key.hasPrefix(keepPrefix) }
    }

    /// ウェイトバッファキャッシュが上限を超えた場合、古いエントリを退去させます。
    private func pruneWeightBufferCache(maxEntries: Int = 16) {
        if weightBufferCache.count > maxEntries {
            // 最小の半径キーのエントリを削除（再利用される可能性が最も低い）
            let sortedKeys = weightBufferCache.keys.sorted()
            let removeCount = weightBufferCache.count - maxEntries
            for key in sortedKeys.prefix(removeCount) {
                weightBufferCache.removeValue(forKey: key)
            }
        }
    }

    // MARK: - パブリック API

    /// テクスチャをインプレースで置換してフィルターを画像に適用します。
    ///
    /// この同期バリアントは内部コマンドバッファを作成し、GPU 完了を待ちます。
    /// リアルタイムレンダリングループでは、代わりに `encode(_:to:commandBuffer:)` を推奨します。
    /// - Parameters:
    ///   - filter: 適用するフィルタータイプ
    ///   - image: テクスチャが置換される対象画像
    public func apply(_ filter: FilterType, to image: MImage) {
        let srcTex = image.texture
        let w = srcTex.width
        let h = srcTex.height

        // 異なるサイズのキャッシュエントリを自動パージ
        pruneTexturePool(keepWidth: w, keepHeight: h)
        pruneWeightBufferCache()

        // MPS フィルターは専用の MPS パスに委譲
        switch filter {
        case .mpsBlur(let sigma):
            applyMPS(image) { self.getOrCreateGaussian(sigma: sigma) }; return
        case .mpsSobel:
            applyMPS(image) { self.getOrCreateSobel() }; return
        case .mpsLaplacian:
            applyMPS(image) { self.getOrCreateLaplacian() }; return
        case .mpsErode(let radius):
            applyMPS(image) { self.getOrCreateAreaMin(size: radius * 2 + 1) }; return
        case .mpsDilate(let radius):
            applyMPS(image) { self.getOrCreateAreaMax(size: radius * 2 + 1) }; return
        case .mpsMedian(let diameter):
            applyMPS(image) { self.getOrCreateMedian(diameter: diameter) }; return
        case .mpsThreshold(let value):
            applyMPS(image) { self.getOrCreateThreshold(value: value) }; return
        default:
            break
        }

        guard let outTex = getOrCreateTexture(width: w, height: h, tag: "output") else { return }

        switch filter {
        case .blur(let radius):
            applyGaussianBlur(src: srcTex, dst: outTex, radius: max(1, radius), width: w, height: h, externalCommandBuffer: nil)
        default:
            applySinglePass(filter, src: srcTex, dst: outTex, width: w, height: h, externalCommandBuffer: nil)
        }

        image.replaceTexture(outTex)
        // 所有権が画像に移ったため、出力テクスチャをプールから削除
        texturePool.removeValue(forKey: "\(w)_\(h)_output")
    }

    /// コマンドバッファにフィルター操作をエンコードします（コミットや待機なし）。
    ///
    /// リアルタイムレンダリングループ内で使用するノンブロッキングバリアントです。
    /// MPS フィルターはこのパスではサポートされません。非 MPS フィルタータイプのみ使用してください。
    /// - Parameters:
    ///   - filter: エンコードするフィルタータイプ
    ///   - image: テクスチャが置換される対象画像
    ///   - commandBuffer: エンコード先のコマンドバッファ
    public func encode(_ filter: FilterType, to image: MImage, commandBuffer: MTLCommandBuffer) {
        let srcTex = image.texture
        let w = srcTex.width
        let h = srcTex.height

        guard let outTex = getOrCreateTexture(width: w, height: h, tag: "output") else { return }

        switch filter {
        case .blur(let radius):
            applyGaussianBlur(src: srcTex, dst: outTex, radius: max(1, radius), width: w, height: h, externalCommandBuffer: commandBuffer)
        default:
            applySinglePass(filter, src: srcTex, dst: outTex, width: w, height: h, externalCommandBuffer: commandBuffer)
        }

        image.replaceTexture(outTex)
        texturePool.removeValue(forKey: "\(w)_\(h)_output")
    }

    // MARK: - Private: MPS フィルター適用

    private func applyMPS(_ image: MImage, kernel: () -> MPSUnaryImageKernel) {
        let src = image.texture
        let w = src.width, h = src.height
        guard let dst = getOrCreateTexture(width: w, height: h, tag: "mps_output"),
              let cb = commandQueue.makeCommandBuffer() else { return }
        kernel().encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        cb.commit()
        cb.waitUntilCompleted()
        image.replaceTexture(dst)
        texturePool.removeValue(forKey: "\(w)_\(h)_mps_output")
    }

    private func getOrCreateGaussian(sigma: Float) -> MPSImageGaussianBlur {
        if let cached = gaussianCache[sigma] { return cached }
        let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
        gaussianCache[sigma] = kernel
        return kernel
    }

    private func getOrCreateSobel() -> MPSImageSobel {
        if let k = sobelKernel { return k }
        let k = MPSImageSobel(device: device)
        sobelKernel = k
        return k
    }

    private func getOrCreateLaplacian() -> MPSImageLaplacian {
        if let k = laplacianKernel { return k }
        let k = MPSImageLaplacian(device: device)
        laplacianKernel = k
        return k
    }

    private func getOrCreateAreaMin(size: Int) -> MPSImageAreaMin {
        if let cached = areaMinCache[size] { return cached }
        let k = MPSImageAreaMin(device: device, kernelWidth: size, kernelHeight: size)
        areaMinCache[size] = k
        return k
    }

    private func getOrCreateAreaMax(size: Int) -> MPSImageAreaMax {
        if let cached = areaMaxCache[size] { return cached }
        let k = MPSImageAreaMax(device: device, kernelWidth: size, kernelHeight: size)
        areaMaxCache[size] = k
        return k
    }

    private func getOrCreateMedian(diameter: Int) -> MPSImageMedian {
        if let cached = medianCache[diameter] { return cached }
        let k = MPSImageMedian(device: device, kernelDiameter: diameter)
        medianCache[diameter] = k
        return k
    }

    private func getOrCreateThreshold(value: Float) -> MPSImageThresholdBinary {
        if let k = thresholdKernel { return k }
        let k = MPSImageThresholdBinary(device: device, thresholdValue: value, maximumValue: 1.0, linearGrayColorTransform: nil)
        thresholdKernel = k
        return k
    }

    // MARK: - Private: シングルパス

    private func applySinglePass(
        _ filter: FilterType, src: MTLTexture, dst: MTLTexture, width: Int, height: Int,
        externalCommandBuffer: MTLCommandBuffer?
    ) {
        let functionName = kernelName(for: filter)
        guard let pipeline = getOrCreatePipeline(functionName: functionName) else { return }
        let cb: MTLCommandBuffer
        if let ext = externalCommandBuffer {
            cb = ext
        } else {
            guard let newCB = commandQueue.makeCommandBuffer() else { return }
            cb = newCB
        }
        guard let encoder = cb.makeComputeCommandEncoder() else { return }

        var params = FilterParams(
            width: UInt32(width), height: UInt32(height),
            param1: paramValue(for: filter), param2: 0
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(dst, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<FilterParams>.size, index: 0)

        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()

        if externalCommandBuffer == nil {
            cb.commit()
            cb.waitUntilCompleted()
        }
    }

    // MARK: - Private: ガウシアンブラー（2パス分離型）

    private func applyGaussianBlur(
        src: MTLTexture, dst: MTLTexture, radius: Int, width: Int, height: Int,
        externalCommandBuffer: MTLCommandBuffer?
    ) {
        guard let tempTex = getOrCreateTexture(width: width, height: height, tag: "blur_temp"),
              let hPipeline = getOrCreatePipeline(functionName: "filter_gaussian_h"),
              let vPipeline = getOrCreatePipeline(functionName: "filter_gaussian_v") else { return }
        let cb: MTLCommandBuffer
        if let ext = externalCommandBuffer {
            cb = ext
        } else {
            guard let newCB = commandQueue.makeCommandBuffer() else { return }
            cb = newCB
        }
        guard let encoder = cb.makeComputeCommandEncoder() else { return }

        var params = FilterParams(
            width: UInt32(width), height: UInt32(height),
            param1: Float(radius), param2: 0
        )
        let weightBuffer = getOrCreateWeightBuffer(radius: radius)

        let tw = hPipeline.threadExecutionWidth
        let th = max(1, hPipeline.maxTotalThreadsPerThreadgroup / tw)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        let groupSize = MTLSize(width: tw, height: th, depth: 1)

        // 水平パス: src -> tempTex
        encoder.setComputePipelineState(hPipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(tempTex, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<FilterParams>.size, index: 0)
        if let wb = weightBuffer {
            encoder.setBuffer(wb, offset: 0, index: 1)
        }
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

        // メモリバリア
        encoder.memoryBarrier(scope: .textures)

        // 垂直パス: tempTex -> dst
        encoder.setComputePipelineState(vPipeline)
        encoder.setTexture(tempTex, index: 0)
        encoder.setTexture(dst, index: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

        encoder.endEncoding()

        if externalCommandBuffer == nil {
            cb.commit()
            cb.waitUntilCompleted()
        }
    }

    // MARK: - Private: カーネル管理

    private func ensureLibrary() -> MTLLibrary? {
        if let lib = library { return lib }
        do {
            guard let source = ShaderLibrary.loadShaderSource("imageFilter") else {
                print("[metaphor] Failed to load imageFilter shader source")
                return nil
            }
            let lib = try device.makeLibrary(source: source, options: nil)
            self.library = lib
            return lib
        } catch {
            print("[metaphor] Failed to compile ImageFilter shaders: \(error)")
            return nil
        }
    }

    private func getOrCreatePipeline(functionName: String) -> MTLComputePipelineState? {
        if let cached = kernelCache[functionName] { return cached }

        // ShaderLibrary パス (metallib) をランタイムコンパイルより優先
        let function: MTLFunction?
        if let fn = shaderLibrary?.function(named: functionName, from: ShaderLibrary.BuiltinKey.imageFilter) {
            function = fn
        } else if let lib = ensureLibrary() {
            function = lib.makeFunction(name: functionName)
        } else {
            return nil
        }

        guard let function else { return nil }
        do {
            let pipeline = try device.makeComputePipelineState(function: function)
            kernelCache[functionName] = pipeline
            return pipeline
        } catch {
            print("[metaphor] Failed to create compute pipeline for \(functionName): \(error)")
            return nil
        }
    }

    // MARK: - Private: テクスチャプール

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

    // MARK: - Private: ガウシアンウェイト

    private func getOrCreateWeightBuffer(radius: Int) -> MTLBuffer? {
        if let cached = weightBufferCache[radius] { return cached }

        let sigma = Float(radius) / 3.0
        let size = radius * 2 + 1
        var weights = [Float](repeating: 0, count: size)
        var sum: Float = 0
        for i in 0..<size {
            let x = Float(i - radius)
            weights[i] = exp(-(x * x) / (2 * sigma * sigma))
            sum += weights[i]
        }
        for i in 0..<size { weights[i] /= sum }

        guard let buffer = device.makeBuffer(
            bytes: weights,
            length: weights.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else { return nil }

        weightBufferCache[radius] = buffer
        return buffer
    }

    // MARK: - Private: フィルターディスパッチヘルパー

    private func kernelName(for filter: FilterType) -> String {
        switch filter {
        case .threshold: "filter_threshold"
        case .gray: "filter_gray"
        case .invert: "filter_invert"
        case .posterize: "filter_posterize"
        case .blur: "filter_gaussian_h"
        case .erode: "filter_erode"
        case .dilate: "filter_dilate"
        case .edgeDetect: "filter_edgeDetect"
        case .sharpen: "filter_sharpen"
        case .sepia: "filter_sepia"
        case .pixelate: "filter_pixelate"
        // MPS ケースは apply() 内の早期リターンで処理
        case .mpsBlur, .mpsSobel, .mpsLaplacian, .mpsErode, .mpsDilate, .mpsMedian, .mpsThreshold:
            "filter_gray"
        }
    }

    private func paramValue(for filter: FilterType) -> Float {
        switch filter {
        case .threshold(let level): level
        case .posterize(let levels): Float(max(2, min(255, levels)))
        case .blur(let radius): Float(max(1, radius))
        case .sharpen(let amount): amount
        case .pixelate(let blockSize): Float(max(1, blockSize))
        // MPS ケースは apply() 内の早期リターンで処理
        case .mpsBlur, .mpsSobel, .mpsLaplacian, .mpsErode, .mpsDilate, .mpsMedian, .mpsThreshold:
            0
        default: 0
        }
    }
}
