import Testing
import simd
@testable import metaphor
@testable import MetaphorCore

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
        let a = Color(r: 1, g: 0, b: 0, alpha: 1)
        let b = Color(r: 0, g: 1, b: 0, alpha: 1)
        let mid = Color.interpolate(from: a, to: b, t: 0.5)
        #expect(mid.r == 0.5)
        #expect(mid.g == 0.5)
        #expect(mid.b == 0)
    }

    // オーバーシュートするイージング（easeOutBack / easeOutElastic）は 0...1 を外れた
    // t を渡してくるため、組み込みの Interpolatable はクランプせず外挿する契約。
    @Test("範囲外の t をクランプせず外挿する")
    func extrapolatesOutOfRangeT() {
        #expect(abs(Float.interpolate(from: 0, to: 100, t: 1.2) - 120) < 1e-3)
        #expect(abs(Float.interpolate(from: 0, to: 100, t: -0.2) - (-20)) < 1e-3)

        let over = SIMD2<Float>.interpolate(from: SIMD2(0, 0), to: SIMD2(10, 20), t: 1.5)
        #expect(over.x == 15)
        #expect(over.y == 30)

        let under = SIMD3<Float>.interpolate(
            from: SIMD3(0, 0, 0), to: SIMD3(10, 20, 30), t: -0.1)
        #expect(abs(under.x - (-1)) < 1e-3)
        #expect(abs(under.z - (-3)) < 1e-3)
    }

    @Test("Color の外挿は成分が 0...1 を外れうる")
    @MainActor
    func colorExtrapolatesBeyondUnitRange() {
        let a = Color(r: 0, g: 0, b: 0, alpha: 1)
        let b = Color(r: 1, g: 0.5, b: 0, alpha: 1)
        let over = Color.interpolate(from: a, to: b, t: 1.2)
        #expect(over.r > 1.0)
        #expect(abs(over.g - 0.6) < 1e-6)
        #expect(over.b == 0)
    }
}

// MARK: - Easing Overshoot

@Suite("Easing overshoot")
struct EasingOvershootTests {

    private static func sampledRange(_ easing: (Float) -> Float) -> (min: Float, max: Float) {
        let samples = stride(from: Float(0), through: Float(1), by: 0.005).map(easing)
        return (samples.min()!, samples.max()!)
    }

    @Test("easeOutBack / easeOutElastic は 1.0 を超える区間を持つ")
    func outEasingsOvershoot() {
        #expect(Self.sampledRange(easeOutBack).max > 1.0)
        #expect(Self.sampledRange(easeOutElastic).max > 1.0)
    }

    @Test("easeInBack / easeInElastic は 0.0 を下回る区間を持つ")
    func inEasingsUndershoot() {
        #expect(Self.sampledRange(easeInBack).min < 0.0)
        #expect(Self.sampledRange(easeInElastic).min < 0.0)
    }

    @Test("両端は 0 と 1 に固定される")
    func endpointsAreExact() {
        for easing in [easeOutBack, easeOutElastic, easeInBack, easeInElastic] {
            #expect(abs(easing(0)) < 1e-5)
            #expect(abs(easing(1) - 1) < 1e-5)
        }
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

    // 以下 4 本は #946 で足した isWaiting を固定する。
    // 「袖で出番を待っている（.delaying）」を「そもそも出番が無い（.idle）」から
    // 外から区別できることが本題。

    @Test("delay 待機中は isWaiting だけが true になる")
    @MainActor
    func waitingDuringDelay() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.delay(0.5)
        tw.start()

        #expect(tw.isWaiting == true)
        #expect(tw.isActive == false, "待機中はまだ動いていない")
        #expect(tw.isComplete == false)
    }

    @Test("待機が明けると isWaiting と isActive が入れ替わる")
    @MainActor
    func waitingFlipsToActiveWhenDelayElapses() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.delay(0.5)
        tw.start()
        #expect(tw.isWaiting == true)

        tw.update(0.5)  // delay ちょうど分。ここで .delaying → .running

