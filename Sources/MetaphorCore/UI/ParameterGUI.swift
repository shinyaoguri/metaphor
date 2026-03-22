import simd

/// ランタイムでパラメータを調整するための軽量イミディエートモードGUIを提供します。
///
/// Canvas2D プリミティブを使用してレンダリングします。`draw()` 内で毎フレームウィジェットメソッドを呼び出してください。
/// ```swift
/// var radius: Float = 50
/// var speed: Float = 1.0
/// var show: Bool = true
///
/// func draw() {
///     gui.slider("radius", &radius, min: 10, max: 200)
///     gui.slider("speed", &speed, min: 0.1, max: 5.0)
///     gui.toggle("show", &show)
///     if show {
///         circle(width/2, height/2, radius)
///     }
/// }
/// ```
@MainActor
public final class ParameterGUI {
    // MARK: - Layout Constants

    /// GUIパネルのX位置
    public var x: Float = 10
    /// GUIパネルのY位置
    public var y: Float = 10
    /// 各ウィジェットの幅
    public var widgetWidth: Float = 200
    /// スライダートラックの高さ
    public var sliderHeight: Float = 16
    /// トグルチェックボックスのサイズ
    public var toggleSize: Float = 16
    /// ウィジェット間のスペーシング
    public var padding: Float = 4
    /// ラベルのフォントサイズ
    public var fontSize: Float = 12
    /// パネルの背景色
    public var backgroundColor: Color = Color(r: 0.0, g: 0.0, b: 0.0, a: 0.6)
    /// スライダートラックの色
    public var trackColor: Color = Color(r: 0.3, g: 0.3, b: 0.3, a: 1.0)
    /// スライダーの塗りつぶし色
    public var fillColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// トグル有効時の色
    public var toggleOnColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// ラベルテキストの色
    public var labelColor: Color = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.9)
    /// 値テキストの色
    public var valueColor: Color = Color(r: 0.8, g: 0.8, b: 0.8, a: 0.7)

    /// GUIの表示フラグ
    public var isVisible: Bool = true

    // MARK: - Internal State

    /// 現在ドラッグ中のスライダーID
    private var activeSliderID: String?
    /// 次のウィジェットの累積Y位置
    private var currentY: Float = 0
    /// レイアウト後の計算済みパネル幅
    private var panelWidth: Float = 0
    /// レイアウト後の計算済みパネル高さ
    private var panelHeight: Float = 0

    /// 新しい ParameterGUI インスタンスを作成します。
    public init() {}

    // MARK: - Frame Management

    /// GUIレイアウトの新しいフレームを開始します（`draw()` の先頭で呼び出し）。
    public func begin() {
        currentY = y + padding
        panelWidth = widgetWidth + padding * 2
        panelHeight = 0
    }

    /// 現在のGUIレイアウトフレームを終了します（`draw()` の末尾で呼び出し）。
    /// - Returns: パネルの矩形 (x, y, width, height)。
    @discardableResult
    public func end() -> (Float, Float, Float, Float) {
        panelHeight = currentY - y + padding
        return (x, y, panelWidth, panelHeight)
    }

    // MARK: - Slider

    /// スライダーウィジェットを描画し、バインドされた値を更新します。
    /// - Parameters:
    ///   - label: スライダーの表示ラベル。
    ///   - value: バインドする値（直接変更されます）。
    ///   - minVal: 最小許容値。
    ///   - maxVal: 最大許容値。
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - input: マウス状態を提供する InputManager。
    public func slider(
        _ label: String,
        _ value: inout Float,
        min minVal: Float = 0,
        max maxVal: Float = 1,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }

        let sliderX = x + padding
        let sliderY = currentY
        let labelY = sliderY
        let trackY = labelY + fontSize + 2

        // ラベル＋値テキスト
        drawLabel(label, at: sliderX, y: labelY, canvas: canvas)
        let valStr = String(format: "%.2f", value)
        drawValue(valStr, at: sliderX + widgetWidth, y: labelY, canvas: canvas)

        // トラック背景
        canvas.push()
        canvas.noStroke()
        canvas.fill(trackColor)
        canvas.rect(sliderX, trackY, widgetWidth, sliderHeight)

        // 塗りつぶしバー
        let ratio = (value - minVal) / (maxVal - minVal)
        let fillWidth = widgetWidth * max(0, min(1, ratio))
        canvas.fill(fillColor)
        canvas.rect(sliderX, trackY, fillWidth, sliderHeight)
        canvas.pop()

        // マウスインタラクション
        let mx = input.mouseX
        let my = input.mouseY
        let id = "slider.\(label)"

        if input.isMouseDown {
            if activeSliderID == id ||
               (activeSliderID == nil &&
                mx >= sliderX && mx <= sliderX + widgetWidth &&
                my >= trackY && my <= trackY + sliderHeight) {
                activeSliderID = id
                let t = (mx - sliderX) / widgetWidth
                value = minVal + (maxVal - minVal) * max(0, min(1, t))
            }
        } else {
            if activeSliderID == id {
                activeSliderID = nil
            }
        }

        currentY = trackY + sliderHeight + padding
    }

    // MARK: - Toggle

    /// トグルウィジェットを描画し、バインドされた値を更新します。
    /// - Parameters:
    ///   - label: トグルの表示ラベル。
    ///   - value: バインドする真偽値（直接変更されます）。
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - input: マウス状態を提供する InputManager。
    public func toggle(
        _ label: String,
        _ value: inout Bool,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }

        let toggleX = x + padding
        let toggleY = currentY + 2

        // チェックボックス背景
        canvas.push()
        canvas.noStroke()
        if value {
            canvas.fill(toggleOnColor)
        } else {
            canvas.fill(trackColor)
        }
        canvas.rect(toggleX, toggleY, toggleSize, toggleSize)

        // チェックマーク
        if value {
            canvas.stroke(.white)
            canvas.strokeWeight(2)
            canvas.line(
                toggleX + 3, toggleY + toggleSize / 2,
                toggleX + toggleSize / 2 - 1, toggleY + toggleSize - 4
            )
            canvas.line(
                toggleX + toggleSize / 2 - 1, toggleY + toggleSize - 4,
                toggleX + toggleSize - 3, toggleY + 3
            )
        }
        canvas.pop()

        // ラベル
        drawLabel(label, at: toggleX + toggleSize + 6, y: toggleY, canvas: canvas)

        // クリック検出（マウスダウンのフレームでのみ発火）
        let mx = input.mouseX
        let my = input.mouseY
        if input.isMouseDown && !wasMouseDown {
            if mx >= toggleX && mx <= toggleX + widgetWidth &&
               my >= toggleY && my <= toggleY + toggleSize + 2 {
                value.toggle()
            }
        }

        currentY = toggleY + toggleSize + padding + 2
    }

    // MARK: - Color Picker (Simple)

    /// R/G/B スライダーで構成されるシンプルなカラーピッカーを描画します。
    /// - Parameters:
    ///   - label: カラーピッカーの表示ラベル。
    ///   - value: バインドするカラー値（直接変更されます）。
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - input: マウス状態を提供する InputManager。
    public func colorPicker(
        _ label: String,
        _ value: inout Color,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }

        let pickerX = x + padding
        let labelY = currentY

        drawLabel(label, at: pickerX, y: labelY, canvas: canvas)
        currentY = labelY + fontSize + 2

        // カラープレビュースウォッチ
        canvas.push()
        canvas.noStroke()
        canvas.fill(value)
        canvas.rect(pickerX, currentY, widgetWidth, sliderHeight)
        canvas.pop()
        currentY += sliderHeight + 2

        // R/G/B スライダー
        var simd = value.simd
        let savedFill = fillColor
        fillColor = Color(r: 0.9, g: 0.3, b: 0.3, a: 1.0)
        slider("  R", &simd.x, min: 0, max: 1, canvas: canvas, input: input)
        fillColor = Color(r: 0.3, g: 0.9, b: 0.3, a: 1.0)
        slider("  G", &simd.y, min: 0, max: 1, canvas: canvas, input: input)
        fillColor = Color(r: 0.3, g: 0.3, b: 0.9, a: 1.0)
        slider("  B", &simd.z, min: 0, max: 1, canvas: canvas, input: input)
        fillColor = savedFill

        value = Color(r: simd.x, g: simd.y, b: simd.z, a: simd.w)
    }

    // MARK: - Panel Background

    /// パネル背景を描画します（`begin()` の後、ウィジェットの前に呼び出し）。
    /// - Parameter canvas: 描画に使用する Canvas2D インスタンス。
    public func drawBackground(canvas: Canvas2D) {
        guard isVisible else { return }
        canvas.push()
        canvas.noStroke()
        canvas.fill(backgroundColor)
        canvas.rect(x, y, panelWidth, max(panelHeight, 10))
        canvas.pop()
    }

    // MARK: - Update State

    /// 内部入力トラッキング状態を更新します（各フレームの末尾で呼び出し）。
    /// - Parameter input: 現在のマウス状態を提供する InputManager。
    public func updateInput(input: InputManager) {
        wasMouseDown = input.isMouseDown
    }

    // MARK: - Private

    /// 前フレームでマウスが押されていたかどうか
    private var wasMouseDown: Bool = false

    /// 指定位置に左揃えラベルを描画
    private func drawLabel(_ text: String, at x: Float, y: Float, canvas: Canvas2D) {
        canvas.push()
        canvas.fill(labelColor)
        canvas.noStroke()
        canvas.textSize(fontSize)
        canvas.textAlign(.left, .top)
        canvas.text(text, x, y)
        canvas.pop()
    }

    /// 指定位置に右揃え値文字列を描画
    private func drawValue(_ text: String, at rightX: Float, y: Float, canvas: Canvas2D) {
        canvas.push()
        canvas.fill(valueColor)
        canvas.noStroke()
        canvas.textSize(fontSize)
        canvas.textAlign(.right, .top)
        canvas.text(text, rightX, y)
        canvas.pop()
    }
}
