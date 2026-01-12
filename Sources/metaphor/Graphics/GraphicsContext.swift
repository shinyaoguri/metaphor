import Metal
import simd

/// Processing風の描画コンテキスト
/// MTLRenderCommandEncoderをラップし、高レベルな描画APIを提供する
public final class Graphics {
    // MARK: - Internal Metal Resources

    internal let encoder: MTLRenderCommandEncoder
    internal let device: MTLDevice
    private let batchRenderer: BatchRenderer

    // MARK: - State Management

    private var stateStack: [RenderState] = []
    private var currentState: RenderState

    // MARK: - Shape Building State

    private var shapeVertices: [SIMD2<Float>] = []
    private var shapeKind: ShapeKind = .polygon
    private var isBuilding: Bool = false

    // MARK: - Graphics Properties (Processing互換)

    /// キャンバスの幅
    public let width: Float

    /// キャンバスの高さ
    public let height: Float

    /// フレームカウント
    public var frameCount: UInt64 = 0

    // MARK: - Input State (Processing互換)

    /// 入力状態のスナップショット
    private let input: InputSnapshot

    /// 現在のマウスX座標
    public var mouseX: Float { input.mouseX }

    /// 現在のマウスY座標
    public var mouseY: Float { input.mouseY }

    /// 前フレームのマウスX座標
    public var pmouseX: Float { input.pmouseX }

    /// 前フレームのマウスY座標
    public var pmouseY: Float { input.pmouseY }

    /// マウスボタンが押されているか
    public var mousePressed: Bool { input.isMousePressed }

    /// 押されているマウスボタン
    public var mouseButton: MouseButton { input.mouseButton }

    /// キーが押されているか
    public var keyPressed: Bool { input.isKeyPressed }

    /// 最後に押されたキー
    public var key: Character { input.key }

    /// 最後に押されたキーコード
    public var keyCode: UInt16 { input.keyCode }

    // MARK: - Initialization

    /// Graphicsを初期化
    /// - Parameters:
    ///   - encoder: Metalレンダーコマンドエンコーダー
    ///   - device: Metalデバイス
    ///   - pipelines: パイプラインキャッシュ
    ///   - width: キャンバス幅
    ///   - height: キャンバス高さ
    ///   - frameCount: 現在のフレーム番号
    ///   - input: 入力状態のスナップショット
    internal init(
        encoder: MTLRenderCommandEncoder,
        device: MTLDevice,
        pipelines: PipelineCache,
        width: Int,
        height: Int,
        frameCount: UInt64 = 0,
        input: InputSnapshot = .empty
    ) {
        self.encoder = encoder
        self.device = device
        self.width = Float(width)
        self.height = Float(height)
        self.frameCount = frameCount
        self.input = input
        self.currentState = .default
        self.batchRenderer = BatchRenderer(device: device, pipelines: pipelines)
        self.batchRenderer.setCanvasSize(width: self.width, height: self.height)
    }

    // MARK: - Background (Processing API)

    /// 背景を単色で塗りつぶす（グレースケール）
    public func background(_ gray: Float) {
        background(gray, gray, gray)
    }

    /// 背景を単色で塗りつぶす（RGB）
    public func background(_ r: Float, _ g: Float, _ b: Float) {
        // 現在の変換を無視してフルスクリーンの四角形を描画
        let color = SIMD4<Float>(r / 255, g / 255, b / 255, 1)
        batchRenderer.addRect(
            x: 0, y: 0, width: width, height: height,
            color: color,
            transform: .identity
        )
    }

    /// 背景を単色で塗りつぶす（Color）
    public func background(_ color: Color) {
        background(color.r, color.g, color.b)
    }

    // MARK: - Fill (Processing API)

    /// 塗りつぶし色を設定（グレースケール）
    public func fill(_ gray: Float, _ alpha: Float = 255) {
        currentState.fillColor = Color(gray, alpha)
    }

    /// 塗りつぶし色を設定（RGB）
    public func fill(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 255) {
        currentState.fillColor = Color(r, g, b, a)
    }

    /// 塗りつぶし色を設定（Color）
    public func fill(_ color: Color) {
        currentState.fillColor = color
    }

    /// 塗りつぶしを無効化
    public func noFill() {
        currentState.fillColor = nil
    }

