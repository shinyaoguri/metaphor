@preconcurrency import Metal
import simd

// MARK: - PostEffectContext

/// ポストプロセスエフェクト用のレンダリングインフラを提供します。
///
/// エフェクトはこのコンテキストを使用してフルスクリーンパスのレンダリング、
/// Kawase ブラーの適用、スクラッチテクスチャの管理を行います。
@MainActor
public final class PostEffectContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    let shaderLibrary: ShaderLibrary
    private let blitVertexFunction: MTLFunction

    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var bloomCompositePipeline: MTLRenderPipelineState?

    // Kawase ブラーチェーン
    private var kawaseChain: [MTLTexture] = []
    private var kawaseChainWidth: Int = 0
    private var kawaseChainHeight: Int = 0

    // マルチパスエフェクト用スクラッチテクスチャ
    private var scratchTex: MTLTexture?
    private var scratchWidth: Int = 0
    private var scratchHeight: Int = 0

    // 効率的なテクスチャ確保用 MTLHeap
    private var textureHeap: MTLHeap?
    private var heapWidth: Int = 0
    private var heapHeight: Int = 0

    init(device: MTLDevice, commandQueue: MTLCommandQueue, shaderLibrary: ShaderLibrary, blitVertexFunction: MTLFunction) {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = shaderLibrary
        self.blitVertexFunction = blitVertexFunction
    }

    // MARK: - スクラッチテクスチャ

    /// 指定されたサイズに一致するスクラッチテクスチャを取得します（フレーム間で再利用）。
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

    // MARK: - レンダーパス

    /// 指定されたフラグメントシェーダーとパラメータで単一のフルスクリーンパスをレンダリングします。
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

    /// 2つのテクスチャをブレンドするコンポジットパスをレンダリングします（ブルーム用）。
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

    // MARK: - Kawase ブラー

    /// Kawase ダウンサンプル/アップサンプルブラーを適用します。
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

        // ダウンサンプル
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

        // アップサンプル
        for i in stride(from: iters - 2, through: 0, by: -1) {
            let dst = kawaseChain[i]
            var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            renderKawasePass(
                commandBuffer: commandBuffer, input: input, output: dst,
                functionName: KawaseBlurShaders.FunctionName.kawaseUpsample, texelSize: &texelSize
            )
            input = dst
        }

        // 最終アップサンプルを output へ
        var texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        renderKawasePass(
            commandBuffer: commandBuffer, input: input, output: output,
            functionName: KawaseBlurShaders.FunctionName.kawaseUpsample, texelSize: &texelSize
        )
        return output
    }

    // MARK: - パイプライン管理

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

    // MARK: - キャッシュ無効化

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

    /// 現在のレンダーサイズに対してヒープが十分な大きさであることを保証します。
    private func ensureHeap(width: Int, height: Int) {
        guard width != heapWidth || height != heapHeight else { return }

        // ヒープサイズの見積もり: ピンポン2枚 + スクラッチ1枚 + Kawase 6レベル
        // フルサイズの各テクスチャ = width * height * 4 バイト (BGRA8)
        let fullSize = width * height * 4
        // Kawase ミップ: 1/4 + 1/16 + 1/64 + ... ≈ フルの 1/3
        let estimatedSize = fullSize * 4  // フルテクスチャ約3枚 + Kawase チェーン
        let heapDesc = MTLHeapDescriptor()
        heapDesc.size = estimatedSize
        heapDesc.storageMode = .private
        heapDesc.type = .automatic
        textureHeap = device.makeHeap(descriptor: heapDesc)
        textureHeap?.label = "metaphor.postprocess.heap"
        heapWidth = width
        heapHeight = height
    }

    /// ヒープからテクスチャを作成し、デバイス確保にフォールバックします。
    func makeHeapTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        // まずヒープ確保を試み、失敗時はデバイスにフォールバック
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

/// ポストプロセスエフェクトのチェーンを管理し、ピンポンテクスチャで適用します。
@MainActor
public final class PostProcessPipeline {
    // MARK: - パブリック

    /// 現在のポストプロセスエフェクトチェーン
    public private(set) var effects: [any PostEffect] = []

    // MARK: - Private

    private let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let context: PostEffectContext

    /// エフェクトパス間で読み書きを交互に行うピンポンテクスチャ
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    // MARK: - 初期化

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

    // MARK: - エフェクト管理

    /// ポストプロセスエフェクトをチェーンの末尾に追加します。
    public func add(_ effect: any PostEffect) {
        effects.append(effect)
    }

    /// 指定されたインデックスのエフェクトを削除します。
    public func remove(at index: Int) {
        guard effects.indices.contains(index) else { return }
        effects.remove(at: index)
    }

    /// チェーンから全エフェクトを削除します。
    public func removeAll() {
        effects.removeAll()
    }

    /// エフェクトチェーン全体を指定された配列で置換します。
    public func set(_ effects: [any PostEffect]) {
        self.effects = effects
    }

    // MARK: - 適用

    /// ソーステクスチャにフルエフェクトチェーンを適用し、最終結果を返します。
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

    /// テクスチャキャッシュを無効化します（キャンバスリサイズ時に呼び出し）。
    func invalidateTextures() {
        textureA = nil
        textureB = nil
        currentWidth = 0
        currentHeight = 0
        context.invalidateTextures()
    }

    /// パイプラインキャッシュを無効化します（シェーダーホットリロード後に呼び出し）。
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
