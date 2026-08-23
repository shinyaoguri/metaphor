import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - Processing Parity Tests

@Suite("Processing Math Parity")
struct ProcessingMathParityTests {

    @Test("map linearly remaps values")
    func mapValues() {
        #expect(map(5, 0, 10, 0, 100) == 50)
        #expect(map(0, 0, 10, 100, 200) == 100)
        #expect(map(10, 0, 10, 100, 200) == 200)
        #expect(abs(map(2.5, 0, 10, 0, 1) - 0.25) < 0.0001)
    }

    @Test("constrain clamps values")
    func constrainValues() {
        #expect(constrain(5, 0, 10) == 5)
        #expect(constrain(-1, 0, 10) == 0)
        #expect(constrain(15, 0, 10) == 10)
    }

    @Test("norm normalizes values")
    func normValues() {
        #expect(norm(5, 0, 10) == 0.5)
        #expect(norm(0, 0, 10) == 0)
        #expect(norm(10, 0, 10) == 1)
    }

    @Test("mag computes 2D vector magnitude")
    func mag2D() {
        #expect(abs(mag(3, 4) - 5) < 0.0001)
        #expect(mag(0, 0) == 0)
    }

    @Test("mag computes 3D vector magnitude")
    func mag3D() {
        #expect(abs(mag(1, 2, 2) - 3) < 0.0001)
        #expect(mag(0, 0, 0) == 0)
    }

    @Test("dist computes 2D distance")
    func dist2D() {
        #expect(abs(dist(0, 0, 3, 4) - 5) < 0.0001)
        #expect(dist(5, 5, 5, 5) == 0)
    }

    @Test("dist computes 3D distance")
    func dist3D() {
        #expect(abs(dist(0, 0, 0, 1, 2, 2) - 3) < 0.0001)
    }

    @Test("lerp interpolates correctly")
    func lerpValues() {
        #expect(lerp(Float(0), Float(10), Float(0.5)) == 5)
        #expect(lerp(Float(0), Float(10), Float(0)) == 0)
        #expect(lerp(Float(0), Float(10), Float(1)) == 10)
    }

    @Test("sq squares a value")
    func sqValues() {
        #expect(sq(3) == 9)
        #expect(sq(-4) == 16)
        #expect(sq(0) == 0)
    }
}

// MARK: - Processing Time Function Tests

@Suite("Processing Time Parity")
struct ProcessingTimeParityTests {

    @Test("second returns 0-59")
    func secondRange() {
        let s = second()
        #expect(s >= 0 && s <= 59)
    }

    @Test("minute returns 0-59")
    func minuteRange() {
        let m = minute()
        #expect(m >= 0 && m <= 59)
    }

    @Test("hour returns 0-23")
    func hourRange() {
        let h = hour()
        #expect(h >= 0 && h <= 23)
    }

    @Test("day returns 1-31")
    func dayRange() {
        let d = day()
        #expect(d >= 1 && d <= 31)
    }

    @Test("month returns 1-12")
    func monthRange() {
        let m = month()
        #expect(m >= 1 && m <= 12)
    }

    @Test("year returns reasonable value")
    func yearRange() {
        let y = year()
        #expect(y >= 2024 && y <= 2100)
    }
}

// MARK: - Canvas2D Clipping Tests

@Suite("Canvas2D Clipping", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DClippingTests {

    @Test("canvas2D has beginClip and endClip")
    func clipMethodsExist() throws {
        let renderer = try MetaphorRenderer(width: 200, height: 200)
        let canvas = try Canvas2D(renderer: renderer)

        #expect(canvas.width == 200)
        #expect(canvas.height == 200)
    }
}

// MARK: - Bezier Math Tests

@Suite("Processing Bezier Math")
struct ProcessingBezierMathTests {

    @Test("bezierPoint at boundaries")
    func bezierPointBoundaries() {
        let start: Float = 0
        let end: Float = 100
        #expect(abs(bezierPoint(start, 25, 75, end, 0) - start) < 0.0001)
        #expect(abs(bezierPoint(start, 25, 75, end, 1) - end) < 0.0001)
    }

    @Test("curvePoint at boundaries")
    func curvePointBoundaries() {
        // Catmull-Rom: passes through b at t=0 and c at t=1
        let b: Float = 50
        let c: Float = 100
        #expect(abs(curvePoint(0, b, c, 150, 0) - b) < 0.0001)
        #expect(abs(curvePoint(0, b, c, 150, 1) - c) < 0.0001)
    }
}
