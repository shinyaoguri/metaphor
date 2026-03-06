@preconcurrency import Metal
import simd

// MARK: - PostEffectContext

/// Provides rendering infrastructure for post-process effects.
///
/// Effects use this context to render fullscreen passes, apply Kawase blur,
/// and manage scratch textures.
@MainActor
public final class PostEffectContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    let shaderLibrary: ShaderLibrary
    private let blitVertexFunction: MTLFunction

    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var bloomCompositePipeline: MTLRenderPipelineState?

    // Kawase blur chain
    private var kawaseChain: [MTLTexture] = []
    private var kawaseChainWidth: Int = 0
    private var kawaseChainHeight: Int = 0

    // Scratch texture for multi-pass effects
    private var scratchTex: MTLTexture?
    private var scratchWidth: Int = 0
    private var scratchHeight: Int = 0

    // MTLHeap for efficient texture allocation
    private var textureHeap: MTLHeap?
    private var heapWidth: Int = 0
    private var heapHeight: Int = 0

    init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary, blitVertexFunction: MTLFunction) {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = shaderLibrary
        self.blitVertexFunction = blitVertexFunction
    }

    // MARK: - Scratch Textures

    /// Get a scratch texture matching the given dimensions (reused across frames).
    func getScratchTexture(width: Int, height: Int) -> MTLTexture? {
        if scratchWidth == width && scratchHeight == height, let tex = scratchTex {
            return tex
        }
        ensureHeap(width: width, height: height)
        scratchTex = makeHeapTexture(width: width, height: height)
        scratchWidth = width
        scratchHeight = height
        return scratchTex
    }

    // MARK: - Render Passes

    /// Render a single fullscreen pass with the given fragment shader and parameters.
    func renderPass(
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
              let pipeline = getOrCreatePipeline(fragmentName: fragmentName, libraryKey: libraryKey)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)

        var p = params
        encoder.setFragmentBytes(&p, length: MemoryLayout<PostProcessParams>.size, index: 0)

        if let customParams, !customParams.isEmpty {
            customParams.withUnsafeBufferPointer { ptr in
                encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count, index: 1)
            }
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// Render a composite pass blending two textures (used by bloom).
    func renderCompositePass(
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
              let pipeline = getOrCreateBloomCompositePipeline()
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(original, index: 0)
        encoder.setFragmentTexture(bloom, index: 1)

        var p = params
        encoder.setFragmentBytes(&p, length: MemoryLayout<PostProcessParams>.size, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    // MARK: - Kawase Blur

    /// Apply Kawase downsample/upsample blur.
    @discardableResult
    func applyKawaseBlur(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        output: MTLTexture,
        iterations: Int
    ) -> MTLTexture {
        let iters = max(1, min(iterations, 6))
        ensureKawaseChain(width: source.width, height: source.height, iterations: iters)
        guard kawaseChain.count == iters else { return source }

        // Downsample
        var input = source
        for i in 0..<iters {
            let dst = kawaseChain[i]
            var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            renderKawasePass(
                commandBuffer: commandBuffer, input: input, output: dst,
                functionName: KawaseBlurShaders.FunctionName.kawaseDownsample, texelSize: &texelSize
            )
            input = dst
        }

        // Upsample
        for i in stride(from: iters - 2, through: 0, by: -1) {
            let dst = kawaseChain[i]
            var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            renderKawasePass(
                commandBuffer: commandBuffer, input: input, output: dst,
                functionName: KawaseBlurShaders.FunctionName.kawaseUpsample, texelSize: &texelSize
            )
            input = dst
        }

        // Final upsample to output
        var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        renderKawasePass(
            commandBuffer: commandBuffer, input: input, output: output,
            functionName: KawaseBlurShaders.FunctionName.kawaseUpsample, texelSize: &texelSize
        )
        return output
    }

    // MARK: - Pipeline Management

    func getOrCreatePipeline(fragmentName: String, libraryKey: String? = nil) -> MTLRenderPipelineState? {
        let cacheKey = libraryKey.map { "\($0).\(fragmentName)" } ?? fragmentName
        if let cached = pipelineCache[cacheKey] { return cached }

        let key = libraryKey ?? ShaderLibrary.BuiltinKey.postProcess
        guard let fragmentFn = shaderLibrary.function(named: fragmentName, from: key) else { return nil }

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

    // MARK: - Cache Invalidation

    func invalidateTextures() {
        kawaseChain.removeAll()
        kawaseChainWidth = 0
        kawaseChainHeight = 0
        scratchTex = nil
        scratchWidth = 0
        scratchHeight = 0
        textureHeap = nil
        heapWidth = 0
        heapHeight = 0
    }

    func invalidatePipelines() {
        pipelineCache.removeAll()
        bloomCompositePipeline = nil
    }

    // MARK: - Private

    private func ensureKawaseChain(width: Int, height: Int, iterations: Int) {
        guard width != kawaseChainWidth || height != kawaseChainHeight
              || kawaseChain.count != iterations else { return }

        kawaseChain.removeAll()
        ensureHeap(width: width, height: height)

        var w = width / 2
        var h = height / 2
        for _ in 0..<iterations {
            w = max(1, w)
            h = max(1, h)
            if let tex = makeHeapTexture(width: w, height: h) {
                kawaseChain.append(tex)
            }
            w /= 2
            h /= 2
        }
        kawaseChainWidth = width
        kawaseChainHeight = height
    }

    /// Ensure the heap is large enough for the current render dimensions.
    private func ensureHeap(width: Int, height: Int) {
        guard width != heapWidth || height != heapHeight else { return }

        // Estimate heap size: 2 ping-pong + 1 scratch + 6 kawase levels
        // Each texture at full size = width * height * 4 bytes (BGRA8)
        let fullSize = width * height * 4
        // Kawase mips: 1/4 + 1/16 + 1/64 + ... ≈ 1/3 of full
        let estimatedSize = fullSize * 4  // ~3 full textures + kawase chain
        let heapDesc = MTLHeapDescriptor()
        heapDesc.size = estimatedSize
        heapDesc.storageMode = .private
        heapDesc.type = .automatic
        textureHeap = device.makeHeap(descriptor: heapDesc)
        textureHeap?.label = "metaphor.postprocess.heap"
        heapWidth = width
        heapHeight = height
    }

    /// Create a texture from the heap, falling back to device allocation.
    func makeHeapTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        // Try heap allocation first, fall back to device
        if let heap = textureHeap, let tex = heap.makeTexture(descriptor: desc) {
            return tex
        }
        return device.makeTexture(descriptor: desc)
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

    private func getOrCreateBloomCompositePipeline() -> MTLRenderPipelineState? {
        if let cached = bloomCompositePipeline { return cached }

        guard let fragmentFn = shaderLibrary.function(
            named: PostProcessShaders.FunctionName.postBloomComposite,
            from: ShaderLibrary.BuiltinKey.postProcess
        ) else { return nil }

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
}

// MARK: - PostProcessPipeline

/// Manage a chain of post-process effects and apply them using ping-pong textures.
@MainActor
public final class PostProcessPipeline {
    // MARK: - Public

    /// The current chain of post-process effects.
    public private(set) var effects: [any PostEffect] = []

    // MARK: - Private

    private let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let context: PostEffectContext

    /// Ping-pong textures for alternating read/write between effect passes.
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    // MARK: - Initialization

    public init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary) throws {
        self.device = device
        self.commandQueue = commandQueue

        guard let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw MetaphorError.shaderNotFound("blitVertex")
        }

        self.context = PostEffectContext(
            device: device,
            commandQueue: commandQueue,
            shaderLibrary: shaderLibrary,
            blitVertexFunction: vertexFn
        )
    }

    // MARK: - Effect Management

    /// Append a post-process effect to the end of the chain.
    public func add(_ effect: any PostEffect) {
        effects.append(effect)
    }

    /// Remove the effect at the specified index.
    public func remove(at index: Int) {
        guard effects.indices.contains(index) else { return }
        effects.remove(at: index)
    }

    /// Remove all effects from the chain.
    public func removeAll() {
        effects.removeAll()
    }

    /// Replace the entire effect chain with the given array.
    public func set(_ effects: [any PostEffect]) {
        self.effects = effects
    }

    // MARK: - Apply

    /// Apply the full effect chain to the source texture and return the final result.
    public func apply(source: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard !effects.isEmpty else { return source }

        ensureTextures(width: source.width, height: source.height)
        guard let texA = textureA, let texB = textureB else { return source }

        var currentInput = source
        var useA = true

        for effect in effects {
            let output = useA ? texA : texB
            effect.apply(input: currentInput, output: output, commandBuffer: commandBuffer, context: context)
            currentInput = output
            useA = !useA
        }

        return currentInput
    }

    /// Invalidate the texture cache (call when the canvas is resized).
    func invalidateTextures() {
        textureA = nil
        textureB = nil
        currentWidth = 0
        currentHeight = 0
        context.invalidateTextures()
    }

    /// Invalidate the pipeline cache (call after shader hot reload).
    func invalidatePipelines() {
        context.invalidatePipelines()
    }

    // MARK: - Private

    private func ensureTextures(width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }

        textureA = context.makeHeapTexture(width: width, height: height)
        textureB = context.makeHeapTexture(width: width, height: height)
        currentWidth = width
        currentHeight = height
    }
}
