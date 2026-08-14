import Metal
import simd

// MARK: - 組み込み uniform

/// カスタム 2D シェーダへ metaphor が自動供給する組み込み uniform（Epic #291 E2）。
///
/// フラグメントシェーダの `buffer(3)` にバインドされます。MSL 側の対応する構造体定義は
/// ``BuiltinShaders/canvas2DStructs`` にあり、レイアウトは一致しています。
///
/// 2D のカラー頂点 `Canvas2D.Vertex2D` は position + color の 24 バイトで **UV を持ちません**。
/// UV は頂点を太らせる代わりに、フラグメント側で `[[position]]`（= 画面ピクセル座標）を
/// ``resolution`` で割って作ります。Shadertoy 系の `fragCoord / iResolution` がそのまま移ります。
public struct Canvas2DShaderUniforms {
    /// キャンバスの寸法（ピクセル）。
    public var resolution: SIMD2<Float>
    /// マウス位置（ピクセル）。
    public var mouse: SIMD2<Float>
    /// スケッチ開始からの経過時間（秒）。
    public var time: Float
    /// これまでに描画されたフレーム数。
    public var frameCount: UInt32
}

/// ``Canvas2DShaderUniforms`` のうち Canvas2D 自身が持たない値。
///
/// Canvas2D は `SketchContext` を直接参照しない（依存方向の維持）ため、
/// `seqProvider` / `hasRecorded3D` と同じく注入フック経由で受け取ります。
struct Canvas2DShaderInputs {
    var time: Float
    var mouse: SIMD2<Float>
    var frameCount: UInt32
}

// MARK: - シェーダ識別子

/// ``Canvas2DPipelineKey`` に載せるカスタムシェーダの識別子（Epic #291 E2）。
///
/// `revision` を含むのは、ホットリロード（#648 / E3）で同じ ``Shader2D`` インスタンスの
/// 中身が差し替わったときにキーも変わり、古いパイプラインを引き当てないようにするためです。
struct Canvas2DShaderID: Hashable, Sendable {
    let object: ObjectIdentifier
    let revision: Int
}

// MARK: - Shader2D

/// 2D 描画に適用するカスタムフラグメントシェーダ（Epic #291 E2）。
///
/// `loadShader()` / `createShader()` で作り、`shader()` で適用し、`resetShader()` で解除します。
/// 3D の ``CustomMaterial`` と同じ構えで、`setParameters()` の生バイト列は
/// フラグメントの `buffer(4)` に届きます。
///
/// ```swift
/// let wave = try loadShader("data/wave.metal", fragment: "waveFragment")
///
/// func draw() {
///     wave.setParameters(WaveParams(amount: 0.3))
///     shader(wave)
///     rect(0, 0, width, height)   // 図形が「シェーダを通す面」になる
///     resetShader()
/// }
/// ```
///
/// **適用範囲**: `rect()` / `circle()` / `line()` などカラー系の描画は、
/// color / instanced / massive のどの経路を通っても同じ stage_in（position + color）なので
/// 1 本の関数がそのまま載ります。`image()` / `text()` のテクスチャ経路も、
/// texCoord を宣言しない関数ならそのまま載ります（テクスチャを無視して描かれます）。
///
/// **制約**: `blendMode(.difference)` / `.exclusion` は組み込みのフレームバッファフェッチ用
/// フラグメントで実装されているためカスタムシェーダと排他です。適用中は通常のアルファブレンドへ
/// フォールバックし、初回だけ警告を出します。
@MainActor
public final class Shader2D {
    /// フラグメントシェーダ関数名。
    public let fragmentFunctionName: String

    /// ``ShaderLibrary`` での登録キー。
    let libraryKey: String

    /// コンパイル済みフラグメント関数。
    private(set) var fragmentFunction: MTLFunction

    /// ``reload(shaderLibrary:)`` のたびに増える世代番号。パイプラインキーの一部になります。
    private(set) var revision: Int = 0

    /// パイプラインキーに載せる識別子。
    var id: Canvas2DShaderID {
        Canvas2DShaderID(object: ObjectIdentifier(self), revision: revision)
    }

    /// カスタムパラメータの生バイト列。
    private var parameterData: [UInt8]?

    /// 格納されたパラメータバイト列。未設定なら nil。
    var parameters: [UInt8]? { parameterData }

    init(fragmentFunction: MTLFunction, functionName: String, libraryKey: String) {
        self.fragmentFunction = fragmentFunction
        self.fragmentFunctionName = functionName
        self.libraryKey = libraryKey
    }

    /// カスタムパラメータを生バイト列として設定します。
    ///
    /// データはフラグメントシェーダの `buffer(4)` にバインドされます。
    ///
    /// 値は**描画バッチが確定した時点**のものが焼き込まれます。図形ごとに違う値を渡したいときは、
    /// `setParameters()` のあとに `shader()` を呼び直してください（`shader()` は呼ぶたびに
    /// 保留中のバッチをフラッシュし、バッチ境界を作ります）。
    ///
    /// - Parameter value: GPU 構造体レイアウトに一致する任意の型。
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    // MARK: - ホットリロード

    /// シェーダライブラリから関数を引き直し、このシェーダを更新します（#648 / E3 の土台）。
    ///
    /// `ShaderLibrary.reload` のあとに呼びます。``revision`` が進むので、
    /// 以降の描画は新しいパイプラインキーで解決されます。
    /// - Parameter shaderLibrary: 更新済みのシェーダライブラリ。
    /// - Throws: 関数名が見つからない場合に ``MetaphorError/material(_:)`` の
    ///   ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard let fn = shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunctionName))
        }
        self.fragmentFunction = fn
        self.revision += 1
    }
}
