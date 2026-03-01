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

    /// コンパイル済みフラグメント関数
    let fragmentFunction: MTLFunction

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

    init(fragmentFunction: MTLFunction, functionName: String, libraryKey: String) {
        self.fragmentFunction = fragmentFunction
        self.fragmentFunctionName = functionName
        self.libraryKey = libraryKey
    }
}

// MARK: - Errors

/// カスタムマテリアル関連のエラー
public enum CustomMaterialError: Error {
    /// 指定した関数名がシェーダーライブラリに見つからない
    case shaderNotFound(String)
}