        #expect(tw.isWaiting == false)
        #expect(tw.isActive == true)
    }

    @Test("delay を付けなければ start() 直後から isWaiting は false")
    @MainActor
    func noDelayNeverWaits() {
        // 境界: delayDuration == 0 は .delaying を通らず直接 .running に入る。
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()

        #expect(tw.isWaiting == false)
        #expect(tw.isActive == true)
    }

    @Test("走っていないトゥイーンは isWaiting も false（.idle と区別できる）")
    @MainActor
    func idleAndFinishedAreNotWaiting() {
        // これが本題。delay 付きでも「待機中でない」3 つの状態はすべて false になる。
        // ここが true に漏れると、isWaiting は「delay が設定されている」を意味してしまい、
        // .delaying を指すプロパティとして役に立たない。
        let notStarted = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        notStarted.delay(0.5)
        #expect(notStarted.isWaiting == false, "未 start() は袖で待ってすらいない")

        let afterReset = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        afterReset.delay(0.5)
        afterReset.start()
        #expect(afterReset.isWaiting == true)
        afterReset.reset()
        #expect(afterReset.isWaiting == false, "reset() は .idle へ落とす")

        let afterCancel = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        afterCancel.delay(0.5)
        afterCancel.start()
        #expect(afterCancel.isWaiting == true)
        afterCancel.cancel()
        #expect(afterCancel.isWaiting == false, "cancel() は .complete へ落とす")
        #expect(afterCancel.isComplete == true)
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

    // 以下 3 本は #840 で doc に書き足した「組み合わせたときの挙動」を固定する。
    // どれも実装は妥当だが doc からは読み取れず、読者が別の期待を持つ地点。

    @Test("yoyo() 単独では往復せず to で完了する")
    @MainActor
    func yoyoWithoutRepeatDoesNotReverse() {
        // 方向が反転するのはサイクルとサイクルの境目。既定は 1 サイクルなので
        // 境目が来る前に完了し、yoyo() だけでは何も起きない。
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.yoyo()
        tw.start()

        tw.update(1.0)
        #expect(tw.isComplete == true)
        #expect(tw.value == 100.0, "往復したなら from(0) に戻っているはず")
    }

    @Test("yoyo() の着地点は総サイクル数の偶奇で決まる")
    @MainActor
    func yoyoFinalValueDependsOnCycleParity() {
        // 往路 → 復路 → 往路 … と交互に走るので、偶数サイクルで終われば from、
        // 奇数サイクルで終われば to に着く。
        for (cycles, expected) in [(2, Float(0)), (3, Float(100)), (4, Float(0))] {
            let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
            tw.yoyo().repeatCount(cycles)
            tw.start()
            for _ in 0..<cycles { tw.update(1.0) }

            #expect(tw.isComplete == true, "cycles=\(cycles)")
            #expect(tw.value == expected, "cycles=\(cycles) の着地点が \(tw.value)")
        }
    }

    @Test("delay は繰り返しの初回サイクルにのみ掛かる")
    @MainActor
    func delayAppliesOnlyToFirstCycle() {
        // 0.25 秒刻み（Float で誤差なく積める）。delay 0.5 + duration 1.0 × 3 サイクル
        // = 3.5 秒 = 14 刻みで完了する。毎周 delay が掛かるなら 4.5 秒 = 18 刻みになる。
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.delay(0.5).repeatCount(3)
        tw.start()

        var ticks = 0
        while !tw.isComplete && ticks < 100 {
            tw.update(0.25)
            ticks += 1
        }
        #expect(ticks == 14, "完了まで \(ticks) 刻み。毎周 delay が掛かるなら 18 になる")
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

    @Test("Large delta consumes multiple repeat cycles at once")
    @MainActor
    func largeDeltaConsumesMultipleCycles() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
        tw.repeatCount(3)
        tw.start()

        // 3サイクル分（1.5s）を一度の update で渡すと、その場で完了する。
        tw.update(1.5)
        #expect(tw.isComplete == true)
    }

    @Test("Large delta with infinite repeat does not complete or stall")
    @MainActor
    func largeDeltaInfiniteRepeat() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
        tw.repeatCount(0)  // 無限リピート
        tw.start()

        // 10サイクル分を一度に渡しても無限ループせず、実行中のまま残差で進む。
        tw.update(5.0)
        #expect(tw.isComplete == false)
        #expect(tw.isActive == true)
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

    @Test("Cancel completes without firing onComplete")
    @MainActor
    func cancel() {
        var fired = false
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
            .onComplete { fired = true }
        tw.start()
        tw.update(0.5)

        tw.cancel()
        #expect(tw.isComplete == true)
        #expect(fired == false)
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

    @Test("Cancelled infinite-repeat tween is auto-removed")
    @MainActor
    func cancelledInfiniteTweenRemoval() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 0.5, easing: { $0 })
            .repeatCount(0)  // 無限リピート: cancel() しない限り完了しない
        tw.start()
        manager.add(tw)

        manager.update(5.0)
        #expect(manager.count == 1)

        tw.cancel()
        manager.update(0.01)
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

// MARK: - Tween registration lifetime

/// 登録の唯一の出口が「完了」だったため、そこへ至らない経路
/// （未 start のまま・完了後にもう一度 `start()`）が噛み合っていなかった。
/// 登録の寿命が `Tween` の状態機械と一致することを固定する。
@Suite("Tween registration lifetime")
struct TweenRegistrationLifetimeTests {

    @Test("完走して登録が外れたトゥイーンでも start() でもう一度動く")
    @MainActor
    func restartAfterCompletionReregisters() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
        tw.start()
        manager.add(tw)

        manager.update(0.5)
        #expect(tw.isComplete == true)
        #expect(manager.count == 0)  // 完了したので登録は外れている

        tw.start()  // 再演。登録し直されないと二度と動かない
        #expect(manager.count == 1)

        manager.update(0.25)
        #expect(abs(tw.value - 50.0) < 0.01)
        #expect(tw.isActive == true)
    }

    @Test("未 start のトゥイーンは滞留せず、参照も解放される")
    @MainActor
    func idleTweensAreEvictedAndReleased() {
        let manager = TweenManager()
        for _ in 0..<600 {
            manager.add(Tween(from: 0.0 as Float, to: 1.0, duration: 1.0))
        }
        #expect(manager.count == 600)

        manager.update(1.0 / 60)
        #expect(manager.count == 0)

        // AnyTween の 2 クロージャがトゥイーンを強参照するので、外れないことは
        // そのままメモリ滞留を意味する。外れれば解放されることまで見る。
        weak var weakTween: Tween<Float>?
        do {
            let tw = Tween(from: 0.0 as Float, to: 1.0, duration: 1.0)
            weakTween = tw
            manager.add(tw)
        }
        #expect(weakTween != nil)  // マネージャが握っている
        manager.update(1.0 / 60)
        #expect(weakTween == nil)  // 未 start なので外れ、解放される
    }

    @Test("reset() で idle に戻したトゥイーンも外れ、start() で戻る")
    @MainActor
    func resetEvictsAndStartRestores() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        manager.add(tw)
        manager.update(0.5)
        #expect(manager.count == 1)

        tw.reset()
        manager.update(1.0 / 60)
        #expect(manager.count == 0)
        #expect(tw.value == 0)

        tw.start()
        #expect(manager.count == 1)
        manager.update(0.5)
        #expect(abs(tw.value - 50.0) < 0.01)
    }

    @Test("同じトゥイーンを二重に add しても 1 倍速のまま")
    @MainActor
    func doubleAddDoesNotDoubleSpeed() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        manager.add(tw)
        manager.add(tw)  // 2 回目は弾かれる
        #expect(manager.count == 1)

        manager.update(0.5)
        #expect(abs(tw.value - 50.0) < 0.01)  // 2 倍速なら 100.0 になり完了してしまう
        #expect(tw.isComplete == false)
    }

    @Test("start() 済みのトゥイーンを add しても二重登録にならない")
    @MainActor
    func addAfterStartDoesNotDoubleRegister() {
        // `tween()` ファクトリは add するが start しない。利用者が受け取ってから
        // start() すると再登録が走るので、そこで二重登録にならないことを見る。
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        manager.add(tw)   // ファクトリ相当（まだ .idle）
        tw.start()        // ここで再登録が走る
        #expect(manager.count == 1)

        manager.update(0.5)
        #expect(abs(tw.value - 50.0) < 0.01)
    }
}

