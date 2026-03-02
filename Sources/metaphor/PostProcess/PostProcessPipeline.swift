@preconcurrency import Metal
import MetalPerformanceShaders
import simd

/// ポストプロセスエフェクトチェーンを管理し、ping-pongテクスチャ方式で適用する
@MainActor
public final class PostProcessPipeline {
    // MARK: - Public

    /// 現在のエフェクトチェーン
    public private(set) var effects: [PostEffect] = []

    // MARK: - Private

    private let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let shaderLibrary: ShaderLibrary

    /// Ping-pong テクスチャ
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    /// パイプラインキャッシュ (フラグメント関数名 -> パイプライン)
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    /// bloom composite用パイプライン (テクスチャ2枚入力)
    private var bloomCompositePipeline: MTLRenderPipelineState?

    /// Kawaseブラー用テクスチャチェーン（ダウンサンプル解像度列）
    private var kawaseChain: [MTLTexture] = []
    private var kawaseChainWidth: Int = 0
    private var kawaseChainHeight: Int = 0

    /// blit頂点シェーダー（全パスで共有）
    private let blitVertexFunction: MTLFunction

    /// MPS 画像フィルタ（lazy）
    private lazy var mpsFilter: MPSImageFilterWrapper = {
        MPSImageFilterWrapper(device: device, commandQueue: commandQueue)
    }()

    /// CoreImage フィルタラッパー（lazy）
    private lazy var ciFilterWrapper: CIFilterWrapper = {
        CIFilterWrapper(device: device, commandQueue: commandQueue)
    }()

    // MARK: - Initialization

