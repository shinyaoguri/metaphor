@preconcurrency import Metal
import simd

// MARK: - PostProcessParams

/// ポストプロセスシェーダー用のユニフォームパラメータを格納します。
struct PostProcessParams {
    var texelSize: SIMD2<Float> = .zero
    var intensity: Float = 0
    var threshold: Float = 0
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var temperature: Float = 0
    var radius: Float = 0
    var smoothness: Float = 0
    var _pad0: Float = 0
    var _pad1: Float = 0
}

// MARK: - PostEffect プロトコル

/// レンダリング済みフレームに適用されるポストプロセスエフェクト
///
/// カスタムエフェクトを作成するにはこのプロトコルを実装してください。組み込みエフェクトには
/// ``BloomEffect``、``BlurEffect``、``InvertEffect``、``GrayscaleEffect``、
/// ``VignetteEffect``、``ChromaticAberrationEffect``、``ColorGradeEffect`` があります。
@MainActor
public protocol PostEffect: AnyObject {
    /// このエフェクトの表示名
    var name: String { get }

    /// `input` から読み取り、結果を `output` に書き込んでこのエフェクトを適用します。
    func apply(
        input: MTLTexture, output: MTLTexture,
        commandBuffer: MTLCommandBuffer, context: PostEffectContext
    )
}

// MARK: - 組み込みエフェクト: ブルーム

/// ブルーム（高輝度領域周辺のグロウ）を適用します。
@MainActor
public final class BloomEffect: PostEffect {
    public let name = "bloom"
    public var intensity: Float
    public var threshold: Float

    public init(intensity: Float = 1.0, threshold: Float = 0.8) {
        self.intensity = intensity
        self.threshold = threshold
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        let params = PostProcessParams(texelSize: texelSize, intensity: intensity, threshold: threshold)

        // 1. 明るい領域を抽出: input → output (一時)
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postBloomExtract, params: params
        )
        // 2. Kawase ブラー: output → scratch
        guard let scratch = context.getScratchTexture(width: input.width, height: input.height) else { return }
        context.applyKawaseBlur(commandBuffer: commandBuffer, source: output, output: scratch, iterations: 4)
        // 3. コンポジット: 元画像 + ブルーム → output
        context.renderCompositePass(
            commandBuffer: commandBuffer, original: input, bloom: scratch,
            output: output, params: params
        )
    }
}

// MARK: - 組み込みエフェクト: ブラー

/// ブラーエフェクトを適用します（大きい半径では Kawase、小さい半径ではガウシアン）。
@MainActor
public final class BlurEffect: PostEffect {
    public let name = "blur"
    public var radius: Float

    public init(radius: Float = 5.0) {
        self.radius = radius
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        if radius >= 4 {
            let iterations = max(2, min(Int(log2(radius)), 6))
            context.applyKawaseBlur(commandBuffer: commandBuffer, source: input, output: output, iterations: iterations)
        } else {
            let texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
            let params = PostProcessParams(texelSize: texelSize, radius: radius)
            guard let scratch = context.getScratchTexture(width: input.width, height: input.height) else { return }
            context.renderPass(
                commandBuffer: commandBuffer, input: input, output: scratch,
                fragmentName: PostProcessShaders.FunctionName.postBlurH, params: params
            )
            context.renderPass(
                commandBuffer: commandBuffer, input: scratch, output: output,
                fragmentName: PostProcessShaders.FunctionName.postBlurV, params: params
            )
        }
    }
}

// MARK: - 組み込みエフェクト: シンプルなシングルパス

/// 全カラーを反転します。
@MainActor
public final class InvertEffect: PostEffect {
    public let name = "invert"
    public init() {}

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let params = PostProcessParams(texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)))
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postInvert, params: params
        )
    }
}

/// グレースケールに変換します。
@MainActor
public final class GrayscaleEffect: PostEffect {
    public let name = "grayscale"
    public init() {}

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let params = PostProcessParams(texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)))
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postGrayscale, params: params
        )
    }
}

/// エッジを暗くするビネットエフェクトを適用します。
@MainActor
public final class VignetteEffect: PostEffect {
    public let name = "vignette"
    public var intensity: Float
    public var smoothness: Float

    public init(intensity: Float = 0.5, smoothness: Float = 0.5) {
        self.intensity = intensity
        self.smoothness = smoothness
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let params = PostProcessParams(
            texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)),
            intensity: intensity, smoothness: smoothness
        )
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postVignette, params: params
        )
    }
}

/// 色収差（カラーフリンジ）を適用します。
@MainActor
public final class ChromaticAberrationEffect: PostEffect {
    public let name = "chromaticAberration"
    public var intensity: Float

    public init(intensity: Float = 0.005) {
        self.intensity = intensity
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let params = PostProcessParams(
            texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)),
            intensity: intensity
        )
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postChromaticAberration, params: params
        )
    }
}

/// カラーグレーディング調整を適用します。
@MainActor
public final class ColorGradeEffect: PostEffect {
    public let name = "colorGrade"
    public var brightness: Float
    public var contrast: Float
    public var saturation: Float
    public var temperature: Float

    public init(brightness: Float = 0.0, contrast: Float = 1.0, saturation: Float = 1.0, temperature: Float = 0.0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let params = PostProcessParams(
            texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)),
            brightness: brightness, contrast: contrast,
            saturation: saturation, temperature: temperature
        )
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postColorGrade, params: params
        )
    }
}
