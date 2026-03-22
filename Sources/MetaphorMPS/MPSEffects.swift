@preconcurrency import Metal
import MetalPerformanceShaders
import MetaphorCore

// MARK: - MPS ポストエフェクトクラス

/// MPS ハードウェア最適化ガウシアンブラーを適用します。
@MainActor
public final class MPSBlurEffect: PostEffect {
    public let name = "mpsBlur"
    public var sigma: Float
    private var filter: MPSImageFilterWrapper?

    public init(sigma: Float) {
        self.sigma = sigma
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let f = filter ?? {
            let w = MPSImageFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            filter = w
            return w
        }()
        f.encodeGaussianBlur(
            commandBuffer: commandBuffer, source: input, destination: output, sigma: sigma
        )
    }
}

/// MPS Sobel エッジ検出を適用します。
@MainActor
public final class MPSSobelEffect: PostEffect {
    public let name = "mpsSobel"
    private var filter: MPSImageFilterWrapper?

    public init() {}

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let f = filter ?? {
            let w = MPSImageFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            filter = w
            return w
        }()
        f.encodeSobel(
            commandBuffer: commandBuffer, source: input, destination: output
        )
    }
}

/// MPS モルフォロジー収縮を適用します。
@MainActor
public final class MPSErodeEffect: PostEffect {
    public let name = "mpsErode"
    public var radius: Int
    private var filter: MPSImageFilterWrapper?

    public init(radius: Int = 1) {
        self.radius = radius
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let f = filter ?? {
            let w = MPSImageFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            filter = w
            return w
        }()
        f.encodeErode(
            commandBuffer: commandBuffer, source: input, destination: output, radius: radius
        )
    }
}

/// MPS モルフォロジー膨張を適用します。
@MainActor
public final class MPSDilateEffect: PostEffect {
    public let name = "mpsDilate"
    public var radius: Int
    private var filter: MPSImageFilterWrapper?

    public init(radius: Int = 1) {
        self.radius = radius
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let f = filter ?? {
            let w = MPSImageFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            filter = w
            return w
        }()
        f.encodeDilate(
            commandBuffer: commandBuffer, source: input, destination: output, radius: radius
        )
    }
}