    // MARK: - Stroke (Processing API)

    /// 線の色を設定（グレースケール）
    public func stroke(_ gray: Float, _ alpha: Float = 255) {
        currentState.strokeColor = Color(gray, alpha)
    }

    /// 線の色を設定（RGB）
    public func stroke(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 255) {
        currentState.strokeColor = Color(r, g, b, a)
    }

    /// 線の色を設定（Color）
    public func stroke(_ color: Color) {
        currentState.strokeColor = color
    }

    /// 線を無効化
    public func noStroke() {
        currentState.strokeColor = nil
    }

    /// 線の太さを設定
    public func strokeWeight(_ weight: Float) {
        currentState.strokeWeight = weight
    }

    // MARK: - Transform (Processing API)

    /// 現在の変換状態を保存
    public func pushMatrix() {
        stateStack.append(currentState)
    }

    /// 前回保存した変換状態を復元
    public func popMatrix() {
        guard let previous = stateStack.popLast() else { return }
        currentState = previous
    }

    /// 平行移動
    public func translate(_ x: Float, _ y: Float) {
        currentState.transform = currentState.transform *
            float4x4(translation: SIMD3<Float>(x, y, 0))
    }

    /// 回転（ラジアン）
    public func rotate(_ angle: Float) {
        currentState.transform = currentState.transform *
            float4x4(rotationZ: angle)
    }

    /// 均一スケール
    public func scale(_ s: Float) {
        currentState.transform = currentState.transform *
            float4x4(scale: s)
    }

    /// 非均一スケール
    public func scale(_ sx: Float, _ sy: Float) {
        currentState.transform = currentState.transform *
            float4x4(scale: SIMD3<Float>(sx, sy, 1))
    }

    /// 変換をリセット
    public func resetMatrix() {
        currentState.transform = .identity
    }

    // MARK: - Shape Mode (Processing API)

    /// 四角形の描画モードを設定
    public func rectMode(_ mode: RectMode) {
        currentState.rectMode = mode
    }

    /// 楕円の描画モードを設定
    public func ellipseMode(_ mode: EllipseMode) {
        currentState.ellipseMode = mode
    }

    // MARK: - Drawing Primitives (Processing API)

    /// 四角形を描画
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let (adjX, adjY, adjW, adjH) = adjustForRectMode(x, y, w, h)

        // 塗りつぶし
        if let fillColor = currentState.fillColor {
            batchRenderer.addRect(
                x: adjX, y: adjY, width: adjW, height: adjH,
                color: fillColor.normalized,
                transform: currentState.transform
            )
        }

