import Foundation
import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore

// MARK: - SVG Export (#285)

@Suite("SVG export", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SVGExportTests {

    private func makeCanvas(width: Float = 200, height: Float = 100) throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: width,
            height: height
        )
    }

    private func attach(_ canvas: Canvas2D) -> SVGRecorder {
        let recorder = SVGRecorder(
            width: canvas.width, height: canvas.height, outputPath: "/dev/null")
        canvas.svgRecorder = recorder
        return recorder
    }

    @Test("golden output for basic shapes")
    func goldenBasicShapes() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)

        canvas.background(Color(r: 1, g: 1, b: 1))
        canvas.fillColor = SIMD4(1, 0, 0, 1)
        canvas.hasFill = true
        canvas.hasStroke = false
        canvas.rect(10, 20, 50, 30)
        canvas.hasFill = false
        canvas.hasStroke = true
        canvas.strokeColor = SIMD4(0, 0, 0, 1)
        canvas.currentStrokeWeight = 2
        canvas.circle(100, 50, 40)
        canvas.line(0, 0, 200, 100)

        let expected = """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
            <rect width="200" height="100" fill="rgb(255,255,255)"/>
            <rect x="10" y="20" width="50" height="30" fill="rgb(255,0,0)"/>
            <ellipse cx="100" cy="50" rx="20" ry="20" fill="none" stroke="rgb(0,0,0)" stroke-width="2" stroke-linecap="round"/>
            <line x1="0" y1="0" x2="200" y2="100" fill="none" stroke="rgb(0,0,0)" stroke-width="2" stroke-linecap="round"/>
            </svg>

            """
        #expect(recorder.svgString() == expected)
    }

    @Test("output is deterministic across two identical runs")
    func deterministicOutput() throws {
        func run() throws -> String {
            let canvas = try makeCanvas()
            let recorder = attach(canvas)
            canvas.background(Color(gray: 51 / 255))
            canvas.triangle(10, 10, 90, 10, 50, 80)
            canvas.bezier(0, 0, 30, 100, 70, 100, 100, 0)
            return recorder.svgString()
        }
        #expect(try run() == (try run()))
    }

    @Test("transforms are emitted as matrix attributes")
    func transformAttribute() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.translate(50, 25)
        canvas.rect(0, 0, 10, 10)
        let svg = recorder.svgString()
        #expect(svg.contains(#"transform="matrix(1 0 0 1 50 25)""#))
    }

    @Test("style attributes: alpha, noFill, stroke cap and join")
    func styleAttributes() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.fillColor = SIMD4(0, 0, 1, 0.5)
        canvas.hasFill = true
        canvas.hasStroke = true
        canvas.strokeColor = SIMD4(1, 0, 0, 1)
        canvas.currentStrokeCap = .square
        canvas.currentStrokeJoin = .round
        canvas.rect(0, 0, 10, 10)
        let svg = recorder.svgString()
        #expect(svg.contains(#"fill-opacity="0.5""#))
        #expect(svg.contains(#"stroke-linecap="square""#))
        #expect(svg.contains(#"stroke-linejoin="round""#))
    }

    @Test("rectMode center is resolved before recording")
    func rectModeResolution() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.rectMode(.center)
        canvas.rect(50, 50, 20, 10)
        let svg = recorder.svgString()
        #expect(svg.contains(#"<rect x="40" y="45" width="20" height="10""#))
    }

    @Test("beginShape polygon with contour uses evenodd fill rule")
    func shapeWithContour() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.beginShape()
        canvas.vertex(0, 0)
        canvas.vertex(100, 0)
        canvas.vertex(100, 100)
        canvas.vertex(0, 100)
        canvas.beginContour()
        canvas.vertex(25, 25)
        canvas.vertex(75, 25)
        canvas.vertex(75, 75)
        canvas.vertex(25, 75)
        canvas.endContour()
        canvas.endShape(.close)
        let svg = recorder.svgString()
        #expect(svg.contains(#"fill-rule="evenodd""#))
        #expect(svg.contains("M0 0L100 0L100 100L0 100Z"))
        #expect(svg.contains("M25 25L75 25L75 75L25 75Z"))
    }

    @Test("curveVertex emits cubic bezier segments")
    func curveVertexPath() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.beginShape()
        canvas.curveVertex(0, 50)
        canvas.curveVertex(20, 20)
        canvas.curveVertex(80, 80)
        canvas.curveVertex(100, 50)
        canvas.endShape()
        let svg = recorder.svgString()
        #expect(svg.contains("C"))
        // 描かれる区間は p1→p2（20,20 → 80,80）
        #expect(svg.contains("M20 20"))
    }

    @Test("arc pie closes to the center, full sweep becomes an ellipse")
    func arcModes() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.arc(50, 50, 40, 40, 0, Float.pi / 2, .pie)
        canvas.arc(100, 50, 40, 40, 0, Float.pi * 2, .open)
        let svg = recorder.svgString()
        #expect(svg.contains("L50 50Z"))
        #expect(svg.contains(#"<ellipse cx="100" cy="50""#))
    }

    @Test("clip wraps elements in a clipPath group")
    func clipGroup() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.beginClip(10, 10, 50, 50)
        canvas.rect(0, 0, 100, 100)
        canvas.endClip()
        canvas.rect(0, 0, 5, 5)
        let svg = recorder.svgString()
        #expect(svg.contains(#"<clipPath id="clip1"><rect x="10" y="10" width="50" height="50"/></clipPath>"#))
        #expect(svg.contains(#"<g clip-path="url(#clip1)"><rect x="0" y="0" width="100" height="100""#))
        // クリップ外の要素は g で包まれない
        #expect(svg.contains(#"<rect x="0" y="0" width="5" height="5""#))
    }

    @Test("unsupported features are skipped without adding elements")
    func unsupportedSkipped() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.text("hello", 10, 10)
        canvas.linearGradient(0, 0, 10, 10, Color(gray: 0), Color(gray: 1))
        let baseline = recorder.svgString()
        // 図形要素は 1 つも記録されていない（svg ヘッダ + 閉じタグのみ）
        #expect(!baseline.contains("<text"))
        #expect(!baseline.contains("<path"))
        #expect(!baseline.contains("<rect x"))
    }

    @Test("background clears previously recorded elements")
    func backgroundClears() throws {
        let canvas = try makeCanvas()
        let recorder = attach(canvas)
        canvas.rect(0, 0, 10, 10)
        canvas.background(Color(r: 0, g: 0, b: 0))
        canvas.circle(50, 50, 20)
        let svg = recorder.svgString()
        #expect(!svg.contains("<rect x"))
        #expect(svg.contains("<ellipse"))
    }

    @Test("beginSVGRecord/endSVGRecord writes the file through SketchContext")
    func beginEndSVGWritesFile() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-svg-\(UUID().uuidString)")
        let path = dir.appendingPathComponent("out.svg").path
        defer { try? FileManager.default.removeItem(at: dir) }

        context.beginSVGRecord(path)
        // 二重 beginSVGRecord は警告のみで recorder は維持される
        context.beginSVGRecord(path)
        context.canvas.circle(32, 32, 16)
        context.endSVGRecord()

        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written.contains("<ellipse cx=\"32\" cy=\"32\""))
        // endSVGRecord 後は記録が止まる
        #expect(context.canvas.svgRecorder == nil)
    }
}
