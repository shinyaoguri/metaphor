import Foundation
import simd

/// `@Param` で宣言されたパラメータを、``ParameterStore`` に束縛したウィジェットとして
/// 描画する API（Parameter Store D2）。
///
/// 人間が触るスライダーと、外部エージェントが書く `.metaphor/params/set-request.json` は
/// どちらも同じ ``ParameterStore`` を叩く**対称なクライアント**です。GUI 側が独自に値を
/// 持たないので、ドラッグした値はそのまま `params.json` に永続化され、次回起動で復元されます。
@MainActor
public extension ParameterGUI {

    // MARK: - 自動パネル

    /// 宣言された全ての `@Param` を、宣言順に自動レイアウトして描画します。
    ///
    /// ```swift
    /// @main final class MySketch: Sketch {
    ///     @Param(min: 10, max: 200) var radius: Float = 50
    ///     @Param var showGrid: Bool = true
    ///
    ///     func draw() {
    ///         gui.params()        // 1 行で全パラメータのパネル
    ///         circle(width / 2, height / 2, radius)
    ///     }
    /// }
    /// ```
    ///
    /// 背景はレイアウトを先に確定してから描くため、**1 フレーム目から正しい高さ**で出ます
    /// （単一フレームのキャプチャでも崩れない）。
    ///
    /// - Returns: パネルの矩形 (x, y, width, height)。パラメータが無い / 非表示のときは高さ 0。
    @discardableResult
    func params() -> (Float, Float, Float, Float) {
        guard let context = boundContext else {
            metaphorDiagnostic(
                "gui.params(): Sketch に接続されていない ParameterGUI では描画できません"
                + "（params(store:canvas:input:) を使ってください）"
            )
            return (x, y, 0, 0)
        }
        return params(store: context.params, canvas: context.canvas, input: context.input)
    }

    /// 描画先とストアを明示して自動パネルを描画します（テスト・自前の GUI インスタンス向け）。
    /// - Parameters:
    ///   - store: 描画対象のパラメータストア。
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - input: マウス状態を提供する InputManager。
    /// - Returns: パネルの矩形 (x, y, width, height)。
    @discardableResult
    func params(
        store: ParameterStore,
        canvas: Canvas2D,
        input: InputManager
    ) -> (Float, Float, Float, Float) {
        guard isVisible else { return (x, y, 0, 0) }

        let rows = store.names.compactMap { name in
            store.descriptor(name).map { (name: name, descriptor: $0) }
        }
        guard !rows.isEmpty else { return (x, y, 0, 0) }

        begin()

        // 先に全高を確定してから背景 → ウィジェットの順に描く。
        let contentHeight = rows.reduce(Float(0)) { $0 + rowHeight(for: $1.descriptor) }
        let totalHeight = contentHeight + padding * 2
        drawPanelBackground(height: totalHeight, canvas: canvas)

        for row in rows {
            let top = currentY
            drawRow(row.name, row.descriptor, store: store, canvas: canvas, input: input)
            // レイアウトは上で確定した表が正典。ウィジェット内部の進み方に依存させない。
            currentY = top + rowHeight(for: row.descriptor)
        }

        panelHeight = currentY - y + padding
        return (x, y, panelWidth, totalHeight)
    }

    // MARK: - 単一パラメータ

    /// 名前で 1 つのパラメータを描画します（型に応じたウィジェットが選ばれます）。
    ///
    /// 自動パネルではなく手でレイアウトを組みたいときに、既存のイミディエイトモード
    /// ウィジェットと混ぜて使えます。
    ///
    /// ```swift
    /// gui.begin()
    /// gui.param("radius")                                    // store 束縛
    /// gui.slider("zoom", &zoom, min: 0.5, max: 4,
    ///            canvas: canvas, input: input)               // 従来どおりの即時モード
    /// gui.end()
    /// ```
    ///
    /// - Parameter name: `@Param` で宣言した名前。未宣言なら何も描かず診断を出します。
    func param(_ name: String) {
        guard let context = boundContext else {
            metaphorDiagnostic(
                "gui.param(\(name)): Sketch に接続されていない ParameterGUI では描画できません"
            )
            return
        }
        param(name, store: context.params, canvas: context.canvas, input: context.input)
    }

