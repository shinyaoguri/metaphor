import Foundation

/// ポストプロセスエフェクトシェーダー関数名と共有構造体定義。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// 反転、グレースケール、ビネット、色収差、カラーグレーディング、
/// ガウシアンブラー（水平/垂直）、ブルーム抽出、ブルーム合成を含みます。
public enum PostProcessShaders {

    /// カスタムポストプロセスシェーダーが受け取る stage_in と組み込みパラメータの MSL 定義。
    ///
    /// `createPostEffect()` / `createPostEffectFromFile()` は ``postProcessPreamble``
    /// （stdlib + これ）を**必ず**先頭へ足すので、ユーザーのソースでこれらを
    /// 再定義しないでください。
    ///
    /// - `PPVertexOut`: 組み込みのポストプロセス頂点シェーダーの出力。`texCoord` が
    ///   0〜1 の画面座標です。
    /// - `PostProcessParams`: metaphor が `buffer(0)` へ自動供給する組み込みパラメータ
    ///   （`texelSize` と ``CustomPostEffect/intensity`` などのマッピング先）。
    ///
    /// 2D / 3D の前文と同じく `#ifndef` ガードで包んであるので、これを自分で前置した
    /// ソースを渡しても二重定義にはなりません（#718）。
    ///
    /// 中身は組み込みシェーダーと同じ `Shaders/Metal/MetaphorPostProcessTypes.h` からの
    /// 生成物です（#714）。
    public static let commonStructs = BuiltinShadersGenerated.postProcessStructs

    /// カスタムポストエフェクトのソースへ自動で足される前文（stdlib + ``commonStructs``）。
    ///
    /// 2D の ``BuiltinShaders/canvas2DPreamble``・3D の ``BuiltinShaders/canvas3DPreamble``
    /// と対称です。フラグメント関数だけを書けば動きます。
    ///
    /// ```swift
    /// let effect = try createPostEffect(
    ///     name: "myEffect",
    ///     source: """
    ///     fragment float4 myEffect(
    ///         PPVertexOut in [[stage_in]],
    ///         texture2d<float> tex [[texture(0)]],
    ///         constant PostProcessParams &params [[buffer(0)]]
    ///     ) {
    ///         // ...
    ///     }
    ///     """,
    ///     fragmentFunction: "myEffect"
    /// )
    /// ```
    public static let postProcessPreamble = """
    #include <metal_stdlib>
    using namespace metal;

    \(commonStructs)
    """

    /// ポストプロセスシェーダー関数名定数。
    public enum FunctionName {
        /// 反転ポストプロセスシェーダーのMSL関数名。
        public static let postInvert = "metaphor_postInvert"
        /// グレースケールポストプロセスシェーダーのMSL関数名。
        public static let postGrayscale = "metaphor_postGrayscale"
        /// ビネットポストプロセスシェーダーのMSL関数名。
        public static let postVignette = "metaphor_postVignette"
        /// 色収差ポストプロセスシェーダーのMSL関数名。
        public static let postChromaticAberration = "metaphor_postChromaticAberration"
        /// カラーグレーディングポストプロセスシェーダーのMSL関数名。
        public static let postColorGrade = "metaphor_postColorGrade"
        /// 水平ガウシアンブラーポストプロセスシェーダーのMSL関数名。
        public static let postBlurH = "metaphor_postBlurH"
        /// 垂直ガウシアンブラーポストプロセスシェーダーのMSL関数名。
        public static let postBlurV = "metaphor_postBlurV"
        /// ブルーム抽出ポストプロセスシェーダーのMSL関数名。
        public static let postBloomExtract = "metaphor_postBloomExtract"
        /// ブルーム合成ポストプロセスシェーダーのMSL関数名。
        public static let postBloomComposite = "metaphor_postBloomComposite"
    }
}
