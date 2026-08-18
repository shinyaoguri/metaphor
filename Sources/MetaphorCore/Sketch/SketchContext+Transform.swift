import Metal

extension SketchContext {

    // MARK: - Post Process

    /// MSL フラグメントシェーダーソースからカスタムポストプロセスエフェクトを作成します。
    ///
    /// 前文（stdlib + `PPVertexOut` / `PostProcessParams`）は**自動で足されます**（#718）。
    /// ソースに書くのはフラグメント関数だけで、``PostProcessShaders/commonStructs`` が
    /// 配る型を自分で定義しないでください。
    ///
    /// - Parameters:
    ///   - name: エフェクト名（ライブラリキーとして使用）。
    ///   - source: MSL シェーダーソースコード。
    ///   - fragmentFunction: フラグメントシェーダー関数名。
    /// - Returns: `CustomPostEffect` インスタンス。
    /// - Throws: ``MetaphorError``。MSL のコンパイルに失敗した場合は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、指定した
    ///   フラグメント関数が見つからない場合は ``MetaphorError/shaderNotFound(_:)``。
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        try renderer.shaderLibrary.register(source: PostEffectSource.complete(source), as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunction)
        }
        return CustomPostEffect(name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
    }

    /// 外部 MSL ファイルからカスタムポストプロセスエフェクトを作成します。
    ///
    /// 読み込んだファイルは**自動で監視対象**になります（#648）。保存するとビルド無しで
    /// 再コンパイルされ、絵がその場で変わります。コンパイルに失敗しても直前の動く
    /// シェーダのまま描き続け、エラーだけがコンソールに出ます。無効化は
    /// ``SketchConfig/shaderHotReload`` か環境変数 `METAPHOR_SHADER_HOT_RELOAD=0`。
    ///
    /// ソース経路（``createPostEffect(name:source:fragmentFunction:)``）と同じく、前文は
    /// **自動で足されます**（#718）。ファイルに書くのはフラグメント関数だけです。
    ///
    /// - Parameters:
    ///   - name: エフェクト名（ライブラリキーとして使用）。
    ///   - path: MSL ソースファイルのパス。
    ///   - fragmentFunction: フラグメントシェーダー関数名。
    /// - Returns: `CustomPostEffect` インスタンス。
    /// - Throws: ``MetaphorError``。ソースファイルを読み込めなかった場合は
    ///   ``MetaphorError/shaderSourceLoadFailed(path:detail:)``、MSL のコンパイルに失敗した
    ///   場合は ``MetaphorError/shaderCompilationFailed(name:underlying:)``、指定した
    ///   フラグメント関数が見つからない場合は ``MetaphorError/shaderNotFound(_:)``。
    public func createPostEffectFromFile(
        name: String, path: String, fragmentFunction: String
    ) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        // `registerFromFile` ではなく自分で読むのは、前文を足してから登録するため
        // （2D の `loadShader` / 3D の `createMaterialFromFile` と同じ形）。
        let source: String
        do {
            source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw MetaphorError.shaderSourceLoadFailed(
                path: path, detail: error.localizedDescription)
        }
        try renderer.shaderLibrary.register(source: PostEffectSource.complete(source), as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunction)
        }
        let effect = CustomPostEffect(
            name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
        shaderHotReloader?.register(
            postEffect: effect, path: path, fragment: fragmentFunction)
        return effect
    }

    /// ポストプロセスエフェクトをパイプラインに追加します。
    /// - Parameter effect: 追加するポストプロセスエフェクト。
    public func addPostEffect(_ effect: any PostEffect) {
        renderer.addPostEffect(effect)
    }

    /// 指定インデックスのポストプロセスエフェクトを削除します。
    /// - Parameter index: 削除するエフェクトのインデックス。
    public func removePostEffect(at index: Int) {
        renderer.removePostEffect(at: index)
    }

    /// パイプラインからすべてのポストプロセスエフェクトを削除します。
    public func clearPostEffects() {
        renderer.clearPostEffects()
    }

    /// すべてのポストプロセスエフェクトを指定した配列で置き換えます。
    /// - Parameter effects: 新しいポストプロセスエフェクトの配列。
    public func setPostEffects(_ effects: [any PostEffect]) {
        renderer.setPostEffects(effects)
    }

    // MARK: - Unified Transform Stack

    /// 2D・3D 両方の変換とスタイル状態をスタックに保存します。
    public func push() {
        canvas.push()
        canvas3D.pushState()
    }

    /// 2D・3D 両方の変換とスタイル状態をスタックから復元します。
    public func pop() {
        canvas.pop()
        canvas3D.popState()
    }

    /// 2D・3D 両方のスタイル状態（変換を除く）をスタックに保存します。
    ///
    /// fill()/stroke() 等は 2D・3D 両方へ書き込むため、片方だけ保存すると
    /// push/pop をまたいで 2D と 3D のスタイルが黙って乖離する。
    public func pushStyle() {
        canvas.pushStyle()
        canvas3D.pushStyle()
    }

    /// 2D・3D 両方のスタイル状態（変換を除く）をスタックから復元します。
    public func popStyle() {
        canvas.popStyle()
        canvas3D.popStyle()
    }

    /// 平行移動を適用します（2D・3D 両方）。
    ///
    /// 3D 側は z = 0 の平行移動として適用されます（Processing P3D 互換）。
    /// - Parameters:
    ///   - x: 水平方向の移動量。
    ///   - y: 垂直方向の移動量。
    public func translate(_ x: Float, _ y: Float) {
        canvas.translate(x, y)
        canvas3D.translate(x, y, 0)
    }

    /// 回転を適用します（2D・3D 両方）。
    ///
    /// 3D 側は z 軸まわりの回転として適用されます（Processing P3D 互換）。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotate(_ angle: Float) {
        canvas.rotate(angle)
        canvas3D.rotateZ(angle)
    }

    /// 非均一スケールを適用します（2D・3D 両方）。
    ///
    /// 3D 側は z 軸を等倍（1）としたスケールになります（Processing P3D 互換）。
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    public func scale(_ sx: Float, _ sy: Float) {
        canvas.scale(sx, sy)
        canvas3D.scale(sx, sy, 1)
    }

    /// 2D・3D 両方のキャンバスに均一スケールを適用します。
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) {
        canvas.scale(s)
        canvas3D.scale(s, s, s)
    }

    /// 2D 変換に 3x3 行列を乗算します。
    /// - Parameter matrix: 連結する行列。
    public func applyMatrix(_ matrix: float3x3) {
        canvas.applyMatrix(matrix)
    }

    /// 2D 変換に Processing 形式の 6 成分アフィン行列を乗算します。
    public func applyMatrix(
        _ n00: Float, _ n01: Float, _ n02: Float,
        _ n10: Float, _ n11: Float, _ n12: Float
    ) {
        canvas.applyMatrix(n00, n01, n02, n10, n11, n12)
    }

    /// 3D 変換に 4x4 行列を乗算します。
    /// - Parameter matrix: 連結する行列。
    public func applyMatrix(_ matrix: float4x4) {
        canvas3D.applyMatrix(matrix)
    }

    /// 2D・3D 両方の変換行列を単位行列にリセットします。
    public func resetMatrix() {
        canvas.resetMatrix()
        canvas3D.resetMatrix()
    }

    /// 2D 変換に x 軸方向のせん断を適用します。
    /// - Parameter angle: ラジアン単位のせん断角度。
    public func shearX(_ angle: Float) {
        canvas.shearX(angle)
    }

    /// 2D 変換に y 軸方向のせん断を適用します。
    /// - Parameter angle: ラジアン単位のせん断角度。
    public func shearY(_ angle: Float) {
        canvas.shearY(angle)
    }

    /// 2D モデル座標のスクリーン座標を返します。
    public func screenPosition(_ x: Float, _ y: Float) -> SIMD2<Float> {
        canvas.screenPosition(x, y)
    }

    /// 3D モデル座標を現在のモデル変換だけで写したワールド座標を返します。
    ///
    /// カメラと投影は通しません（``camera(eye:center:up:)`` を動かしても変わりません）。
    public func modelPosition(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        canvas3D.modelPosition(x, y, z)
    }

    /// 3D モデル座標のスクリーン座標を返します。
    ///
    /// カメラ背後の点では x/y が原点対称に反転し z が 0...1 を外れます。
    /// ``isInFront(_:_:_:)`` で判別してください。
    public func screenPosition(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        canvas3D.screenPosition(x, y, z)
    }

    /// 3D モデル座標の点がカメラ平面より前にあるかを返します。
    public func isInFront(_ x: Float, _ y: Float, _ z: Float) -> Bool {
        canvas3D.isInFront(x, y, z)
    }
}

// MARK: - カスタムポストエフェクトのソース組み立て (#718)

/// カスタムポストエフェクトのソースへ前文を足す。
enum PostEffectSource {
    /// 前文（stdlib + `PPVertexOut` / `PostProcessParams`）を先頭へ足した完全な
    /// ソースを返します。
    ///
    /// **常に足します。**2D（``Shader2DSource/complete(_:)``）・3D
    /// （``Shader3DSource/complete(_:)``）と同じ判断で、「ソースに前文があれば
    /// 素通しする」という条件付きの規約は採りません。postFX は前文を自分で前置する
    /// 作法（`PostProcessShaders.commonStructs + ...`）が長く案内されていたので、
    /// 二重に前置されるケースが必ず出ますが、前文そのものが `#ifndef` ガードを
    /// 持つため 2 回目は空になります（``PostProcessShaders/postProcessPreamble``）。
    static func complete(_ source: String) -> String {
        PostProcessShaders.postProcessPreamble + "\n\n" + source
    }
}
