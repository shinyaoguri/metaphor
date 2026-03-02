@preconcurrency import Metal
import MetalPerformanceShaders
import simd

/// Manage a chain of post-process effects and apply them using ping-pong textures.
@MainActor
public final class PostProcessPipeline {
    // MARK: - Public

    /// The current chain of post-process effects.
    public private(set) var effects: [PostEffect] = []

    // MARK: - Private

    private let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let shaderLibrary: ShaderLibrary

    /// Ping-pong textures for alternating read/write between effect passes.
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    /// Pipeline state cache keyed by fragment function name.
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    /// Pipeline state for bloom composite pass (two-texture input).
    private var bloomCompositePipeline: MTLRenderPipelineState?

    /// Texture chain for Kawase blur downsample/upsample passes.
    private var kawaseChain: [MTLTexture] = []
    private var kawaseChainWidth: Int = 0
    private var kawaseChainHeight: Int = 0

    /// Blit vertex shader function shared across all passes.
    private let blitVertexFunction: MTLFunction

    /// Lazily initialized MPS image filter wrapper.
    private lazy var mpsFilter: MPSImageFilterWrapper = {
        MPSImageFilterWrapper(device: device, commandQueue: commandQueue)
    }()

    /// Lazily initialized CoreImage filter wrapper.
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
            throw MetaphorError.postProcessShaderNotFound("blitVertex")
        }
        self.blitVertexFunction = vertexFn
    }

    // MARK: - Effect Management

    /// Append a post-process effect to the end of the chain.
    ///
    /// - Parameter effect: The effect to add.
    public func add(_ effect: PostEffect) {
        effects.append(effect)
    }

    /// Remove the effect at the specified index.
    ///
    /// - Parameter index: The index of the effect to remove. No-op if out of bounds.
    public func remove(at index: Int) {
        guard effects.indices.contains(index) else { return }
        effects.remove(at: index)
    }

    /// Remove all effects from the chain.
    public func removeAll() {
        effects.removeAll()
    }

    /// Replace the entire effect chain with the given array.
    ///
    /// - Parameter effects: The new array of effects.
    public func set(_ effects: [PostEffect]) {
        self.effects = effects
    }

    // MARK: - Apply

    /// Apply the full effect chain to the source texture and return the final result.
    ///
    /// - Parameters:
    ///   - source: The input texture to process.
    ///   - commandBuffer: The command buffer to encode GPU work into.
    /// - Returns: The output texture after all effects have been applied.
    // TODO: Optimize by merging consecutive Metal effects into a single render command encoder.
    // Currently each effect creates and ends its own encoder, but sharing encoders for
    // consecutive same-type effects would reduce GPU command overhead (#16).
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
                // Kawase blur-based bloom: extract -> kawaseBlur -> composite
                let bloomParams = makeParams(
                    texelSize: texelSize, intensity: intensity, threshold: threshold
                )

                // 1. Extract bright areas: currentInput -> texA
                renderPass(
                    commandBuffer: commandBuffer,
                    input: currentInput, output: texA,
                    fragmentName: PostProcessShaders.FunctionName.postBloomExtract,
                    params: bloomParams
                )
                // 2. Kawase blur: texA -> texB
                let _ = applyKawaseBlur(
                    commandBuffer: commandBuffer,
                    source: texA, output: texB,
                    iterations: 4
                )
                // 3. Composite original + bloom: currentInput(original) + texB(bloom) -> texA
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
                    // Kawase blur (faster for large radii)
                    let iterations = max(2, min(Int(log2(radius)), 6))
                    let _ = applyKawaseBlur(
                        commandBuffer: commandBuffer,
                        source: currentInput, output: output,
                        iterations: iterations
                    )
                } else {
                    // Keep Gaussian for small radii
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
                // Custom effect (single pass)
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
                let anyParams = params.mapValues { $0.anyValue }
                ciFilterWrapper.apply(
                    filterName: name,
                    parameters: anyParams,
                    source: currentInput, destination: output,
                    commandBuffer: commandBuffer
                )
                currentInput = output
                useA = !useA

            default:
                // Single-pass effects (invert, grayscale, vignette, chromaticAberration, colorGrade)
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

    /// Invalidate the texture cache (call when the canvas is resized).
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

    /// Invalidate the pipeline cache (call after shader hot reload).
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

    /// Apply Kawase downsample/upsample blur and return the result texture.
    private func applyKawaseBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        output: MTLTexture,
        iterations: Int
    ) -> MTLTexture {
        let iters = max(1, min(iterations, 6))
        ensureKawaseChain(width: source.width, height: source.height, iterations: iters)
        guard kawaseChain.count == iters else { return source }

        // Downsample pass: source -> chain[0] -> chain[1] -> ... -> chain[n-1]
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

        // Upsample pass: chain[n-1] -> chain[n-2] -> ... -> chain[0] -> output
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

        // Final upsample: chain[0] -> output (back to original resolution)
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
                .sampleCount(1)
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
                .sampleCount(1)
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
