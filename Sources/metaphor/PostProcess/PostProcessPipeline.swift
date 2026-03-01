@preconcurrency import Metal
import simd

/// ポストプロセスエフェクトチェーンを管理し、ping-pongテクスチャ方式で適用する
@MainActor
public final class PostProcessPipeline {
    // MARK: - Public

    /// 現在のエフェクトチェーン
    public private(set) var effects: [PostEffect] = []

    // MARK: - Private

    private let device: MTLDevice
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

    /// blit頂点シェーダー（全パスで共有）
    private let blitVertexFunction: MTLFunction

    // MARK: - Initialization

    init(device: MTLDevice, shaderLibrary: ShaderLibrary) throws {
        self.device = device
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
                // 4パス: extract → blurH → blurV → composite
                let bloomParams = makeParams(
                    texelSize: texelSize, intensity: intensity, threshold: threshold
                )
                let blurParams = makeParams(
                    texelSize: texelSize, radius: 8
                )

                // 1. Extract: currentInput → texA
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: texA,
                    fragmentName: PostProcessShaders.FunctionName.postBloomExtract,
                    params: bloomParams
                )
                // 2. BlurH: texA → texB
                renderPass(
                    commandBuffer: commandBuffer,
                    input: texA, output: texB,
                    fragmentName: PostProcessShaders.FunctionName.postBlurH,
                    params: blurParams
                )
                // 3. BlurV: texB → texA (texA = blurred bloom)
                renderPass(
                    commandBuffer: commandBuffer,
                    input: texB, output: texA,
                    fragmentName: PostProcessShaders.FunctionName.postBlurV,
                    params: blurParams
                )
                // 4. Composite: currentInput(original) + texA(bloom) → texB
                renderCompositePass(
                    commandBuffer: commandBuffer,
                    original: currentInput, bloom: texA,
                    output: texB,
                    params: bloomParams
                )
                currentInput = texB
                useA = true

            case .blur(let radius):
                // 2パス separable blur
                let params = makeParams(texelSize: texelSize, radius: radius)
                let target1 = useA ? texA : texB
                let target2 = useA ? texB : texA
                // H pass
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: target1,
                    fragmentName: PostProcessShaders.FunctionName.postBlurH,
                    params: params
                )
                // V pass
                renderPass(
                    commandBuffer: commandBuffer,
                    input: target1, output: target2,
                    fragmentName: PostProcessShaders.FunctionName.postBlurV,
                    params: params
                )
                currentInput = target2
                useA = (target2 === texA)

            default:
                // 単パスエフェクト
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

    // MARK: - Private: Render Passes

    private func renderPass(
        commandBuffer: MTLCommandBuffer,
        input: MTLTexture,
        output: MTLTexture,
        fragmentName: String,
        params: PostProcessParams
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = output
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
              let pipeline = getOrCreatePipeline(fragmentName: fragmentName) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)

        var p = params
        encoder.setFragmentBytes(&p, length: MemoryLayout<PostProcessParams>.size, index: 0)

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

    private func getOrCreatePipeline(fragmentName: String) -> MTLRenderPipelineState? {
        if let cached = pipelineCache[fragmentName] {
            return cached
        }

        guard let fragmentFn = shaderLibrary.function(
            named: fragmentName,
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
            pipelineCache[fragmentName] = pipeline
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
