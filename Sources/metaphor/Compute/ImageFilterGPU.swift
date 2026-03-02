@preconcurrency import Metal

/// GPU画像フィルタのユニフォーム構造体
struct FilterParams {
    var width: UInt32
    var height: UInt32
    var param1: Float
    var param2: Float
}

/// GPU コンピュートシェーダーによる画像フィルタ
///
/// CPU版 `ImageFilter` の代替。BGRA テクスチャをネイティブに処理し、
/// `.private` ストレージモードのテクスチャにも対応する。
@MainActor
public final class ImageFilterGPU {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// コンパイル済みライブラリ（全カーネルを含む）
    private var library: MTLLibrary?

    /// カーネルキャッシュ (関数名 -> パイプライン)
    private var kernelCache: [String: MTLComputePipelineState] = [:]

    /// テクスチャプール (サイズキー -> テクスチャ)
    private var texturePool: [String: MTLTexture] = [:]

    /// ガウシアンウェイトバッファキャッシュ (radius -> バッファ)
    private var weightBufferCache: [Int: MTLBuffer] = [:]

    /// ShaderLibrary からの事前コンパイル済みライブラリ参照
    private weak var shaderLibrary: ShaderLibrary?

    /// MPS 画像フィルタ（lazy）
    private lazy var mpsFilter: MPSImageFilterWrapper = {
        MPSImageFilterWrapper(device: device, commandQueue: commandQueue)
    }()

    init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary? = nil) {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = shaderLibrary
    }

    // MARK: - Public API

    /// MImage にフィルタを適用（テクスチャを差し替える）
    public func apply(_ filter: FilterType, to image: MImage) {
        let srcTex = image.texture
        let w = srcTex.width
        let h = srcTex.height

        guard let outTex = getOrCreateTexture(width: w, height: h, tag: "output") else { return }

        // MPS フィルタは専用パスに委譲
        switch filter {
        case .mpsBlur(let sigma):
            mpsFilter.gaussianBlur(image, sigma: sigma); return
        case .mpsSobel:
            mpsFilter.sobel(image); return
        case .mpsLaplacian:
            mpsFilter.laplacian(image); return
        case .mpsErode(let radius):
            mpsFilter.erode(image, radius: radius); return
        case .mpsDilate(let radius):
            mpsFilter.dilate(image, radius: radius); return
        case .mpsMedian(let diameter):
            mpsFilter.median(image, diameter: diameter); return
        case .mpsThreshold(let value):
            mpsFilter.threshold(image, value: value); return
        default:
            break
        }

        switch filter {
        case .blur(let radius):
            applyGaussianBlur(src: srcTex, dst: outTex, radius: max(1, radius), width: w, height: h)
        default:
            applySinglePass(filter, src: srcTex, dst: outTex, width: w, height: h)
        }

        image.replaceTexture(outTex)
        // 出力テクスチャは image に渡したのでプールから外す
        texturePool.removeValue(forKey: "\(w)_\(h)_output")
    }

    // MARK: - Private: Single Pass

    private func applySinglePass(
        _ filter: FilterType, src: MTLTexture, dst: MTLTexture, width: Int, height: Int
    ) {
        let functionName = kernelName(for: filter)
        guard let pipeline = getOrCreatePipeline(functionName: functionName),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

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
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - Private: Gaussian Blur (2-pass separable)

    private func applyGaussianBlur(
        src: MTLTexture, dst: MTLTexture, radius: Int, width: Int, height: Int
    ) {
        guard let tempTex = getOrCreateTexture(width: width, height: height, tag: "blur_temp"),
              let hPipeline = getOrCreatePipeline(functionName: "filter_gaussian_h"),
              let vPipeline = getOrCreatePipeline(functionName: "filter_gaussian_v"),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        var params = FilterParams(
            width: UInt32(width), height: UInt32(height),
            param1: Float(radius), param2: 0
        )
        let weightBuffer = getOrCreateWeightBuffer(radius: radius)

        let tw = hPipeline.threadExecutionWidth
        let th = max(1, hPipeline.maxTotalThreadsPerThreadgroup / tw)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        let groupSize = MTLSize(width: tw, height: th, depth: 1)

        // Horizontal pass: src → tempTex
        encoder.setComputePipelineState(hPipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(tempTex, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<FilterParams>.size, index: 0)
        if let wb = weightBuffer {
            encoder.setBuffer(wb, offset: 0, index: 1)
        }
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

        // Memory barrier
        encoder.memoryBarrier(scope: .textures)

        // Vertical pass: tempTex → dst
        encoder.setComputePipelineState(vPipeline)
        encoder.setTexture(tempTex, index: 0)
        encoder.setTexture(dst, index: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - Private: Kernel Management

    private func ensureLibrary() -> MTLLibrary? {
        if let lib = library { return lib }
        do {
            let lib = try device.makeLibrary(source: ImageFilterShaders.source, options: nil)
            self.library = lib
            return lib
        } catch {
            print("[metaphor] Failed to compile ImageFilter shaders: \(error)")
            return nil
        }
    }

    private func getOrCreatePipeline(functionName: String) -> MTLComputePipelineState? {
        if let cached = kernelCache[functionName] { return cached }

        // ShaderLibrary 経由 (metallib) を優先
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

    // MARK: - Private: Texture Pool

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

    // MARK: - Private: Gaussian Weights

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

    // MARK: - Private: Filter Dispatch Helpers

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
        // MPS cases are handled via early return in apply()
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
        // MPS cases are handled via early return in apply()
        case .mpsBlur, .mpsSobel, .mpsLaplacian, .mpsErode, .mpsDilate, .mpsMedian, .mpsThreshold:
            0
        default: 0
        }
    }
}