    /// 描画先とストアを明示して 1 つのパラメータを描画します。
    /// - Parameters:
    ///   - name: `@Param` で宣言した名前。
    ///   - store: 描画対象のパラメータストア。
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - input: マウス状態を提供する InputManager。
    func param(
        _ name: String,
        store: ParameterStore,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard isVisible else { return }
        guard let descriptor = store.descriptor(name) else {
            metaphorDiagnostic("gui.param(\(name)): 宣言されていないパラメータです")
            return
        }
        let top = currentY
        drawRow(name, descriptor, store: store, canvas: canvas, input: input)
        currentY = top + rowHeight(for: descriptor)
    }

}

// MARK: - 内部実装

@MainActor
extension ParameterGUI {

    /// パラメータ 1 件分の行の高さ。
    ///
    /// 背景の先行描画と各ウィジェットの配置は**この 1 つの表**から決まります
    /// （測り直しと描き方が食い違わないように）。
    func rowHeight(for descriptor: ParamDescriptor) -> Float {
        switch descriptor.type {
        case "bool":
            return toggleSize + padding + 4
        case "color":
            return labelRowHeight + sliderHeight + 2 + sliderRowHeight * 3
        case "vec2":
            return labelRowHeight + sliderRowHeight * 2
        case "vec3":
            return labelRowHeight + sliderRowHeight * 3
        case "string":
            return descriptor.choices == nil
                ? labelRowHeight + padding
                : sliderRowHeight
        default:  // float / int
            return sliderRowHeight
        }
    }

    /// ラベル 1 行分の高さ。
    var labelRowHeight: Float { fontSize + 2 }

    /// スライダー 1 本分（ラベル + トラック + 余白）の高さ。
    var sliderRowHeight: Float { labelRowHeight + sliderHeight + padding }

    /// パネル背景を、確定済みの高さで描画します。
    func drawPanelBackground(height: Float, canvas: Canvas2D) {
        canvas.push()
        canvas.noStroke()
        canvas.fill(backgroundColor)
        canvas.rect(x, y, panelWidth, height)
        canvas.pop()
    }

    /// 型に応じたウィジェットを 1 行描画します。
    func drawRow(
        _ name: String,
        _ descriptor: ParamDescriptor,
        store: ParameterStore,
        canvas: Canvas2D,
        input: InputManager
    ) {
        guard let value = store.value(name) else { return }
        switch value {
        case .float(let v):
            let range = range(for: name, descriptor: descriptor, magnitude: Float(v))
            var f = Float(v)
            slider(
                name, &f, min: range.min, max: range.max,
                canvas: canvas, input: input, valueText: nil
            )
            commit(.float(Double(f)), original: value, name: name, store: store)

        case .int(let v):
            let range = range(for: name, descriptor: descriptor, magnitude: Float(v))
            var f = Float(v)
            slider(
                name, &f, min: range.min, max: range.max,
                canvas: canvas, input: input, valueText: String(Int(f.rounded()))
            )
            commit(.int(Int(f.rounded())), original: value, name: name, store: store)

        case .bool(let v):
            var b = v
            toggle(name, &b, canvas: canvas, input: input)
            commit(.bool(b), original: value, name: name, store: store)

        case .color(let r, let g, let b, let a):
            var color = Color(r: r, g: g, b: b, a: a)
            colorPicker(name, &color, canvas: canvas, input: input)
            commit(
                .color(color.r, color.g, color.b, color.a),
                original: value, name: name, store: store
            )

        case .vec2(let vx, let vy):
            let range = range(
                for: name, descriptor: descriptor,
                magnitude: Swift.max(abs(vx), abs(vy))
            )
            drawLabel(name, at: x + padding, y: currentY, canvas: canvas)
            currentY += labelRowHeight
            var components = SIMD2<Float>(vx, vy)
            slider("  x", &components.x, min: range.min, max: range.max,
                   canvas: canvas, input: input, valueText: nil)
            slider("  y", &components.y, min: range.min, max: range.max,
                   canvas: canvas, input: input, valueText: nil)
            commit(
                .vec2(components.x, components.y),
                original: value, name: name, store: store
            )

        case .vec3(let vx, let vy, let vz):
            let range = range(
                for: name, descriptor: descriptor,
                magnitude: Swift.max(abs(vx), Swift.max(abs(vy), abs(vz)))
            )
            drawLabel(name, at: x + padding, y: currentY, canvas: canvas)
            currentY += labelRowHeight
            var components = SIMD3<Float>(vx, vy, vz)
            slider("  x", &components.x, min: range.min, max: range.max,
                   canvas: canvas, input: input, valueText: nil)
            slider("  y", &components.y, min: range.min, max: range.max,
                   canvas: canvas, input: input, valueText: nil)
            slider("  z", &components.z, min: range.min, max: range.max,
                   canvas: canvas, input: input, valueText: nil)
            commit(
                .vec3(components.x, components.y, components.z),
                original: value, name: name, store: store
            )

        case .string(let s):
            drawChoice(name, current: s, descriptor: descriptor,
                       store: store, canvas: canvas, input: input)
        }
    }