// MARK: - Tween invalid delta

/// `TweenManager.update(_:)` は public で、利用者が自前で計算した `deltaTime` を
/// そのまま受け取る。非有限・負・巨大な刻みでも状態が壊れず、必ず停止することを固定する。
@Suite("Tween invalid delta")
struct TweenInvalidDeltaTests {

    @Test("NaN の刻みを 1 回受けても状態が汚れず、次のフレームから復帰する")
    @MainActor
    func nanDeltaDoesNotPoisonState() {
        let manager = TweenManager()
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        manager.add(tw)

        for _ in 0..<16 { manager.update(1.0 / 64) }  // 0.25 秒ぶん進める
        #expect(abs(tw.value - 25.0) < 0.01)

        manager.update(Float.nan)  // 壊れた刻みを 1 回だけ渡す
        #expect(tw.value.isNaN == false)
        #expect(abs(tw.value - 25.0) < 0.01)  // 値は据え置き

        for _ in 0..<600 { manager.update(1.0 / 64) }  // 以降は通常どおり進んで完了する
        #expect(tw.value == 100.0)
        #expect(tw.isComplete == true)
        #expect(manager.count == 0)  // 完了したので登録も外れる
    }

    @Test("ディレイ中に NaN を受けてもディレイが明ける")
    @MainActor
    func nanDeltaDuringDelayDoesNotStall() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.delay(0.5)
        tw.start()

