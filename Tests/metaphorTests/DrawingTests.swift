import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - beginShape Tests

@Suite("beginShape/endShape", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct BeginShapeTests {

    @Test("beginShape and endShape do not crash without encoder")
    func noEncoderSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        // encoder無しでもクラッシュしないことを確認
        canvas.beginShape()
        canvas.vertex(100, 100)
        canvas.vertex(200, 100)
        canvas.vertex(150, 200)
        canvas.endShape(.close)
        // キャンバスの寸法が保持されていること
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }

    @Test("vertex outside beginShape is ignored")
    func vertexOutsideShape() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        // beginShape外のvertexは無視される — currentEncoder が nil のまま
        canvas.vertex(100, 100)
        #expect(canvas.currentEncoder == nil)
    }

    @Test("all shape modes can be used without crash")
    func allModesSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        let modes: [ShapeMode] = [.polygon, .points, .lines, .triangles, .triangleStrip, .triangleFan]
        for mode in modes {
            canvas.beginShape(mode)
            canvas.vertex(100, 100)
            canvas.vertex(200, 100)
            canvas.vertex(150, 200)
            canvas.vertex(250, 200)
            canvas.endShape()
        }
        #expect(modes.count == 6)
        #expect(canvas.width == 1920)
    }
}

// MARK: - curveVertex Tests (#503)

@Suite("curveVertex", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CurveVertexTests {

    private func makeCanvas() throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: 640,
            height: 360
        )
    }

    /// 4 点の curveVertex を記録し、展開後の頂点列を返します。
    private func expand(
        _ canvas: Canvas2D, _ points: [(Float, Float)], tightness: Float? = nil, detail: Int? = nil
    ) -> [(Float, Float)] {
        if let tightness { canvas.curveTightness(tightness) }
        if let detail { canvas.curveDetail(detail) }
        canvas.beginShape()
        for p in points { canvas.curveVertex(p.0, p.1) }
        return canvas.expandShapeVerticesEx().map { ($0.x, $0.y) }
    }

    @Test("曲線は制御点 p1 から始まり p2 で終わる")
    func passesThroughControlPoints() throws {
        let canvas = try makeCanvas()
        let verts = expand(canvas, [(0, 50), (20, 20), (80, 80), (100, 50)], detail: 20)

        let first = try #require(verts.first)
        let last = try #require(verts.last)
        #expect(abs(first.0 - 20) < 0.001)
        #expect(abs(first.1 - 20) < 0.001)
        #expect(abs(last.0 - 80) < 0.001)
        #expect(abs(last.1 - 80) < 0.001)
    }

    @Test("既定の tightness では標準 Catmull-Rom（curvePoint）と一致する")
    func matchesStandardCatmullRom() throws {
        let canvas = try makeCanvas()
        let pts: [(Float, Float)] = [(0, 50), (20, 20), (80, 80), (100, 50)]
        let detail = 8
        let verts = expand(canvas, pts, detail: detail)

        // verts[0] は始点 p1。以降 detail 個が t = 1/detail ... 1 に対応する
        #expect(verts.count == detail + 1)
        for step in 1...detail {
            let t = Float(step) / Float(detail)
            let ex = curvePoint(pts[0].0, pts[1].0, pts[2].0, pts[3].0, t)
            let ey = curvePoint(pts[0].1, pts[1].1, pts[2].1, pts[3].1, t)
            #expect(abs(verts[step].0 - ex) < 0.001)
            #expect(abs(verts[step].1 - ey) < 0.001)
        }
    }

    @Test("tightness を変えても端点は制御点に固定される", arguments: [Float(-5), -1, 0, 1, 5])
    func tightnessKeepsEndpoints(_ tightness: Float) throws {
        let canvas = try makeCanvas()
        let verts = expand(canvas, [(0, 50), (20, 20), (80, 80), (100, 50)], tightness: tightness, detail: 12)

        let first = try #require(verts.first)
        let last = try #require(verts.last)
        #expect(abs(first.0 - 20) < 0.001)
        #expect(abs(first.1 - 20) < 0.001)
        #expect(abs(last.0 - 80) < 0.001)
        #expect(abs(last.1 - 80) < 0.001)
    }

    @Test("円周上に打った点は円の内側に収まる（拡大・平行移動しない）")
    func staysOnCircle() throws {
        let canvas = try makeCanvas()
        let cx: Float = 320, cy: Float = 180, r: Float = 100
        var pts: [(Float, Float)] = []
        for i in -1...74 {
            let a = Float(i) / 72 * TWO_PI
            pts.append((cx + cos(a) * r, cy + sin(a) * r))
        }
        let verts = expand(canvas, pts, detail: 20)

        #expect(!verts.isEmpty)
        for v in verts {
            let d = sqrt((v.0 - cx) * (v.0 - cx) + (v.1 - cy) * (v.1 - cy))
            // Catmull-Rom は円を厳密には再現しないが、半径のずれは 1% 未満に収まる
            #expect(abs(d - r) < r * 0.01)
        }
    }

    @Test("curveVertex が 4 点未満なら何も展開しない")
    func tooFewPoints() throws {
        let canvas = try makeCanvas()
        #expect(expand(canvas, [(0, 0), (10, 10), (20, 0)]).isEmpty)
    }
}

