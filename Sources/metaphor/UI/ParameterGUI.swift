import simd

/// Provide a lightweight immediate-mode GUI for adjusting parameters at runtime.
///
/// Renders using Canvas2D primitives. Call widget methods every frame inside `draw()`.
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

    /// The X position of the GUI panel.
    public var x: Float = 10
    /// The Y position of the GUI panel.
    public var y: Float = 10
    /// The width of each widget.
    public var widgetWidth: Float = 200
    /// The height of a slider track.
    public var sliderHeight: Float = 16
    /// The size of a toggle checkbox.
    public var toggleSize: Float = 16
    /// The spacing between widgets.
    public var padding: Float = 4
    /// The font size for labels.
    public var fontSize: Float = 12
    /// The background color of the panel.
    public var backgroundColor: Color = Color(r: 0.0, g: 0.0, b: 0.0, a: 0.6)
    /// The color of the slider track.
    public var trackColor: Color = Color(r: 0.3, g: 0.3, b: 0.3, a: 1.0)
    /// The fill color of the slider.
    public var fillColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// The color of the toggle when enabled.
    public var toggleOnColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1.0)
    /// The color of label text.
    public var labelColor: Color = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.9)
    /// The color of value text.
    public var valueColor: Color = Color(r: 0.8, g: 0.8, b: 0.8, a: 0.7)

    /// Whether the GUI is visible.
    public var isVisible: Bool = true

    // MARK: - Internal State

    /// The ID of the slider currently being dragged.
    private var activeSliderID: String?
    /// The accumulated Y position for the next widget.
    private var currentY: Float = 0
    /// The computed panel width after layout.
    private var panelWidth: Float = 0
    /// The computed panel height after layout.
    private var panelHeight: Float = 0

    /// Create a new ParameterGUI instance.
    public init() {}

    // MARK: - Frame Management

    /// Begin a new frame of GUI layout (call at the start of `draw()`).
    public func begin() {
        currentY = y + padding
        panelWidth = widgetWidth + padding * 2
        panelHeight = 0
    }

    /// End the current frame of GUI layout (call at the end of `draw()`).
    /// - Returns: The panel rectangle as (x, y, width, height).
    @discardableResult
    public func end() -> (Float, Float, Float, Float) {
        panelHeight = currentY - y + padding
        return (x, y, panelWidth, panelHeight)
    }

    // MARK: - Slider

    /// Draw a slider widget and update the bound value.
    /// - Parameters:
    ///   - label: The display label for the slider.
    ///   - value: The value to bind (modified in place).
    ///   - minVal: The minimum allowed value.
    ///   - maxVal: The maximum allowed value.
    ///   - canvas: The Canvas2D instance used for drawing.
    ///   - input: The InputManager providing mouse state.
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

        // Label + value text
        drawLabel(label, at: sliderX, y: labelY, canvas: canvas)
        let valStr = String(format: "%.2f", value)
        drawValue(valStr, at: sliderX + widgetWidth, y: labelY, canvas: canvas)

        // Track background
        canvas.push()
        canvas.noStroke()
        canvas.fill(trackColor)
        canvas.rect(sliderX, trackY, widgetWidth, sliderHeight)

        // Fill bar
        let ratio = (value - minVal) / (maxVal - minVal)
        let fillWidth = widgetWidth * max(0, min(1, ratio))
        canvas.fill(fillColor)
        canvas.rect(sliderX, trackY, fillWidth, sliderHeight)
        canvas.pop()

        // Mouse interaction
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

    /// Draw a toggle widget and update the bound value.
    /// - Parameters:
    ///   - label: The display label for the toggle.
    ///   - value: The boolean value to bind (modified in place).
    ///   - canvas: The Canvas2D instance used for drawing.
    ///   - input: The InputManager providing mouse state.
    public func toggle(
        _ label: String,
        _ value: inout Bool,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }

        let toggleX = x + padding
        let toggleY = currentY + 2

        // Checkbox background
        canvas.push()
        canvas.noStroke()
        if value {
            canvas.fill(toggleOnColor)
        } else {
            canvas.fill(trackColor)
        }
        canvas.rect(toggleX, toggleY, toggleSize, toggleSize)

        // Check mark
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

        // Label
        drawLabel(label, at: toggleX + toggleSize + 6, y: toggleY, canvas: canvas)

        // Click detection (triggers only on the frame mouse goes down)
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

    /// Draw a simple color picker composed of R/G/B sliders.
    /// - Parameters:
    ///   - label: The display label for the color picker.
    ///   - value: The color value to bind (modified in place).
    ///   - canvas: The Canvas2D instance used for drawing.
    ///   - input: The InputManager providing mouse state.
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

        // Color preview swatch
        canvas.push()
        canvas.noStroke()
        canvas.fill(value)
        canvas.rect(pickerX, currentY, widgetWidth, sliderHeight)
        canvas.pop()
        currentY += sliderHeight + 2

        // R/G/B sliders
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

    /// Draw the panel background (call after `begin()` and before any widgets).
    /// - Parameter canvas: The Canvas2D instance used for drawing.
    public func drawBackground(canvas: Canvas2D) {
        guard isVisible else { return }
        canvas.push()
        canvas.noStroke()
        canvas.fill(backgroundColor)
        canvas.rect(x, y, panelWidth, max(panelHeight, 10))
        canvas.pop()
    }

    // MARK: - Update State

    /// Update the internal input tracking state (call at the end of each frame).
    /// - Parameter input: The InputManager providing current mouse state.
    public func updateInput(input: InputManager) {
        wasMouseDown = input.isMouseDown
    }

    // MARK: - Private

    /// Whether the mouse was pressed on the previous frame.
    private var wasMouseDown: Bool = false

    /// Draw a left-aligned label at the given position.
    private func drawLabel(_ text: String, at x: Float, y: Float, canvas: Canvas2D) {
        canvas.push()
        canvas.fill(labelColor)
        canvas.noStroke()
        canvas.textSize(fontSize)
        canvas.textAlign(.left, .top)
        canvas.text(text, x, y)
        canvas.pop()
    }

    /// Draw a right-aligned value string at the given position.
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
