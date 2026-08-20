import Foundation

/// 組み込みMetalシェーダー関数名と共有構造体定義。
///
/// metaphor はデュアルシェーダーシステムを使用します:
/// - **`.metal` ファイル** (`Shaders/Metal/` 内): **正典**。Xcode ビルドではプリコンパイル
///   （default.metallib）として使われる。
/// - **`.txt` リソースファイル** (`Shaders/ShaderSources/` 内): `.metal` からの**生成物**
///   （`scripts/generate-shader-sources.py` がローカル include をインライン展開して生成）。
///   `MTLDevice.makeLibrary(source:)` によるランタイムコンパイル（SwiftPM ビルドの既定経路）
///   と開発時のシェーダーホットリロードに使用される。**手で編集しないこと。**
///
/// 新しいシェーダーは `Shaders/Metal/` 配下に `.metal` ファイルとして追加し、
/// `python3 scripts/generate-shader-sources.py` で `.txt` を再生成してください
/// （陳腐化は pre-push フックと CI が検出します）。
///
/// カスタムシェーダー向けの前文（``canvas2DStructs`` / ``canvas3DStructs`` /
/// ``canvas3DLightingFn`` / ``PostProcessShaders/commonStructs``）も同じスクリプトが
/// `.h` から生成します（実体は `BuiltinShaders+Generated.swift`）。
public enum BuiltinShaders {

    // MARK: - Canvas2D カスタムシェーダ用の構造体 (#647 / Epic #291 E2)

    /// カスタム 2D フラグメントシェーダが受け取る stage_in と uniform の MSL 定義。
    ///
    /// `loadShader()` / `createShader()` は ``canvas2DPreamble``（stdlib + これ）を
    /// **必ず**先頭へ足すので、ユーザーのソースでこれらを再定義しないでください。
    ///
    /// - `Canvas2DVertexOut`: `rect()` / `circle()` / `line()` などカラー系の stage_in。
    ///   color / instanced / massive のどの経路でも同じ型です。
    /// - `Canvas2DTexVertexOut`: `image()` / `text()` のテクスチャ系の stage_in。
    /// - `Canvas2DShaderUniforms`: metaphor が `buffer(3)` へ自動供給する組み込み uniform。
    /// - `Canvas2DVertexIn` / `Canvas2DTexVertexIn`: 組み込み頂点シェーダーの入力
    ///   （頂点は差し替えられないので、通常は読むだけです）。
    ///
    /// 2D のカラー頂点は UV を持たないので、uv はフラグメントの `[[position]]`（画面ピクセル座標）を
    /// `resolution` で割って作ります（Shadertoy の `fragCoord / iResolution` と同じ形）。
    ///
    /// 3D の前文と同じく `#ifndef` ガードで包んであるので、これを自分で前置したソースを
    /// 渡しても二重定義にはなりません（#713）。
    ///
    /// 中身は組み込みシェーダーと同じ `Shaders/Metal/MetaphorCanvas2DTypes.h` からの
    /// 生成物です（#714）。
    public static let canvas2DStructs = BuiltinShadersGenerated.canvas2DStructs

    /// カスタム 2D シェーダのソースへ自動で足される前文（stdlib + ``canvas2DStructs``）。
    public static let canvas2DPreamble = """
    #include <metal_stdlib>
    using namespace metal;

    \(canvas2DStructs)
    """

    // MARK: - Canvas3D 共有構造体 (共通3Dシェーダー定義)

    /// Canvas3D の非テクスチャおよびテクスチャシェーダーで共有されるMSL構造体定義。
    ///
    /// `createMaterial()` / `createMaterialFromFile()` は ``canvas3DPreamble``（stdlib +
    /// これ + ``canvas3DLightingFn``）を**必ず**先頭へ足すので、通常は自分で前置する
    /// 必要はありません。`Canvas3DUniforms` / `Light3D` / `Material3D` /
    /// `ShadowFragmentUniforms` と、stage_in の `Canvas3DVertexOut` /
    /// `Canvas3DTexVertexOut`（+ 頂点入力の 2 型）が入っています。
    ///
    /// 前置しても壊れません（`#ifndef` ガードで包んであるため）。以前の作法で書かれた
    /// ソースはそのまま動きます（#713）。
    ///
    /// 中身は組み込みシェーダーと同じ `Shaders/Metal/MetaphorCanvas3DTypes.h` からの
    /// 生成物です（#707）。
    public static let canvas3DStructs = BuiltinShadersGenerated.canvas3DStructs

    /// MSLライティング関数 (Blinn-Phong + PBR Cook-Torrance GGX)。
    ///
    /// ``canvas3DPreamble`` の一部として自動で足されるので、カスタムマテリアルの中では
    /// `calculateLighting()` などをそのまま呼べます。単体で前置するときは構造体を
    /// 参照するので ``canvas3DStructs`` と**セットで**使ってください。
    ///
    /// 中身は組み込みシェーダーと同じ `Shaders/Metal/MetaphorLighting.h` からの生成物
    /// です（#707）。ライティングの実装を直せば、ここで配られる前文も一緒に動きます。
    public static let canvas3DLightingFn = BuiltinShadersGenerated.canvas3DLightingFn

