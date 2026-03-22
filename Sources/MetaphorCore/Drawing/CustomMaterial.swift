import Metal

/// カスタムフラグメントシェーダーを使用する3Dマテリアル。
///
/// `createMaterial()` でインスタンスを作成し、`material()` で適用します。
/// 適用中、Canvas3D の描画は組み込みシェーダーの代わりにカスタムフラグメントシェーダーを使用します。
///
/// ```swift
/// let mat = try createMaterial(
///     source: BuiltinShaders.canvas3DStructs + myFragmentSource,
///     fragmentFunction: "myCustomFragment"
/// )
/// mat.setParameters(MyParams(color: SIMD3(1, 0, 0)))
/// material(mat)
/// box(100)
/// noMaterial()
/// ```
@MainActor
public final class CustomMaterial {
    /// フラグメントシェーダー関数名。
    public let fragmentFunctionName: String

    /// カスタム頂点シェーダー関数名。nil の場合は組み込みシェーダーを使用。
    public let vertexFunctionName: String?

    /// コンパイル済みフラグメント関数。
    private(set) var fragmentFunction: MTLFunction

    /// コンパイル済み頂点関数。nil の場合は組み込みシェーダーを使用。
    private(set) var vertexFunction: MTLFunction?

    /// ShaderLibrary での登録キー。
    let libraryKey: String

    /// カスタムパラメータデータの生バイト列。
    private var parameterData: [UInt8]?

    /// カスタムパラメータを生バイト列として設定します。
    ///
    /// データはシェーダーの `buffer(4)` にバインドされます。
    /// - Parameter value: GPU 構造体レイアウトに一致する任意の型。
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// 格納されたパラメータバイト列を返します。パラメータが未設定の場合は nil。
    var parameters: [UInt8]? { parameterData }

    init(fragmentFunction: MTLFunction, functionName: String, libraryKey: String,
         vertexFunction: MTLFunction? = nil, vertexFunctionName: String? = nil) {
        self.fragmentFunction = fragmentFunction
        self.fragmentFunctionName = functionName
        self.libraryKey = libraryKey
        self.vertexFunction = vertexFunction
        self.vertexFunctionName = vertexFunctionName
    }

    // MARK: - Hot Reload

    /// シェーダーライブラリからシェーダー関数をリロードしてこのマテリアルを更新します。
    ///
    /// 変更されたシェーダーをパイプライン再構築に使用できるよう、
    /// `ShaderLibrary.reload` の後に呼び出してください。
    /// - Parameter shaderLibrary: 更新されたソースを含むシェーダーライブラリ。
    /// - Throws: 関数名が見つからない場合に `MetaphorError.material(.shaderNotFound)` をスロー。
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard let fn = shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunctionName))
        }
        self.fragmentFunction = fn

        if let vtxName = vertexFunctionName {
            guard let vf = shaderLibrary.function(named: vtxName, from: libraryKey) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            self.vertexFunction = vf
        }
    }
}
