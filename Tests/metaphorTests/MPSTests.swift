import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - FilterType MPS Cases Tests

@Suite("FilterType MPS Cases")
struct FilterTypeMPSTests {

    @Test("MPS blur case holds sigma")
    func mpsBlurCase() {
        let filter = FilterType.mpsBlur(sigma: 5.0)
        if case .mpsBlur(let sigma) = filter {
            #expect(sigma == 5.0)
        } else {
            Issue.record("Expected mpsBlur case")
        }
    }

    @Test("MPS sobel case")
    func mpsSobelCase() {
        let filter = FilterType.mpsSobel
        if case .mpsSobel = filter {
            // OK
        } else {
            Issue.record("Expected mpsSobel case")
        }
    }

    @Test("MPS laplacian case")
    func mpsLaplacianCase() {
        let filter = FilterType.mpsLaplacian
        if case .mpsLaplacian = filter {
            // OK
        } else {
            Issue.record("Expected mpsLaplacian case")
        }
    }

    @Test("MPS erode case holds radius")
    func mpsErodeCase() {
        let filter = FilterType.mpsErode(radius: 3)
        if case .mpsErode(let r) = filter {
            #expect(r == 3)
        } else {
            Issue.record("Expected mpsErode case")
        }
    }

    @Test("MPS dilate case holds radius")
    func mpsDilateCase() {
        let filter = FilterType.mpsDilate(radius: 2)
        if case .mpsDilate(let r) = filter {
            #expect(r == 2)
        } else {
            Issue.record("Expected mpsDilate case")
        }
    }

    @Test("MPS median case holds diameter")
    func mpsMedianCase() {
        let filter = FilterType.mpsMedian(diameter: 5)
        if case .mpsMedian(let d) = filter {
            #expect(d == 5)
        } else {
            Issue.record("Expected mpsMedian case")
        }
    }

    @Test("MPS threshold case holds value")
    func mpsThresholdCase() {
        let filter = FilterType.mpsThreshold(0.7)
        if case .mpsThreshold(let v) = filter {
            #expect(v == 0.7)
        } else {
            Issue.record("Expected mpsThreshold case")
        }
    }
}