// MARK: - curve() Tests (#538)

@Suite("curve", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CurveTests {

    /// p0/p3 を制御ハンドルに、p1 → p2 を描く 4 点。
    private let pts: [(Float, Float)] = [(0, 50), (20, 20), (80, 80), (100, 50)]

    private func makeCanvas() throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: 640,
            height: 360
        )
    }

    /// `curve()` が描く経路の頂点列を返します。
    private func path(
        _ canvas: Canvas2D, tightness: Float? = nil, detail: Int? = nil
    ) -> [(x: Float, y: Float)] {
        if let tightness { canvas.curveTightness(tightness) }
        if let detail { canvas.curveDetail(detail) }
        return canvas.curveSegmentPoints(
            pts[0].0, pts[0].1, pts[1].0, pts[1].1, pts[2].0, pts[2].1, pts[3].0, pts[3].1)
    }

    @Test("既定の tightness では標準 Catmull-Rom（curvePoint）と一致する")
    func matchesStandardCatmullRom() throws {
        let canvas = try makeCanvas()
        let detail = 8
        let verts = path(canvas, detail: detail)

        #expect(verts.count == detail + 1)
        for step in 1...detail {
            let t = Float(step) / Float(detail)
            let ex = curvePoint(pts[0].0, pts[1].0, pts[2].0, pts[3].0, t)
            let ey = curvePoint(pts[0].1, pts[1].1, pts[2].1, pts[3].1, t)
            #expect(abs(verts[step].x - ex) < 0.001)
            #expect(abs(verts[step].y - ey) < 0.001)
        }
    }

    @Test("curveTightness が経路を変える")
    func tightnessChangesPath() throws {
        let loose = path(try makeCanvas(), tightness: -2, detail: 12)
        let normal = path(try makeCanvas(), tightness: 0, detail: 12)
        let tight = path(try makeCanvas(), tightness: 0.8, detail: 12)

        // 制御点が対称な配置だと t = 0.5 の 1 点だけは tightness に依らず同じ位置に来るため、
        // 中央の頂点ではなく経路全体の最大ずれで比較する
        func maxDiff(_ a: [(x: Float, y: Float)], _ b: [(x: Float, y: Float)]) -> Float {
            zip(a, b).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max() ?? 0
        }
        #expect(maxDiff(loose, normal) > 0.5)
        #expect(maxDiff(tight, normal) > 0.5)
    }

    @Test("tightness = 1 では 2 点を結ぶ直線の経路になる")
    func tightnessOneIsStraight() throws {
        let verts = path(try makeCanvas(), tightness: 1, detail: 16)

        // p1 → p2 の線分からの距離が 0（媒介変数の進み方は等速でなくてよい）
        let (ax, ay) = pts[1]
        let (bx, by) = pts[2]
        let len = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
        for v in verts {
            let cross = (bx - ax) * (v.y - ay) - (by - ay) * (v.x - ax)
            #expect(abs(cross) / len < 0.001)
        }
    }

    @Test("tightness を変えても端点は制御点に固定される", arguments: [Float(-5), -1, 0, 1, 5])
    func tightnessKeepsEndpoints(_ tightness: Float) throws {
        let verts = path(try makeCanvas(), tightness: tightness, detail: 12)

        let first = try #require(verts.first)
        let last = try #require(verts.last)
        #expect(abs(first.x - pts[1].0) < 0.001)
        #expect(abs(first.y - pts[1].1) < 0.001)
        #expect(abs(last.x - pts[2].0) < 0.001)
        #expect(abs(last.y - pts[2].1) < 0.001)
    }

    @Test("画面の経路と SVG 書き出しが一致する", arguments: [Float(0), 0.5, -1])
    func matchesSVGOutput(_ tightness: Float) throws {
        let canvas = try makeCanvas()
        let recorder = SVGRecorder(
            width: canvas.width, height: canvas.height, outputPath: "/dev/null")
        canvas.svgRecorder = recorder
        canvas.hasStroke = true
        canvas.curveTightness(tightness)
        canvas.curveDetail(10)
        canvas.curve(
            pts[0].0, pts[0].1, pts[1].0, pts[1].1, pts[2].0, pts[2].1, pts[3].0, pts[3].1)

        // SVG は同じ区間を cubic bezier 1 本で書き出す（M x y C c1x c1y c2x c2y x y）
        let n = try pathNumbers(recorder.svgString())
        #expect(n.count == 8)

        let verts = path(canvas)
        for (i, v) in verts.enumerated() {
            let t = Float(i) / Float(verts.count - 1)
            #expect(abs(bezierPoint(n[0], n[2], n[4], n[6], t) - v.x) < 0.01)
            #expect(abs(bezierPoint(n[1], n[3], n[5], n[7], t) - v.y) < 0.01)
        }
    }

    /// SVG 文字列の最初の `<path d="...">` から数値を出現順に取り出します。
    private func pathNumbers(_ svg: String) throws -> [Float] {
        let head = try #require(svg.range(of: "<path d=\""))
        let rest = svg[head.upperBound...]
        let tail = try #require(rest.range(of: "\""))
        return rest[..<tail.lowerBound]
            .split(whereSeparator: { !"0123456789.-".contains($0) })
            .compactMap { Float($0) }
    }
}

