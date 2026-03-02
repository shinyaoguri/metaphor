import Metal

/// カスタムフラグメントシェーダーを使用する3Dマテリアル
///
/// `createMaterial()` で作成し、`material()` で適用する。
/// 適用中はCanvas3Dの描画で組み込みシェーダーの代わりにカスタムフラグメントシェーダーが使用される。
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
    /// フラグメントシェーダー関数名
    public let fragmentFunctionName: String

    /// カスタム頂点シェーダー関数名（nilなら組み込みシェーダーを使用）
    public let vertexFunctionName: String?

    /// コンパイル済みフラグメント関数
    private(set) var fragmentFunction: MTLFunction

    /// コンパイル済み頂点関数（nilなら組み込みを使用）
    private(set) var vertexFunction: MTLFunction?

    /// ShaderLibraryの登録キー
    let libraryKey: String

    /// カスタムパラメータデータ
    private var parameterData: [UInt8]?

    /// カスタムパラメータをバイト列として設定
    ///
    /// シェーダーの `buffer(4)` にバインドされる。
    /// - Parameter value: GPU構造体と一致する任意の型
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// 設定済みのパラメータバイト列（nilならパラメータなし）
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

    /// シェーダーライブラリから関数を再取得してマテリアルを更新する
    ///
    /// ShaderLibrary の reload 後に呼ぶことで、
    /// 変更されたシェーダーをパイプライン再構築に使えるようになる。
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard let fn = shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) else {
            throw CustomMaterialError.shaderNotFound(fragmentFunctionName)
        }
        self.fragmentFunction = fn

        if let vtxName = vertexFunctionName {
            guard let vf = shaderLibrary.function(named: vtxName, from: libraryKey) else {
                throw CustomMaterialError.shaderNotFound(vtxName)
            }
            self.vertexFunction = vf
        }
    }
}

// MARK: - Errors

/// カスタムマテリアル関連のエラー
public enum CustomMaterialError: Error {
    /// 指定した関数名がシェーダーライブラリに見つからない
    case shaderNotFound(String)
}
