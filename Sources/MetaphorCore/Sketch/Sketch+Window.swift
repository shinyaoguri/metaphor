extension Sketch {
    /// マルチウィンドウ出力用のセカンダリウィンドウを作成します。
    ///
    /// 各ウィンドウは独自のキャンバス、レンダラー、入力処理を持ちます。
    /// ``SketchWindow/draw(_:)`` メソッドにクロージャを渡して描画します。
    ///
    /// ```swift
    /// var preview: SketchWindow?
    ///
    /// func setup() {
    ///     preview = createWindow(SketchWindowConfig(
    ///         width: 400, height: 300, title: "Preview"
    ///     ))
    /// }
    ///
    /// func draw() {
    ///     background(.black)
    ///     fill(.white)
    ///     circle(width / 2, height / 2, 200)
    ///
    ///     preview?.draw { ctx in
    ///         ctx.background(0.2)
    ///         ctx.fill(.red)
    ///         ctx.circle(200, 150, 100)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter config: ウィンドウ設定。
    /// - Returns: 新しい ``SketchWindow``。作成に失敗した場合は `nil`。
    public func createWindow(_ config: SketchWindowConfig = SketchWindowConfig()) -> SketchWindow? {
        context.createWindow(config)
    }

    /// このスケッチから作成されたすべてのセカンダリウィンドウを閉じます。
    public func closeAllWindows() {
        context.closeAllWindows()
    }
}