        tw.update(0.25)
        tw.update(Float.nan)  // ディレイ中に壊れた刻み
        #expect(tw.value.isNaN == false)

        tw.update(0.25)  // ここでディレイが明ける
        #expect(tw.isActive == true)

        tw.update(0.5)
        #expect(abs(tw.value - 50.0) < 0.01)
    }

    @Test("負の刻みは無視され、from を下回って外挿されない")
    @MainActor
    func negativeDeltaIsIgnored() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 1.0, easing: { $0 })
        tw.start()
        tw.update(0.5)
        #expect(abs(tw.value - 50.0) < 0.01)

        tw.update(-0.75)
        #expect(tw.value >= 0)                // from を下回らない
        #expect(abs(tw.value - 50.0) < 0.01)  // 進みも戻りもしない

        tw.update(0.25)  // 続きは通常どおり
        #expect(abs(tw.value - 75.0) < 0.01)
    }

    // 以下 3 本は修正前だと while を抜けられずテストランナーごとハングするため
    // .timeLimit を必ず付ける。
    @Test("無限リピートに .infinity を渡しても停止する", .timeLimit(.minutes(1)))
    @MainActor
    func infiniteDeltaWithInfiniteRepeatTerminates() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
            .repeatCount(0)  // 無限リピート
        tw.start()
        tw.update(0.25)

        tw.update(.infinity)
        #expect(tw.isActive == true)
        #expect(tw.value.isNaN == false)
        #expect(abs(tw.value - 50.0) < 0.01)  // 直前の位置のまま
    }

    @Test("無限リピートに巨大な有限刻みを渡しても桁飽和で停止する", .timeLimit(.minutes(1)))
    @MainActor
    func hugeFiniteDeltaWithInfiniteRepeatTerminates() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
            .repeatCount(0)  // 無限リピート
        tw.start()

        // Float では 1e9 - 0.5 == 1e9（ulp(1e9) = 64）。有限値なので入口の guard では
        // 止まらず、while 側で飽和を検出して抜ける必要がある。
        tw.update(1e9)
        #expect(tw.isActive == true)
        #expect(tw.value.isNaN == false)

        tw.update(0.25)  // サイクル先頭へ丸まっているので通常どおり進む
        #expect(abs(tw.value - 50.0) < 0.01)
    }

    @Test("有限リピートに巨大な刻みを渡すと全サイクル経過とみなして完了する",
          .timeLimit(.minutes(1)))
    @MainActor
    func hugeFiniteDeltaWithFiniteRepeatCompletes() {
        let tw = Tween(from: 0.0 as Float, to: 100.0, duration: 0.5, easing: { $0 })
            .repeatCount(3)
        tw.start()

        // 飽和検出が有限リピートの完了を横取りしないこと（修正前もここは完了していた）。
        tw.update(1e9)
        #expect(tw.isComplete == true)
        #expect(tw.value == 100.0)
    }
}
