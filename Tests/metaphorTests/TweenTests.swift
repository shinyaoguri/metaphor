import Testing
import simd
@testable import metaphor

// MARK: - Interpolatable

@Suite("Interpolatable")
struct InterpolatableTests {

    @Test("Float interpolation")
    func floatInterpolation() {
        #expect(Float.interpolate(from: 0, to: 100, t: 0) == 0)
        #expect(Float.interpolate(from: 0, to: 100, t: 0.5) == 50)
        #expect(Float.interpolate(from: 0, to: 100, t: 1.0) == 100)
    }

    @Test("SIMD2 interpolation")
    func simd2Interpolation() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(10, 20)
        let mid = SIMD2<Float>.interpolate(from: a, to: b, t: 0.5)
        #expect(mid.x == 5)
        #expect(mid.y == 10)
    }

    @Test("SIMD3 interpolation")
    func simd3Interpolation() {
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(10, 20, 30)
        let result = SIMD3<Float>.interpolate(from: a, to: b, t: 1.0)
        #expect(result.x == 10)
        #expect(result.y == 20)
        #expect(result.z == 30)
    }

    @Test("SIMD4 interpolation")
    func simd4Interpolation() {
        let a = SIMD4<Float>(1, 1, 1, 1)
        let b = SIMD4<Float>(0, 0, 0, 0)
        let mid = SIMD4<Float>.interpolate(from: a, to: b, t: 0.5)
        #expect(mid.x == 0.5)
    }

    @Test("Color interpolation")
    @MainActor
    func colorInterpolation() {
        let a = Color(r: 1, g: 0, b: 0, a: 1)
        let b = Color(r: 0, g: 1, b: 0, a: 1)
        let mid = Color.interpolate(from: a, to: b, t: 0.5)
        #expect(mid.r == 0.5)
        #expect(mid.g == 0.5)
        #expect(mid.b == 0)
    }
}

// MARK: - Tween

@Suite("Tween")
struct TweenTests {

    @Test("Initial value equals from")
    @MainActor
    func initialValue() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0)
        #expect(tw.value == 0)
        #expect(tw.isComplete == false)
        #expect(tw.isActive == false)
    }

    @Test("Tween at 50% progress")
    @MainActor
    func halfwayProgress() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })  // linear
        tw.start()
        tw.update(0.5)
        // Linear easing: t=0.5 → value=50
        #expect(abs(tw.value - 50.0) < 0.01)
        #expect(tw.isActive == true)
    }

    @Test("Tween at 100% completes")
    @MainActor
    func completes() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        tw.update(1.0)
        #expect(tw.value == 100.0)
        #expect(tw.isComplete == true)
    }

    @Test("Tween with delay")
    @MainActor
    func withDelay() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.delay(0.5)
        tw.start()
        tw.update(0.3)  // still in delay
        #expect(tw.value == 0)
        tw.update(0.5)  // delay passed, now 0.3 into animation
        #expect(tw.value > 0)
        #expect(tw.isActive == true)
    }

    @Test("Tween yoyo mode")
    @MainActor
    func yoyoMode() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.yoyo().repeatCount(2)
        tw.start()

        // First cycle
        tw.update(1.0)
        #expect(tw.isComplete == false)

        // Second cycle (reverse)
        tw.update(0.5)
        #expect(tw.value < 100)  // going backwards
    }

    @Test("Tween repeat count")
    @MainActor
    func repeatMode() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
        tw.repeatCount(3)
        tw.start()

        tw.update(0.5)  // cycle 1 done
        #expect(tw.isComplete == false)

        tw.update(0.5)  // cycle 2 done
        #expect(tw.isComplete == false)

        tw.update(0.5)  // cycle 3 done
        #expect(tw.isComplete == true)
    }

    @Test("Tween onComplete callback")
    @MainActor
    func onCompleteCallback() {
        var called = false
        let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 0.5, easing: { $0 })
        tw.onComplete { called = true }
        tw.start()
        tw.update(0.5)
        #expect(called == true)
    }

    @Test("Tween reset")
    @MainActor
    func reset() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        tw.update(0.5)
        #expect(tw.value > 0)

        tw.reset()
        #expect(tw.value == 0)
        #expect(tw.isComplete == false)
        #expect(tw.isActive == false)
    }
}

// MARK: - TweenManager

@Suite("TweenManager")
struct TweenManagerTests {

    @Test("Add and update tweens")
    @MainActor
    func addAndUpdate() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 0.5, easing: { $0 })
        tw.start()
        manager.add(tw)
        #expect(manager.count == 1)

        manager.update(0.25)
        #expect(abs(tw.value - 0.5) < 0.01)
    }

    @Test("Completed tweens are auto-removed")
    @MainActor
    func autoRemoval() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 0.5, easing: { $0 })
        tw.start()
        manager.add(tw)

        manager.update(0.5)
        #expect(tw.isComplete == true)
        #expect(manager.count == 0)
    }

    @Test("Clear removes all tweens")
    @MainActor
    func clearAll() {
        let manager = TweenManager()
        for _ in 0..<5 {
            let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 1.0)
            tw.start()
            manager.add(tw)
        }
        #expect(manager.count == 5)
        manager.clear()
        #expect(manager.count == 0)
    }
}