    /// カスタムマテリアルシェーダのソースへ自動で足される前文
    /// （stdlib + ``canvas3DStructs`` + ``canvas3DLightingFn``）。
    ///
    /// 2D の ``canvas2DPreamble`` と対称です。フラグメント関数だけを書けば動きます。
    public static let canvas3DPreamble = """
    #include <metal_stdlib>
    using namespace metal;

    \(canvas3DStructs)

    \(canvas3DLightingFn)
    """

    // MARK: - シェーダー関数名

    /// 組み込みシェーダー関数名定数。
    public enum FunctionName {
        /// ブリット頂点シェーダーのMSL関数名。
        public static let blitVertex = "metaphor_blitVertex"
        /// ブリットフラグメントシェーダーのMSL関数名。
        public static let blitFragment = "metaphor_blitFragment"
        /// フラットカラー頂点シェーダーのMSL関数名。
        public static let flatColorVertex = "metaphor_flatColorVertex"
        /// フラットカラーフラグメントシェーダーのMSL関数名。
        public static let flatColorFragment = "metaphor_flatColorFragment"
        /// 頂点カラー頂点シェーダーのMSL関数名。
        public static let vertexColorVertex = "metaphor_vertexColorVertex"
        /// 頂点カラーフラグメントシェーダーのMSL関数名。
        public static let vertexColorFragment = "metaphor_vertexColorFragment"
        /// ライティング付き頂点シェーダーのMSL関数名。
        public static let litVertex = "metaphor_litVertex"
        /// ライティング付きフラグメントシェーダーのMSL関数名。
        public static let litFragment = "metaphor_litFragment"
        /// Canvas2D 頂点シェーダーのMSL関数名。
        public static let canvas2DVertex = "metaphor_canvas2DVertex"
        /// Canvas2D フラグメントシェーダーのMSL関数名。
        public static let canvas2DFragment = "metaphor_canvas2DFragment"
        /// Canvas2D 差分ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DDifferenceFragment = "metaphor_canvas2DDifferenceFragment"
        /// Canvas2D 除外ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DExclusionFragment = "metaphor_canvas2DExclusionFragment"
        /// Canvas3D 頂点シェーダーのMSL関数名。
        public static let canvas3DVertex = "metaphor_canvas3DVertex"
        /// Canvas3D フラグメントシェーダーのMSL関数名。
        public static let canvas3DFragment = "metaphor_canvas3DFragment"
        /// Canvas3D ワイヤーフレーム（stroke）頂点シェーダーのMSL関数名。
        public static let canvas3DWireVertex = "metaphor_canvas3DWireVertex"
        /// Canvas2D テクスチャ付き頂点シェーダーのMSL関数名。
        public static let canvas2DTexturedVertex = "metaphor_canvas2DTexturedVertex"
        /// Canvas2D テクスチャ付きフラグメントシェーダーのMSL関数名。
        public static let canvas2DTexturedFragment = "metaphor_canvas2DTexturedFragment"
        /// Canvas2D straight alpha テクスチャ用フラグメントシェーダーのMSL関数名。
        ///
        /// `updatePixels()` のように**テクスチャが既に straight**な経路で使います
        /// （既定の ``canvas2DTexturedFragment`` は premultiplied を前提に割り戻す。
        /// ADR-0012 / #848）。
        public static let canvas2DStraightTexturedFragment =
            "metaphor_canvas2DStraightTexturedFragment"
        /// Canvas2D テクスチャ付き差分ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DTexturedDifferenceFragment = "metaphor_canvas2DTexturedDifferenceFragment"
        /// Canvas2D テクスチャ付き除外ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DTexturedExclusionFragment = "metaphor_canvas2DTexturedExclusionFragment"
        /// Canvas3D テクスチャ付き頂点シェーダーのMSL関数名。
        public static let canvas3DTexturedVertex = "metaphor_canvas3DTexturedVertex"
        /// Canvas3D テクスチャ付きフラグメントシェーダーのMSL関数名。
        public static let canvas3DTexturedFragment = "metaphor_canvas3DTexturedFragment"
        /// Canvas2D インスタンス描画頂点シェーダーのMSL関数名。
        public static let canvas2DInstancedVertex = "metaphor_canvas2DInstancedVertex"
        /// Canvas2D インスタンス描画フラグメントシェーダーのMSL関数名。
        public static let canvas2DInstancedFragment = "metaphor_canvas2DInstancedFragment"
        /// Canvas2D インスタンス描画差分ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DInstancedDifferenceFragment = "metaphor_canvas2DInstancedDifferenceFragment"
        /// Canvas2D インスタンス描画除外ブレンドフラグメントシェーダーのMSL関数名。
        public static let canvas2DInstancedExclusionFragment = "metaphor_canvas2DInstancedExclusionFragment"
    }
}
