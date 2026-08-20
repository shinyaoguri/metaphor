import Foundation

// MARK: - 2D カスタムシェーダ（#647 / Epic #291 E2）

extension Sketch {
    /// MSL ソースからカスタム 2D フラグメントシェーダを作成します。
    ///
    /// 2D 用の前文（``BuiltinShaders/canvas2DPreamble`` = stdlib + 構造体定義）を
    /// **必ず**先頭へ足すので、フラグメント関数だけを書けば動きます。
    /// `Canvas2DVertexOut` などは自分で定義しないでください。
    ///
    /// ## 返す色は premultiplied alpha
    ///
    /// キャンバスはアルファを掛けた後の色を持ちます（ADR-0012）。`in.color` は掛ける前
    /// （straight）で渡ってくるので、**返す直前に前文の `metaphorPremultiply()` を通します**。
    ///
    /// ```metal
    /// return metaphorPremultiply(float4(rgb, 1.0) * in.color);
    /// ```
    ///
    /// 掛け忘れると半透明で描いた部分が明るく浮きます（不透明しか返さないシェーダでは
    /// 値が変わらないので、アルファを使わないなら気にする必要はありません）。テクスチャを
    /// 読む経路では、テクスチャ側も premultiplied なので `metaphorUnpremultiply()` で
    /// straight へ戻してから色を掛けます。
    ///
    /// - Parameters:
    ///   - source: MSL シェーダソース。
    ///   - fragment: フラグメントシェーダ関数名。
    /// - Returns: ``Shader2D`` インスタンス。
    /// - Throws: ``MetaphorError``。コンパイル失敗は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、関数が見つからない場合は
    ///   ``MetaphorError/material(_:)`` の ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func createShader(source: String, fragment: String) throws -> Shader2D {
        try context.createShader(source: source, fragment: fragment)
    }

    /// 外部 MSL ファイルからカスタム 2D フラグメントシェーダを読み込みます。
    ///
    /// ```swift
    /// let wave = try loadShader("data/wave.metal", fragment: "waveFragment")
    ///
    /// func draw() {
    ///     shader(wave)
    ///     rect(0, 0, width, height)   // 図形が「シェーダを通す面」になる
    ///     resetShader()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: MSL ソースファイルのパス。
    ///   - fragment: フラグメントシェーダ関数名。
    /// - Returns: ``Shader2D`` インスタンス。
    /// - Throws: ``MetaphorError``。読み込み失敗は
    ///   ``MetaphorError/shaderSourceLoadFailed(path:detail:)``、コンパイル失敗は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、関数が見つからない場合は
    ///   ``MetaphorError/material(_:)`` の ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func loadShader(_ path: String, fragment: String) throws -> Shader2D {
        try context.loadShader(path, fragment: fragment)
    }

    /// 以降の 2D 描画にカスタムフラグメントシェーダを適用します。
    /// - Parameter shader: 適用するシェーダ。
    public func shader(_ shader: Shader2D) {
        context.shader(shader)
    }

    /// カスタム 2D シェーダを解除し、組み込みシェーダへ戻します。
    public func resetShader() {
        context.resetShader()
    }
}
