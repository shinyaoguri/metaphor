import Metal
import simd

// MARK: - Shape Factory Methods

extension SketchContext {

    /// ``ShapeKind`` からリテインドシェイプを作成します。
    ///
    /// シェイプは現在の fill、stroke、マテリアル状態をキャプチャします。
    /// カスタムシェイプの場合は ``createShape()`` に続けて `beginShape`/`vertex`/`endShape` を使用します。
    ///
    /// ```swift
    /// let box = createShape(.box(width: 1, height: 1, depth: 1))
    /// let circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 100))
    /// let group = createShape(.group)
    /// ```
    ///
    /// - Parameter kind: 作成するシェイプの種類。
    /// - Returns: 新しい ``MShape`` インスタンス。
    public func createShape(_ kind: ShapeKind) -> MShape {
        let style = captureCurrentStyle()
        return MShape(device: renderer.device, kind: kind, style: style)
    }

    /// カスタムジオメトリ定義用の空のリテインドシェイプを作成します。
    ///
    /// 返されたシェイプに `beginShape()`、`vertex()`、`endShape()` を使用して
    /// ジオメトリを定義します。
    ///
    /// ```swift
    /// let star = createShape()
    /// star.beginShape()
    /// star.fill(.yellow)
    /// for i in 0..<10 {
    ///     let angle = Float(i) * Float.pi / 5
    ///     let r: Float = (i % 2 == 0) ? 100 : 40
    ///     star.vertex(cos(angle) * r, sin(angle) * r)
    /// }
    /// star.endShape(.close)
    /// ```
    ///
    /// - Returns: kind が `.path2D` の新しい ``MShape`` インスタンス。
    public func createShape() -> MShape {
        let style = captureCurrentStyle()
        return MShape(device: renderer.device, kind: .path2D, style: style)
    }

    // MARK: - Style Capture

    /// Canvas2D と Canvas3D から現在の描画スタイルをスナップショットします。
    private func captureCurrentStyle() -> ShapeStyle {
        var style = ShapeStyle()
        style.fillColor = canvas.fillColor
        style.strokeColor = canvas.strokeColor
        style.strokeWeight = canvas.currentStrokeWeight
        style.hasFill = canvas.hasFill
        style.hasStroke = canvas.hasStroke
        style.material = canvas3D.currentMaterial
        return style
    }
}
