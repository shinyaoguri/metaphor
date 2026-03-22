import Metal

extension SketchContext {

    // MARK: - Post Process

    /// MSL フラグメントシェーダーソースからカスタムポストプロセスエフェクトを作成します。
    ///
    /// シェーダーソースには `PostProcessShaders.commonStructs` をプレフィクスとして含める必要があります。
    /// - Parameters:
    ///   - name: エフェクト名（ライブラリキーとして使用）。
    ///   - source: MSL シェーダーソースコード。
    ///   - fragmentFunction: フラグメントシェーダー関数名。
    /// - Returns: `CustomPostEffect` インスタンス。
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunction)
        }
        return CustomPostEffect(name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
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

    /// 2D スタイル状態のみをスタックに保存します。
    public func pushStyle() {
        canvas.pushStyle()
    }

    /// 2D スタイル状態のみをスタックから復元します。
    public func popStyle() {
        canvas.popStyle()
    }

    /// 2D 平行移動を適用します。
    /// - Parameters:
    ///   - x: 水平方向の移動量。
    ///   - y: 垂直方向の移動量。
    public func translate(_ x: Float, _ y: Float) {
        canvas.translate(x, y)
    }

    /// 2D 回転を適用します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotate(_ angle: Float) {
        canvas.rotate(angle)
    }

    /// 2D スケールを適用します。
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    public func scale(_ sx: Float, _ sy: Float) {
        canvas.scale(sx, sy)
    }

    /// 2D・3D 両方のキャンバスに均一スケールを適用します。
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) {
        canvas.scale(s)
        canvas3D.scale(s, s, s)
    }
}