    /// 値が動いていればストア経由で書き戻します（GUI は独自の値を持たない）。
    func commit(
        _ new: ParamValue,
        original: ParamValue,
        name: String,
        store: ParameterStore
    ) {
        guard new != original else { return }
        store.setValue(new, for: name)
    }

    /// `choices` を持つ `string` を、クリックで次の候補へ回るボタンとして描画します。
    ///
    /// `choices` が無い `string` は自由入力ウィジェットが必要になるため、D2 では
    /// 読み取り専用の表示に留めます（外部からの `set-request` では変更できる）。
    func drawChoice(
        _ name: String,
        current: String,
        descriptor: ParamDescriptor,
        store: ParameterStore,
        canvas: Canvas2D,
        input: InputManager
    ) {
        let originX = x + padding
        let labelY = currentY

        drawLabel(name, at: originX, y: labelY, canvas: canvas)
        drawValue(current, at: originX + widgetWidth, y: labelY, canvas: canvas)

        guard let choices = descriptor.choices, !choices.isEmpty else {
            currentY = labelY + labelRowHeight + padding
            return
        }

        let boxY = labelY + labelRowHeight
        currentY = boxY + sliderHeight + padding
        canvas.push()
        canvas.noStroke()
        canvas.fill(trackColor)
        canvas.rect(originX, boxY, widgetWidth, sliderHeight)
        canvas.pop()

        // 現在位置のインジケータ（候補が 1 つでも幅いっぱいにならないよう分割）。
        let index = choices.firstIndex(of: current) ?? 0
        let cellWidth = widgetWidth / Float(choices.count)
        canvas.push()
        canvas.noStroke()
        canvas.fill(fillColor)
        canvas.rect(originX + cellWidth * Float(index), boxY, cellWidth, sliderHeight)
        canvas.pop()

        widgetCounter += 1
        if input.isMouseDown, !wasMouseDown,
           input.mouseX >= originX, input.mouseX <= originX + widgetWidth,
           input.mouseY >= boxY, input.mouseY <= boxY + sliderHeight {
            let next = choices[(index + 1) % choices.count]
            store.setValue(.string(next), for: name)
        }
    }

    /// スライダーのレンジを決めます。
    ///
    /// `@Param(min:max:)` があればそれが正典。無い場合は**初回表示時の値**から
    /// 決めた自動レンジを固定して使います（毎フレーム測り直すとドラッグ中に
    /// レンジが動いてしまうため）。
    func range(
        for name: String,
        descriptor: ParamDescriptor,
        magnitude: Float
    ) -> (min: Float, max: Float) {
        if let lower = descriptor.min, let upper = descriptor.max {
            return (Float(lower), Float(upper))
        }
        if let cached = autoRanges[name] {
            return cached
        }
        let upper = ParameterGUI.niceCeil(Swift.max(abs(magnitude) * 2, 1))
        let resolved: (min: Float, max: Float) = (
            min: Float(descriptor.min ?? Double(magnitude < 0 ? -upper : 0)),
            max: Float(descriptor.max ?? Double(upper))
        )
        autoRanges[name] = resolved
        return resolved
    }

    /// `x` 以上で最小の「1 / 2 / 5 × 10^n」を返します（自動レンジのキリを良くする）。
    static func niceCeil(_ x: Float) -> Float {
        guard x > 0, x.isFinite else { return 1 }
        let exponent = floor(log10(x))
        let base = pow(Float(10), exponent)
        for step in [Float(1), 2, 5] where x <= step * base + base * 1e-6 {
            return step * base
        }
        return 10 * base
    }
}