// MARK: - Canvas2D GPU Tests

@Suite("Canvas2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DTests {

    @Test("can create Canvas2D from components")
    func createFromComponents() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }

    @Test("can create Canvas2D from renderer")
    func createFromRenderer() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }

    @Test("ellipseSegments adapts to radius within [32, 128]")
    func ellipseSegmentsAdaptsToRadius() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)

        // 小半径・不正値は下限 32
        #expect(canvas.ellipseSegments(forRadius: 0) == 32)
        #expect(canvas.ellipseSegments(forRadius: -10) == 32)
        #expect(canvas.ellipseSegments(forRadius: Float.nan) == 32)
        #expect(canvas.ellipseSegments(forRadius: 24) == 32)
        // 中間域は 32 超〜128 未満に増える（d=300 の円グラフ相当）
        let mid = canvas.ellipseSegments(forRadius: 150)
        #expect(mid > 32 && mid < 128, "r=150 は中間の分割数になる: \(mid)")
        // 巨大半径は上限 128
        #expect(canvas.ellipseSegments(forRadius: 100_000) == 128)
        // 半径に対して単調非減少
        var prev = 0
        for r in stride(from: Float(1), through: 3000, by: 50) {
            let n = canvas.ellipseSegments(forRadius: r)
            #expect(n >= prev, "r=\(r) で分割数が減少した: \(prev) -> \(n)")
            prev = n
        }
    }
}

// MARK: - Canvas2D currentEncoder Tests

@Suite("Canvas2D Encoder Access", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DEncoderTests {

    @Test("currentEncoder is nil before begin")
    func encoderNilBeforeBegin() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        #expect(canvas.currentEncoder == nil)
    }
}

// MARK: - Canvas3D Shader Tests

@Suite("Canvas3D Shader")
struct Canvas3DShaderTests {

    @Test("canvas3D function name constants have expected values")
    func shaderFunctions() {
        #expect(BuiltinShaders.FunctionName.canvas3DVertex == "metaphor_canvas3DVertex")
        #expect(BuiltinShaders.FunctionName.canvas3DFragment == "metaphor_canvas3DFragment")
    }

