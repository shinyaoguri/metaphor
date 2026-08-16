import Testing
@testable import MetaphorCore

// `deltaTime` の起点を持つ ``FrameClock`` の単体テスト（Issue #793）。
// 実バグは「noLoop() で止めている間に進んだ実時間が、再開後の最初のフレームの
// deltaTime に丸ごと乗る」というもの。その丸ごと乗る／乗らないの分かれ目が
// このクラスの `resync(to:)` なので、時刻を注入して固定する。
@Suite("FrameClock")
struct FrameClockTests {
    @Test("advance は起点からの経過を返し、起点を進める")
    func advanceReturnsElapsedAndMovesOrigin() {
        let clock = FrameClock(startTime: 1.0)

        #expect(clock.advance(to: 1.5) == 0.5)
        #expect(clock.previousTime == 1.5)
        #expect(clock.advance(to: 1.75) == 0.25)
        #expect(clock.previousTime == 1.75)
    }

    @Test("delta は起点を進めない（同一フレームの compute → draw で同じ経過を読む）")
    func deltaDoesNotMoveOrigin() {
        let clock = FrameClock(startTime: 2.0)

        #expect(clock.delta(at: 2.25) == 0.25)
        #expect(clock.previousTime == 2.0, "delta は起点を進めない")
        // compute と draw は同じフレーム時刻で呼ばれるので、同じ経過になる。
        #expect(clock.advance(to: 2.25) == 0.25)
    }

    // 回帰テスト(#793): resync が無かった頃は、止めていた実時間がそのまま
    // 再開後 1 フレームぶんの deltaTime になっていた（0.8 秒止めれば 0.8 秒）。
    @Test("resync 後の最初の経過に、止めていた時間は乗らない")
    func resyncDropsPausedDuration() {
        let clock = FrameClock(startTime: 0)

        // 60fps で数フレーム進んだところで noLoop()。
        _ = clock.advance(to: 1.0 / 60)
        _ = clock.advance(to: 2.0 / 60)

        // 0.8 秒止めてから loop() で再開（時計は止めている間も進んでいる）。
        let resumeTime: Float = 2.0 / 60 + 0.8
        clock.resync(to: resumeTime)

        // 再開後の最初のフレームは、再開時刻からの経過（＝ほぼ 1 フレームぶん）。
        let firstFrameAfterResume = clock.advance(to: resumeTime + 1.0 / 60)
        #expect(abs(firstFrameAfterResume - 1.0 / 60) < 1e-6,
                "止めていた 0.8 秒が deltaTime に乗ってはいけない")
    }

    @Test("巻き戻り（過去時刻）は 0 に丸める")
    func rewindClampsToZero() {
        let clock = FrameClock(startTime: 5.0)

        #expect(clock.delta(at: 4.0) == 0)
        #expect(clock.advance(to: 4.0) == 0)
        #expect(clock.previousTime == 4.0, "起点は与えられた時刻に従う")
    }
}
