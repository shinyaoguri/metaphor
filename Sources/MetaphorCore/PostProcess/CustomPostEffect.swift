import Metal
import simd

/// ユーザー定義の MSL フラグメントシェーダーを使用してカスタムポストプロセスエフェクトを適用します。
///
/// `createPostEffect()` で作成し、`addPostEffect(.custom(...))` でチェーンに追加します。
///
/// ```swift
/// let effect = try createPostEffect(
///     name: "myEffect",
///     source: PostProcessShaders.commonStructs + """
///     fragment float4 myFragment(
///         PPVertexOut in [[stage_in]],
///         texture2d<float> tex [[texture(0)]],
///         constant PostProcessParams &params [[buffer(0)]]
///     ) {
///         constexpr sampler s(filter::linear);
///         float4 color = tex.sample(s, in.texCoord);
///         return float4(1.0 - color.rgb, color.a);
///     }
///     """,
///     fragmentFunction: "myFragment"
/// )
/// effect.intensity = 0.5
/// addPostEffect(.custom(effect))
/// ```
@MainActor
public final class CustomPostEffect: PostEffect {
    /// このエフェクトの名前
    public let name: String

    /// フラグメントシェーダー関数名
    public let fragmentFunctionName: String

    /// ShaderLibrary にシェーダーが登録されているキー
    let libraryKey: String

    /// エフェクト強度。PostProcessParams.intensity にマッピング
    public var intensity: Float = 0

    /// しきい値。PostProcessParams.threshold にマッピング
    public var threshold: Float = 0

    /// 半径値。PostProcessParams.radius にマッピング
    public var radius: Float = 0

    /// 滑らかさ値。PostProcessParams.smoothness にマッピング
    public var smoothness: Float = 0

    /// buffer(1) にバインドされるカスタムパラメータデータの生バイト列
    private var parameterData: [UInt8] = []

    init(name: String, fragmentFunctionName: String, libraryKey: String) {
        self.name = name
        self.fragmentFunctionName = fragmentFunctionName
        self.libraryKey = libraryKey
    }

    /// シェーダーに buffer(1) として渡すカスタムパラメータを設定します。
    ///
    /// 任意の POD 構造体をフラグメントシェーダーに送信するために使用します。
    /// ```swift
    /// struct MyParams {
    ///     var amount: Float
    ///     var color: SIMD3<Float>
    /// }
    /// effect.setParameters(MyParams(amount: 0.5, color: SIMD3(1, 0, 0)))
    /// ```
    ///
    /// - Parameter value: バイト列が GPU バッファにコピーされる POD 構造体
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// カスタムパラメータの生バイト配列を返します。
    var parameters: [UInt8] { parameterData }

    /// カスタムパラメータが設定されているかどうかを示します。
    var hasCustomParameters: Bool { !parameterData.isEmpty }

    // MARK: - PostEffect

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        let params = PostProcessParams(
            texelSize: texelSize,
            intensity: intensity,
            threshold: threshold,
            radius: radius,
            smoothness: smoothness
        )
        context.renderPass(
            commandBuffer: commandBuffer,
            input: input, output: output,
            fragmentName: fragmentFunctionName,
            params: params,
            libraryKey: libraryKey,
            customParams: hasCustomParameters ? parameters : nil
        )
    }

    // MARK: - ホットリロード

    /// ホットリロード後にシェーダーライブラリからシェーダー関数を再取得します。
    ///
    /// `ShaderLibrary.reload()` の後に呼び出して、ポストエフェクトパイプラインが
    /// 更新されたシェーダーで再ビルドされることを保証します。
    ///
    /// - Parameter shaderLibrary: 関数をルックアップするシェーダーライブラリ
    /// - Throws: 関数が見つからない場合 `MetaphorError.shaderNotFound`
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunctionName)
        }
        // 関数自体は PostProcessPipeline が libraryKey + fragmentFunctionName で取得するため、
        // ShaderLibrary.reload() での関数キャッシュクリアにより自動的に再取得されます。
    }
}