    @Test("canvas3D shader resource contains Canvas3DUniforms struct")
    func uniformsStruct() {
        let source = ShaderLibrary.loadShaderSource("canvas3D")
        #expect(source != nil)
        #expect(source?.contains("Canvas3DUniforms") == true)
        #expect(source?.contains("normalMatrix") == true)
        #expect(source?.contains("lightCount") == true)
    }

    @Test("canvas3D shader resource includes metal_stdlib")
    func metalStdlib() {
        let source = ShaderLibrary.loadShaderSource("canvas3D")
        #expect(source?.contains("metal_stdlib") == true)
    }
}

// MARK: - Canvas3D Uniforms Layout Tests

@Suite("Canvas3DUniforms")
struct Canvas3DUniformsTests {

    @Test("Canvas3DUniforms has expected stride (240 bytes)")
    func uniformsStride() {
        let stride = MemoryLayout<Canvas3DUniforms>.stride
        // 3x float4x4(64) + 2x float4(16) + float(4) + 3x uint32(4) + pad = 240
        #expect(stride == 240)
    }

    @Test("modelMatrix is at offset 0")
    func modelMatrixOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.modelMatrix)!
        #expect(offset == 0)
    }

    @Test("viewProjectionMatrix is at offset 64")
    func viewProjectionOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.viewProjectionMatrix)!
        #expect(offset == 64)
    }

    @Test("normalMatrix is at offset 128")
    func normalMatrixOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.normalMatrix)!
        #expect(offset == 128)
    }

    @Test("color is at offset 192")
    func colorOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.color)!
        #expect(offset == 192)
    }

    @Test("cameraPosition is at offset 208")
    func cameraPositionOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.cameraPosition)!
        #expect(offset == 208)
    }

    @Test("time is at offset 224")
    func timeOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.time)!
        #expect(offset == 224)
    }

    @Test("lightCount is at offset 228")
    func lightCountOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.lightCount)!
        #expect(offset == 228)
    }

    @Test("hasTexture is at offset 232")
    func hasTextureOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.hasTexture)!
        #expect(offset == 232)
    }
}

// MARK: - Vertex3D Layout Tests

@Suite("Vertex3D")
struct Vertex3DTests {

    @Test("Vertex3D stride matches positionNormalColor layout")
    func strideMatchesLayout() {
        let stride = MemoryLayout<Vertex3D>.stride
        let expected = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        #expect(stride == expected)  // 48 bytes
    }
}

// MARK: - Canvas3D Tests

@Suite("Canvas3D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DTests {

    @Test("can create Canvas3D from renderer")
    func createFromRenderer() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)
        #expect(canvas3D.width == 1920)
        #expect(canvas3D.height == 1080)
    }
}

// MARK: - ShaderLibrary Canvas3D Registration Tests

@Suite("ShaderLibrary Canvas3D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShaderLibraryCanvas3DTests {

    @Test("canvas3D is registered in ShaderLibrary")
    func canvas3DRegistered() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas3D))
    }

    @Test("can retrieve canvas3D vertex function")
    func canvas3DVertexFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        #expect(fn != nil)
    }

    @Test("can retrieve canvas3D fragment function")
    func canvas3DFragmentFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DFragment,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        #expect(fn != nil)
    }
}

// MARK: - Textured Shader Tests

@Suite("Canvas2D Textured Shader", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DTexturedShaderTests {

    @Test("canvas2DTextured shader is registered")
    func registered() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2DTextured))
    }

    @Test("can retrieve textured vertex function")
    func vertexFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        #expect(fn != nil)
    }

    @Test("can retrieve textured fragment function")
    func fragmentFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        #expect(fn != nil)
    }
}

// MARK: - Vertex Layout Tests

@Suite("VertexLayout position2DTexCoordColor")
struct Position2DTexCoordColorTests {

    @Test("stride is 32 bytes")
    func strideCheck() {
        let desc = VertexLayout.position2DTexCoordColor.makeDescriptor()
        #expect(desc.layouts[0].stride == 32)
    }
}