    init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary) throws {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = shaderLibrary

        guard let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw PostProcessError.shaderNotFound("blitVertex")
        }
        self.blitVertexFunction = vertexFn
    }

    // MARK: - Effect Management

    public func add(_ effect: PostEffect) {
        effects.append(effect)
    }

    public func remove(at index: Int) {
        guard effects.indices.contains(index) else { return }
        effects.remove(at: index)
    }

    public func removeAll() {
        effects.removeAll()
    }

    public func set(_ effects: [PostEffect]) {
        self.effects = effects
    }

    // MARK: - Apply

    /// エフェクトチェーンを適用し、最終結果テクスチャを返す
    func apply(source: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard !effects.isEmpty else { return source }

        ensureTextures(width: source.width, height: source.height)
        guard let texA = textureA, let texB = textureB else { return source }

        let texelSize = SIMD2<Float>(
            1.0 / Float(source.width),
            1.0 / Float(source.height)
        )

        var currentInput = source
        var useA = true

        for effect in effects {
            switch effect {
            case .bloom(let intensity, let threshold):
                // Kawaseブラーベースのbloom: extract → kawaseBlur → composite
                let bloomParams = makeParams(
                    texelSize: texelSize, intensity: intensity, threshold: threshold
                )

                // 1. Extract: currentInput → texA
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: texA,
                    fragmentName: PostProcessShaders.FunctionName.postBloomExtract,
                    params: bloomParams
                )
                // 2. Kawase blur: texA → texB
                let _ = applyKawaseBlur(
                    commandBuffer: commandBuffer,
                    source: texA, output: texB,
                    iterations: 4
                )
                // 3. Composite: currentInput(original) + texB(bloom) → texA
                renderCompositePass(
                    commandBuffer: commandBuffer,
                    original: currentInput, bloom: texB,
                    output: texA,
                    params: bloomParams
                )
                currentInput = texA
                useA = false

            case .blur(let radius):
                let output = useA ? texA : texB
                if radius >= 4 {
                    // Kawaseブラー（大半径で高速）
                    let iterations = max(2, min(Int(log2(radius)), 6))
                    let _ = applyKawaseBlur(
                        commandBuffer: commandBuffer,
                        source: currentInput, output: output,
                        iterations: iterations
                    )
                } else {
                    // 小半径はGaussianを維持
                    let params = makeParams(texelSize: texelSize, radius: radius)
                    let mid = useA ? texB : texA
                    renderPass(
                        commandBuffer: commandBuffer,
                        input: currentInput, output: mid,
                        fragmentName: PostProcessShaders.FunctionName.postBlurH,
                        params: params
                    )
                    renderPass(
                        commandBuffer: commandBuffer,
                        input: mid, output: output,
                        fragmentName: PostProcessShaders.FunctionName.postBlurV,
                        params: params
                    )
                }
                currentInput = output
                useA = !useA

            case .custom(let custom):
                // カスタムエフェクト（単パス）
                let output = useA ? texA : texB
                let params = makeParams(texelSize: texelSize, effect: effect)
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: output,
                    fragmentName: custom.fragmentFunctionName,
                    params: params,
                    libraryKey: custom.libraryKey,
                    customParams: custom.hasCustomParameters ? custom.parameters : nil
                )
                currentInput = output
                useA = !useA

            // MARK: MPS Effects
            case .mpsBlur(let sigma):
                let output = useA ? texA : texB
                mpsFilter.encodeGaussianBlur(
                    commandBuffer: commandBuffer,
                    source: currentInput, destination: output, sigma: sigma
                )
                currentInput = output
                useA = !useA

            case .mpsSobel:
                let output = useA ? texA : texB
                mpsFilter.encodeSobel(
                    commandBuffer: commandBuffer,
                    source: currentInput, destination: output
                )
                currentInput = output
                useA = !useA

            case .mpsErode(let radius):
                let output = useA ? texA : texB
                mpsFilter.encodeErode(
                    commandBuffer: commandBuffer,
                    source: currentInput, destination: output, radius: radius
                )
                currentInput = output
                useA = !useA

            case .mpsDilate(let radius):
                let output = useA ? texA : texB
                mpsFilter.encodeDilate(
                    commandBuffer: commandBuffer,
                    source: currentInput, destination: output, radius: radius
                )
                currentInput = output
                useA = !useA

            // MARK: CoreImage Effects
            case .ciFilter(let preset):
                let output = useA ? texA : texB
                let texSize = CGSize(width: currentInput.width, height: currentInput.height)
                ciFilterWrapper.apply(
                    filterName: preset.filterName,
                    parameters: preset.parameters(textureSize: texSize),
                    source: currentInput, destination: output,
                    commandBuffer: commandBuffer
                )
                currentInput = output
                useA = !useA

            case .ciFilterRaw(let name, let params):
                let output = useA ? texA : texB
                ciFilterWrapper.apply(
                    filterName: name,
                    parameters: params,
                    source: currentInput, destination: output,
                    commandBuffer: commandBuffer
                )
                currentInput = output
                useA = !useA

            default:
                // 単パスエフェクト (invert, grayscale, vignette, chromaticAberration, colorGrade)
                let output = useA ? texA : texB
                let params = makeParams(texelSize: texelSize, effect: effect)
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: output,
                    fragmentName: fragmentName(for: effect),
                    params: params
                )
                currentInput = output
                useA = !useA
            }
        }

        return currentInput
    }

    /// テクスチャキャッシュを破棄（resizeCanvas時に呼ぶ）
    func invalidateTextures() {
        textureA = nil
        textureB = nil
        currentWidth = 0
        currentHeight = 0
        kawaseChain.removeAll()
        kawaseChainWidth = 0
        kawaseChainHeight = 0
        ciFilterWrapper.invalidateTextures()
    }

    /// パイプラインキャッシュを破棄（シェーダーホットリロード時に呼ぶ）
    func invalidatePipelines() {
        pipelineCache.removeAll()
    }

    // MARK: - Private: Texture Management

    private func ensureTextures(width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        textureA = device.makeTexture(descriptor: desc)
        textureB = device.makeTexture(descriptor: desc)
        currentWidth = width
        currentHeight = height
    }

    // MARK: - Private: Kawase Blur

    private func ensureKawaseChain(width: Int, height: Int, iterations: Int) {
        guard width != kawaseChainWidth || height != kawaseChainHeight
              || kawaseChain.count != iterations else { return }

        kawaseChain.removeAll()
        var w = width / 2
        var h = height / 2
        for _ in 0..<iterations {
            w = max(1, w)
            h = max(1, h)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false
            )
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            if let tex = device.makeTexture(descriptor: desc) {
                kawaseChain.append(tex)
            }
            w /= 2
            h /= 2
        }
        kawaseChainWidth = width
        kawaseChainHeight = height
    }

    /// Kawase ダウン/アップサンプルによるブラーを適用し、結果テクスチャを返す
    private func applyKawaseBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        output: MTLTexture,
        iterations: Int
    ) -> MTLTexture {
        let iters = max(1, min(iterations, 6))
        ensureKawaseChain(width: source.width, height: source.height, iterations: iters)
        guard kawaseChain.count == iters else { return source }

        // ダウンサンプルパス: source → chain[0] → chain[1] → ... → chain[n-1]
        var input = source
        for i in 0..<iters {
            let dst = kawaseChain[i]
            var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            renderKawasePass(
                commandBuffer: commandBuffer,
                input: input, output: dst,
                functionName: KawaseBlurShaders.FunctionName.kawaseDownsample,
                texelSize: &texelSize
            )
            input = dst
        }

        // アップサンプルパス: chain[n-1] → chain[n-2] → ... → chain[0] → output
        for i in stride(from: iters - 2, through: 0, by: -1) {
            let dst = kawaseChain[i]
            var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            renderKawasePass(
                commandBuffer: commandBuffer,
                input: input, output: dst,
                functionName: KawaseBlurShaders.FunctionName.kawaseUpsample,
                texelSize: &texelSize
            )
            input = dst
        }

        // 最終アップサンプル: chain[0] → output（元解像度）
        var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        renderKawasePass(
            commandBuffer: commandBuffer,
            input: input, output: output,
            functionName: KawaseBlurShaders.FunctionName.kawaseUpsample,
            texelSize: &texelSize
        )
        return output
    }

    private func renderKawasePass(
        commandBuffer: MTLCommandBuffer,
        input: MTLTexture,
        output: MTLTexture,
        functionName: String,
        texelSize: inout SIMD2<Float>
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = output
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
              let pipeline = getOrCreatePipeline(
                  fragmentName: functionName,
                  libraryKey: ShaderLibrary.BuiltinKey.kawaseBlur
              ) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        encoder.setFragmentBytes(&texelSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    // MARK: - Private: Render Passes

    private func renderPass(
        commandBuffer: MTLCommandBuffer,
        input: MTLTexture,
        output: MTLTexture,
        fragmentName: String,
        params: PostProcessParams,
        libraryKey: String? = nil,
        customParams: [UInt8]? = nil
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = output
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
              let pipeline = getOrCreatePipeline(
                  fragmentName: fragmentName,
                  libraryKey: libraryKey
              ) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)

        var p = params
        encoder.setFragmentBytes(&p, length: MemoryLayout<PostProcessParams>.size, index: 0)

        if let customParams, !customParams.isEmpty {
            customParams.withUnsafeBufferPointer { ptr in
                encoder.setFragmentBytes(
                    ptr.baseAddress!,
                    length: ptr.count,
                    index: 1
                )
            }
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func renderCompositePass(
        commandBuffer: MTLCommandBuffer,
        original: MTLTexture,
        bloom: MTLTexture,
        output: MTLTexture,
        params: PostProcessParams
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = output
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
              let pipeline = getOrCreateBloomCompositePipeline() else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(original, index: 0)
        encoder.setFragmentTexture(bloom, index: 1)

        var p = params
        encoder.setFragmentBytes(&p, length: MemoryLayout<PostProcessParams>.size, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    // MARK: - Private: Pipeline Management

    private func getOrCreatePipeline(
        fragmentName: String,
        libraryKey: String? = nil
    ) -> MTLRenderPipelineState? {
        let cacheKey = libraryKey.map { "\($0).\(fragmentName)" } ?? fragmentName
        if let cached = pipelineCache[cacheKey] {
            return cached
        }

        let key = libraryKey ?? ShaderLibrary.BuiltinKey.postProcess
        guard let fragmentFn = shaderLibrary.function(
            named: fragmentName,
            from: key
        ) else {
            return nil
        }

        do {
            let pipeline = try PipelineFactory(device: device)
                .vertex(blitVertexFunction)
                .fragment(fragmentFn)
                .noDepth()
                .build()
            pipelineCache[cacheKey] = pipeline
            return pipeline
        } catch {
            return nil
        }
    }

    private func getOrCreateBloomCompositePipeline() -> MTLRenderPipelineState? {
        if let cached = bloomCompositePipeline {
            return cached
        }

        guard let fragmentFn = shaderLibrary.function(
            named: PostProcessShaders.FunctionName.postBloomComposite,
            from: ShaderLibrary.BuiltinKey.postProcess
        ) else {
            return nil
        }

        do {
            let pipeline = try PipelineFactory(device: device)
                .vertex(blitVertexFunction)
                .fragment(fragmentFn)
                .noDepth()
                .build()
            bloomCompositePipeline = pipeline
            return pipeline
        } catch {
            return nil
        }
    }

    // MARK: - Private: Parameter Helpers

    private func fragmentName(for effect: PostEffect) -> String {
        switch effect {
        case .invert: PostProcessShaders.FunctionName.postInvert
        case .grayscale: PostProcessShaders.FunctionName.postGrayscale
        case .vignette: PostProcessShaders.FunctionName.postVignette
        case .chromaticAberration: PostProcessShaders.FunctionName.postChromaticAberration
        case .colorGrade: PostProcessShaders.FunctionName.postColorGrade
        case .blur: PostProcessShaders.FunctionName.postBlurH
        case .bloom: PostProcessShaders.FunctionName.postBloomExtract
        case .custom(let custom): custom.fragmentFunctionName
        // MPS/CI effects are handled in apply() directly, not via fragmentName
        case .mpsBlur, .mpsSobel, .mpsErode, .mpsDilate,
             .ciFilter, .ciFilterRaw:
            "" // never reached
        }
    }

    private func makeParams(
        texelSize: SIMD2<Float>,
        effect: PostEffect
    ) -> PostProcessParams {
        switch effect {
        case .invert, .grayscale:
            return PostProcessParams(texelSize: texelSize)
        case .vignette(let intensity, let smoothness):
            return PostProcessParams(
                texelSize: texelSize, intensity: intensity, smoothness: smoothness
            )
        case .chromaticAberration(let intensity):
            return PostProcessParams(texelSize: texelSize, intensity: intensity)
        case .colorGrade(let brightness, let contrast, let saturation, let temperature):
            return PostProcessParams(
                texelSize: texelSize,
                brightness: brightness, contrast: contrast,
                saturation: saturation, temperature: temperature
            )
        case .blur(let radius):
            return makeParams(texelSize: texelSize, radius: radius)
        case .bloom(let intensity, let threshold):
            return makeParams(
                texelSize: texelSize, intensity: intensity, threshold: threshold
            )
        case .custom(let custom):
            return PostProcessParams(
                texelSize: texelSize,
                intensity: custom.intensity,
                threshold: custom.threshold,
                radius: custom.radius,
                smoothness: custom.smoothness
            )
        // MPS/CI effects don't use PostProcessParams
        case .mpsBlur, .mpsSobel, .mpsErode, .mpsDilate,
             .ciFilter, .ciFilterRaw:
            return PostProcessParams(texelSize: texelSize)
        }
    }

    private func makeParams(
        texelSize: SIMD2<Float>,
        intensity: Float = 0,
        threshold: Float = 0,
        radius: Float = 0
    ) -> PostProcessParams {
        PostProcessParams(
            texelSize: texelSize,
            intensity: intensity,
            threshold: threshold,
            radius: radius
        )
    }
}

// MARK: - Error

enum PostProcessError: Error {
    case shaderNotFound(String)
}
