import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Render Regression Tests

@Suite("Render Regression", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct RenderRegressionTests {

    @Test("white clear color fills all pixels")
    func clearWhite() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 1, g: 1, b: 1)
        try helper.render { _ in }

        for (x, y) in [(0, 0), (31, 0), (0, 31), (31, 31), (16, 16)] {
            let p = helper.readPixel(x: x, y: y)
            #expect(p.r > 250, "White clear: pixel (\(x),\(y)) R=\(p.r)")
            #expect(p.g > 250, "White clear: pixel (\(x),\(y)) G=\(p.g)")
            #expect(p.b > 250, "White clear: pixel (\(x),\(y)) B=\(p.b)")
        }
    }

    @Test("black clear color fills all pixels")
    func clearBlack() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { _ in }

        let avg = helper.averageColor(inRect: 0, y: 0, width: 32, height: 32)
        #expect(avg.r < 0.02, "Black clear R=\(avg.r)")
        #expect(avg.g < 0.02, "Black clear G=\(avg.g)")
        #expect(avg.b < 0.02, "Black clear B=\(avg.b)")
    }

    @Test("fill color reflected in drawn rect")
    func fillColorReflected() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.red)
            canvas.noStroke()
            canvas.rect(16, 16, 32, 32)
        }
        // Center of the rect should have reddish pixels
        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.r > 200, "Red fill: R=\(center.r)")
        #expect(center.g < 50, "Red fill: G=\(center.g)")
        #expect(center.b < 50, "Red fill: B=\(center.b)")
    }

    @Test("circle draws non-black pixels in center region")
    func circleDrawsPixels() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.circle(32, 32, 30)
        }
        let hasPixels = helper.hasNonBlackPixels(inRect: 27, y: 27, width: 10, height: 10)
        #expect(hasPixels, "Circle center should have non-black pixels")
    }

    @Test("clear color changes between frames")
    func clearColorChanges() throws {
        var helper = try RenderTestHelper(width: 16, height: 16)

        helper.setClearColor(r: 1, g: 0, b: 0)
        try helper.render { _ in }
        let p1 = helper.readPixel(x: 8, y: 8)

        helper.setClearColor(r: 0, g: 0, b: 1)
        try helper.render { _ in }
        let p2 = helper.readPixel(x: 8, y: 8)

        #expect(p1.r > 200, "First frame should be red: R=\(p1.r)")
        #expect(p1.b < 50, "First frame should be red: B=\(p1.b)")
        #expect(p2.b > 200, "Second frame should be blue: B=\(p2.b)")
        #expect(p2.r < 50, "Second frame should be blue: R=\(p2.r)")
    }

    @Test("rect covers expected region only")
    func rectCoverage() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.rect(0, 0, 32, 32)
        }
        let topLeft = helper.hasNonBlackPixels(inRect: 4, y: 4, width: 8, height: 8)
        #expect(topLeft, "Top-left should have white pixels from rect")

        let bottomRight = helper.hasNonBlackPixels(inRect: 48, y: 48, width: 8, height: 8)
        #expect(!bottomRight, "Bottom-right should remain black")
    }
}
