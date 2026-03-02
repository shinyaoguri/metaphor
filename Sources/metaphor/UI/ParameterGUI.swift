import simd

/// ランタイムでパラメータを調整できる軽量即時モード GUI
///
/// Canvas2D のプリミティブで描画される。`draw()` 内で毎フレーム呼び出す。
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

    /// GUI の X 位置
    public var x: Float = 10
    /// GUI の Y 位置
    public var y: Float = 10
    /// ウィジェットの幅
    public var widgetWidth: Float = 200
    /// スライダーの高さ
    public var sliderHeight: Float = 16
    /// トグルのサイズ
    public var toggleSize: Float = 16
    /// ウィジェット間の余白
    public var padding: Float = 4
    /// ラベルのフォントサイズ
    public var fontSize: Float = 12
    /// パネル背景色
    public var backgroundColor: Color = Color(r: 0.0, g: 0.0, b: 0.0, a: 0.6)
    /// スライダートラック色
    public var trackColor: Color = Color(r: 0.3, g: 0.3, b: 0.3, a: 1.0)
    /// スライダーフィル色
    public var fillColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// トグルオン色
    public var toggleOnColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// ラベル色
    public var labelColor: Color = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.9)
    /// 値テキスト色
    public var valueColor: Color = Color(r: 0.8, g: 0.8, b: 0.8, a: 0.7)

    /// GUI が表示されているか
    public var isVisible: Bool = true

    // MARK: - Internal State

    /// 現在ドラッグ中のスライダー ID
    private var activeSliderID: String?
    /// 前フレームまでの累積 Y 位置（次のウィジェットの描画位置）
    private var currentY: Float = 0
    /// パネルの最大幅（描画後に確定）
    private var panelWidth: Float = 0
    /// パネルの最大高さ
    private var panelHeight: Float = 0

    public init() {}

    // MARK: - Frame Management

    /// フレーム開始（draw() の最初に自動的に呼ばれる）
    public func begin() {
        currentY = y + padding
        panelWidth = widgetWidth + padding * 2
        panelHeight = 0
    }

    /// フレーム終了（draw() の最後に自動的に呼ばれる）
    /// - Returns: パネルの矩形 (x, y, w, h)
    @discardableResult
    public func end() -> (Float, Float, Float, Float) {
        panelHeight = currentY - y + padding
        return (x, y, panelWidth, panelHeight)
    }

    // MARK: - Slider

    /// スライダーウィジェットを描画し、値を更新する
    /// - Parameters:
    ///   - label: ラベル
    ///   - value: バインドする値
    ///   - min: 最小値
    ///   - max: 最大値
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

        // ラベル + 値
        drawLabel(label, at: sliderX, y: labelY, canvas: canvas)
        let valStr = String(format: "%.2f", value)
        drawValue(valStr, at: sliderX + widgetWidth, y: labelY, canvas: canvas)

        // トラック背景
        canvas.push()
        canvas.noStroke()
        canvas.fill(trackColor)
        canvas.rect(sliderX, trackY, widgetWidth, sliderHeight)

        // フィル
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

    /// トグルウィジェットを描画し、値を更新する
    /// - Parameters:
    ///   - label: ラベル
    ///   - value: バインドする値
    public func toggle(
        _ label: String,
        _ value: inout Bool,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }

        let toggleX = x + padding
        let toggleY = currentY + 2

        // チェックボックス
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

        // クリック判定（マウスダウンの瞬間のみ）
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

    /// 簡易カラーピッカー（R/G/B スライダー）
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

        // 色プレビュー
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

    /// パネル背景を描画（begin() の後、ウィジェットの前に呼ぶ）
    public func drawBackground(canvas: Canvas2D) {
        guard isVisible else { return }
        canvas.push()
        canvas.noStroke()
        canvas.fill(backgroundColor)
        canvas.rect(x, y, panelWidth, max(panelHeight, 10))
        canvas.pop()
    }

    // MARK: - Update State

    /// 入力状態を更新（フレーム末尾で呼ぶ）
    public func updateInput(input: InputManager) {
        wasMouseDown = input.isMouseDown
    }

    // MARK: - Private

    private var wasMouseDown: Bool = false

    private func drawLabel(_ text: String, at x: Float, y: Float, canvas: Canvas2D) {
        canvas.push()
        canvas.fill(labelColor)
        canvas.noStroke()
        canvas.textSize(fontSize)
        canvas.textAlign(.left, .top)
        canvas.text(text, x, y)
        canvas.pop()
    }

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
