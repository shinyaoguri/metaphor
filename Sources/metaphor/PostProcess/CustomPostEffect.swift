import Metal

/// カスタムポストプロセスエフェクト
///
/// ユーザー定義のMSLフラグメントシェーダーでポストプロセスを適用する。
/// `createPostEffect()` で作成し、`addPostEffect(.custom(...))` でチェーンに追加する。
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
public final class CustomPostEffect: @unchecked Sendable {
    /// エフェクト名
    public let name: String

    /// フラグメントシェーダー関数名
    public let fragmentFunctionName: String

    /// ShaderLibraryに登録されたキー
    let libraryKey: String

    /// エフェクトの強さ（PostProcessParams.intensityにマッピング）
    public var intensity: Float = 0

    /// 閾値（PostProcessParams.thresholdにマッピング）
    public var threshold: Float = 0

    /// 半径（PostProcessParams.radiusにマッピング）
    public var radius: Float = 0

    /// 滑らかさ（PostProcessParams.smoothnessにマッピング）
    public var smoothness: Float = 0

    /// カスタムパラメータデータ（buffer(1)にバインドされる）
    private var parameterData: [UInt8] = []

    init(name: String, fragmentFunctionName: String, libraryKey: String) {
        self.name = name
        self.fragmentFunctionName = fragmentFunctionName
        self.libraryKey = libraryKey
    }

    /// カスタムパラメータを設定（buffer(1)として渡される）
    ///
    /// 任意のPOD構造体をシェーダーに渡すために使用する。
    /// ```swift
    /// struct MyParams {
    ///     var amount: Float
    ///     var color: SIMD3<Float>
    /// }
    /// effect.setParameters(MyParams(amount: 0.5, color: SIMD3(1, 0, 0)))
    /// ```
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// カスタムパラメータのバイト配列
    var parameters: [UInt8] { parameterData }

    /// カスタムパラメータが設定されているか
    var hasCustomParameters: Bool { !parameterData.isEmpty }

    // MARK: - Hot Reload

    /// シェーダーライブラリから関数を再取得する
    ///
    /// ShaderLibrary の reload 後に呼ぶことで、
    /// 変更されたシェーダーでポストエフェクトパイプラインが再構築される。
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) != nil else {
            throw PostProcessError.shaderNotFound(fragmentFunctionName)
        }
        // 関数自体は PostProcessPipeline が libraryKey + fragmentFunctionName から都度取得するため、
        // ShaderLibrary の reload で関数キャッシュがクリアされていれば再取得される
    }
}