        // 枠線
        if let strokeColor = currentState.strokeColor {
            batchRenderer.addRectStroke(
                x: adjX, y: adjY, width: adjW, height: adjH,
                color: strokeColor.normalized,
                weight: currentState.strokeWeight,
                transform: currentState.transform
            )
        }
    }

    /// 楕円を描画
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let (cx, cy, adjW, adjH) = adjustForEllipseMode(x, y, w, h)

        // 塗りつぶし
        if let fillColor = currentState.fillColor {
            batchRenderer.addEllipse(
                cx: cx, cy: cy, width: adjW, height: adjH,
                color: fillColor.normalized,
                transform: currentState.transform
            )
        }

        // 枠線
        if let strokeColor = currentState.strokeColor {
            batchRenderer.addEllipseStroke(
                cx: cx, cy: cy, width: adjW, height: adjH,
                color: strokeColor.normalized,
                weight: currentState.strokeWeight,
                transform: currentState.transform
            )
        }
    }

    /// 円を描画（楕円のショートカット）
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        ellipse(x, y, diameter, diameter)
    }

    /// 線を描画
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        guard let strokeColor = currentState.strokeColor else { return }

        batchRenderer.addLine(
            x1: x1, y1: y1, x2: x2, y2: y2,
            color: strokeColor.normalized,
            weight: currentState.strokeWeight,
            transform: currentState.transform
        )
    }

    /// 点を描画
    public func point(_ x: Float, _ y: Float) {
        guard let strokeColor = currentState.strokeColor else { return }

        batchRenderer.addPoint(
            x: x, y: y,
            color: strokeColor.normalized,
            size: currentState.strokeWeight,
            transform: currentState.transform
        )
    }

    /// 三角形を描画
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        // 塗りつぶし
        if let fillColor = currentState.fillColor {
            batchRenderer.addTriangle(
                x1: x1, y1: y1,
                x2: x2, y2: y2,
                x3: x3, y3: y3,
                color: fillColor.normalized,
                transform: currentState.transform
            )
        }

        // 枠線
        if let strokeColor = currentState.strokeColor {
            batchRenderer.addTriangleStroke(
                x1: x1, y1: y1,
                x2: x2, y2: y2,
                x3: x3, y3: y3,
                color: strokeColor.normalized,
                weight: currentState.strokeWeight,
                transform: currentState.transform
            )
        }
    }

    /// 四角形（4頂点指定）を描画
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        // 2つの三角形として描画
        if let fillColor = currentState.fillColor {
            batchRenderer.addTriangle(
                x1: x1, y1: y1,
                x2: x2, y2: y2,
                x3: x3, y3: y3,
                color: fillColor.normalized,
                transform: currentState.transform
            )
            batchRenderer.addTriangle(
                x1: x1, y1: y1,
                x2: x3, y2: y3,
                x3: x4, y3: y4,
                color: fillColor.normalized,
                transform: currentState.transform
            )
        }

        // 枠線
        if let strokeColor = currentState.strokeColor {
            let color = strokeColor.normalized
            let weight = currentState.strokeWeight
            let transform = currentState.transform
            batchRenderer.addLine(x1: x1, y1: y1, x2: x2, y2: y2, color: color, weight: weight, transform: transform)
            batchRenderer.addLine(x1: x2, y1: y2, x2: x3, y2: y3, color: color, weight: weight, transform: transform)
            batchRenderer.addLine(x1: x3, y1: y3, x2: x4, y2: y4, color: color, weight: weight, transform: transform)
            batchRenderer.addLine(x1: x4, y1: y4, x2: x1, y2: y1, color: color, weight: weight, transform: transform)
        }
    }

    // MARK: - Coordinate Adjustments

    private func adjustForRectMode(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> (Float, Float, Float, Float) {
        switch currentState.rectMode {
        case .corner:
            return (x, y, w, h)
        case .corners:
            return (x, y, w - x, h - y)
        case .center:
            return (x - w / 2, y - h / 2, w, h)
        case .radius:
            return (x - w, y - h, w * 2, h * 2)
        }
    }

    private func adjustForEllipseMode(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> (Float, Float, Float, Float) {
        switch currentState.ellipseMode {
        case .center:
            return (x, y, w, h)
        case .radius:
            return (x, y, w * 2, h * 2)
        case .corner:
            return (x + w / 2, y + h / 2, w, h)
        case .corners:
            let cx = (x + w) / 2
            let cy = (y + h) / 2
            return (cx, cy, w - x, h - y)
        }
    }

    // MARK: - beginShape/endShape (Processing API)

    /// 頂点形状の描画を開始
    /// - Parameter kind: 形状の種類（デフォルト: polygon）
    public func beginShape(_ kind: ShapeKind = .polygon) {
        shapeVertices.removeAll(keepingCapacity: true)
        shapeKind = kind
        isBuilding = true
    }

    /// 頂点を追加
    public func vertex(_ x: Float, _ y: Float) {
        guard isBuilding else { return }
        shapeVertices.append(SIMD2<Float>(x, y))
    }

    /// 頂点形状の描画を終了（open）
    public func endShape() {
        endShape(.open)
    }

    /// 頂点形状の描画を終了
    /// - Parameter mode: 閉じるかどうか
    public func endShape(_ mode: CloseMode) {
        guard isBuilding else { return }
        isBuilding = false

        guard shapeVertices.count >= 2 else { return }

        let transform = currentState.transform

        switch shapeKind {
        case .points:
            if let strokeColor = currentState.strokeColor {
                for v in shapeVertices {
                    batchRenderer.addPoint(
                        x: v.x, y: v.y,
                        color: strokeColor.normalized,
                        size: currentState.strokeWeight,
                        transform: transform
                    )
                }
            }

        case .lines:
            if let strokeColor = currentState.strokeColor {
                for i in stride(from: 0, to: shapeVertices.count - 1, by: 2) {
                    let v1 = shapeVertices[i]
                    let v2 = shapeVertices[i + 1]
                    batchRenderer.addLine(
                        x1: v1.x, y1: v1.y, x2: v2.x, y2: v2.y,
                        color: strokeColor.normalized,
                        weight: currentState.strokeWeight,
                        transform: transform
                    )
                }
            }

        case .triangles:
            if let fillColor = currentState.fillColor {
                for i in stride(from: 0, to: shapeVertices.count - 2, by: 3) {
                    let v0 = shapeVertices[i]
                    let v1 = shapeVertices[i + 1]
                    let v2 = shapeVertices[i + 2]
                    batchRenderer.addTriangle(
                        x1: v0.x, y1: v0.y,
                        x2: v1.x, y2: v1.y,
                        x3: v2.x, y3: v2.y,
                        color: fillColor.normalized,
                        transform: transform
                    )
                }
            }
            if let strokeColor = currentState.strokeColor {
                for i in stride(from: 0, to: shapeVertices.count - 2, by: 3) {
                    let v0 = shapeVertices[i]
                    let v1 = shapeVertices[i + 1]
                    let v2 = shapeVertices[i + 2]
                    batchRenderer.addTriangleStroke(
                        x1: v0.x, y1: v0.y,
                        x2: v1.x, y2: v1.y,
                        x3: v2.x, y3: v2.y,
                        color: strokeColor.normalized,
                        weight: currentState.strokeWeight,
                        transform: transform
                    )
                }
            }

        case .triangleStrip:
            if let fillColor = currentState.fillColor {
                batchRenderer.addTriangleStrip(
                    vertices: shapeVertices,
                    color: fillColor.normalized,
                    transform: transform
                )
            }

        case .triangleFan:
            if let fillColor = currentState.fillColor {
                batchRenderer.addTriangleFan(
                    vertices: shapeVertices,
                    color: fillColor.normalized,
                    transform: transform
                )
            }

        case .quads:
            if let fillColor = currentState.fillColor {
                batchRenderer.addQuads(
                    vertices: shapeVertices,
                    color: fillColor.normalized,
                    transform: transform
                )
            }
            if let strokeColor = currentState.strokeColor {
                for i in stride(from: 0, to: shapeVertices.count - 3, by: 4) {
                    let v0 = shapeVertices[i]
                    let v1 = shapeVertices[i + 1]
                    let v2 = shapeVertices[i + 2]
                    let v3 = shapeVertices[i + 3]
                    let color = strokeColor.normalized
                    let weight = currentState.strokeWeight
                    batchRenderer.addLine(x1: v0.x, y1: v0.y, x2: v1.x, y2: v1.y, color: color, weight: weight, transform: transform)
                    batchRenderer.addLine(x1: v1.x, y1: v1.y, x2: v2.x, y2: v2.y, color: color, weight: weight, transform: transform)
                    batchRenderer.addLine(x1: v2.x, y1: v2.y, x2: v3.x, y2: v3.y, color: color, weight: weight, transform: transform)
                    batchRenderer.addLine(x1: v3.x, y1: v3.y, x2: v0.x, y2: v0.y, color: color, weight: weight, transform: transform)
                }
            }

        case .quadStrip:
            if let fillColor = currentState.fillColor {
                batchRenderer.addQuadStrip(
                    vertices: shapeVertices,
                    color: fillColor.normalized,
                    transform: transform
                )
            }

        case .polygon:
            let shouldClose = mode == .close
            if let fillColor = currentState.fillColor, shapeVertices.count >= 3 {
                batchRenderer.addPolygon(
                    vertices: shapeVertices,
                    color: fillColor.normalized,
                    transform: transform
                )
            }
            if let strokeColor = currentState.strokeColor {
                batchRenderer.addPolygonStroke(
                    vertices: shapeVertices,
                    color: strokeColor.normalized,
                    weight: currentState.strokeWeight,
                    transform: transform,
                    close: shouldClose
                )
            }
        }

        shapeVertices.removeAll(keepingCapacity: true)
    }

    // MARK: - Flush

    /// バッファされた描画コマンドを実行
    /// フレーム終了時に自動的に呼ばれる
    public func flush() {
        batchRenderer.flush(to: encoder)
    }
}
