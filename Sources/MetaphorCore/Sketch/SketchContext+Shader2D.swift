import Foundation
import Metal

// MARK: - 2D カスタムシェーダ（#647 / Epic #291 E2）

extension SketchContext {
    /// MSL ソースからカスタム 2D フラグメントシェーダを作成します。
    ///
    /// ``BuiltinShaders/canvas2DPreamble``（`#include <metal_stdlib>` +
    /// `using namespace metal;` + 2D 用の構造体定義）を**必ず**先頭へ足すので、
    /// フラグメント関数だけを書けば動きます。`Canvas2DVertexOut` /
    /// `Canvas2DTexVertexOut` / `Canvas2DShaderUniforms` は自分で定義しないでください。
    ///
    /// ```swift
    /// let wave = try createShader(source: """
    /// fragment float4 waveFragment(Canvas2DVertexOut in [[stage_in]],
    ///                              constant Canvas2DShaderUniforms &u [[buffer(3)]]) {
    ///     float2 uv = in.position.xy / u.resolution;
    ///     return float4(uv, sin(u.time) * 0.5 + 0.5, 1.0);
    /// }
    /// """, fragment: "waveFragment")
    /// ```
    ///
    /// - Parameters:
    ///   - source: MSL シェーダソース。
    ///   - fragment: フラグメントシェーダ関数名。
    /// - Returns: ``Shader2D`` インスタンス。
    /// - Throws: ``MetaphorError``。MSL のコンパイルに失敗した場合は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、指定した関数が
    ///   見つからない場合は ``MetaphorError/material(_:)`` の
    ///   ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func createShader(source: String, fragment: String) throws -> Shader2D {
        try makeShader2D(source: Shader2DSource.complete(source), fragment: fragment)
    }

    /// 外部 MSL ファイルからカスタム 2D フラグメントシェーダを読み込みます。
    ///
    /// p5.js の `loadShader()` に名前を合わせていますが、**中身は GLSL ではなく MSL** です。
    /// 移植できるのは「読み込み → 適用 → 図形を描く → 解除」という構造と、
    /// `uv = fragCoord / resolution` の規約までです。
    ///
    /// ```swift
    /// let wave = try loadShader("data/wave.metal", fragment: "waveFragment")
    /// ```
    ///
    /// 読み込んだファイルは**自動で監視対象**になります（#648）。保存するとビルド無しで
    /// 再コンパイルされ、絵がその場で変わります。コンパイルに失敗しても直前の動く
    /// シェーダのまま描き続け、エラーだけがコンソールに出ます。無効化は
    /// ``SketchConfig/shaderHotReload`` か環境変数 `METAPHOR_SHADER_HOT_RELOAD=0`。
    ///
    /// - Parameters:
    ///   - path: MSL ソースファイルのパス。
    ///   - fragment: フラグメントシェーダ関数名。
    /// - Returns: ``Shader2D`` インスタンス。
    /// - Throws: ``MetaphorError``。ソースファイルを読み込めなかった場合は
    ///   ``MetaphorError/shaderSourceLoadFailed(path:detail:)``、コンパイルに失敗した場合は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、指定した関数が
    ///   見つからない場合は ``MetaphorError/material(_:)`` の
    ///   ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func loadShader(_ path: String, fragment: String) throws -> Shader2D {
        let source: String
        do {
            source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw MetaphorError.shaderSourceLoadFailed(
                path: path, detail: error.localizedDescription)
        }
        let shader = try makeShader2D(
            source: Shader2DSource.complete(source), fragment: fragment)
        shaderHotReloader?.register(shader: shader, path: path, fragment: fragment)
        return shader
    }

    /// 以降の 2D 描画にカスタムフラグメントシェーダを適用します。
    ///
    /// 呼ぶたびに保留中のバッチをフラッシュするので、``Shader2D/setParameters(_:)`` の
    /// 直後に呼び直せば図形ごとに違うパラメータを渡せます。
    ///
    /// - Parameter shader: 適用するシェーダ。
    public func shader(_ shader: Shader2D) {
        canvas.shader(shader)
    }

    /// カスタム 2D シェーダを解除し、組み込みシェーダへ戻します。
    public func resetShader() {
        canvas.resetShader()
    }

    // MARK: - 内部

    private func makeShader2D(source: String, fragment: String) throws -> Shader2D {
        let key = "user.shader2D.\(fragment)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragment, from: key) else {
            throw MetaphorError.material(.shaderNotFound(fragment))
        }
        return Shader2D(fragmentFunction: fn, functionName: fragment, libraryKey: key)
    }
}

/// カスタム 2D シェーダのソース整形（#647）。
enum Shader2DSource {
    /// 前文（stdlib + 2D 構造体）を先頭へ足した完全なソースを返します。
    ///
    /// **常に足します。**「ソースに `#include <metal_stdlib>` があれば素通しする」という
    /// 条件付きの規約も試したが、コメントに書いた `#include <metal_stdlib>` にまで
    /// 反応してしまい、ユーザーからは理由の分からないコンパイルエラーになった。
    /// 無条件なら規約は 1 行で言い切れる — **`Canvas2DVertexOut` などを自分で定義しないこと**。
    /// stdlib の再 include と `using namespace metal;` の重複は無害なので、
    /// 完全なソースを貼っても壊れるのは構造体を再定義したときだけ。
    static func complete(_ source: String) -> String {
        BuiltinShaders.canvas2DPreamble + "\n\n" + source
    }
}
