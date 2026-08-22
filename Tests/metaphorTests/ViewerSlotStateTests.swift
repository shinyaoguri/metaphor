import Testing
@testable import MetaphorCore

// slot の状態機械（free → inFlight → heldByParent → free）。CONTRACT.md 契約点 5 の補足「同期」。

@Suite("ViewerSlotState")
struct ViewerSlotStateTests {

    @Test("3 slot を順に取り、4 つ目は取れない（latest-wins で publish を飛ばす）")
    func exhaustion() {
        let state = ViewerSlotState(slots: 3)
        let a = state.acquire(), b = state.acquire(), c = state.acquire()
        #expect(a?.slot == 0 && b?.slot == 1 && c?.slot == 2)
        #expect(state.acquire() == nil)
        #expect(state.snapshot.inFlight == [0, 1, 2])
    }

    @Test("complete で親へ渡り seq が進む。release で空きに戻り、再び取れる")
    func lifecycle() {
        let state = ViewerSlotState(slots: 3)
        let ticket = state.acquire()!
        #expect(state.complete(ticket) == 0)
        #expect(state.snapshot.heldByParent == [0])
        #expect(state.snapshot.inFlight.isEmpty)

        // 親が握っている間は同じ slot は取れない（1, 2 が先に出る）。
        #expect(state.acquire()?.slot == 1)
        state.release(slot: 0)
        #expect(state.snapshot.free.contains(0))
        let again = state.acquire()
        #expect(again?.slot == 0, "release された slot が番号順で戻る")
        #expect(state.complete(again!) == 1, "seq は接続内で単調")
    }

    @Test("二重 release・未 complete の release・範囲外は無視する")
    func bogusRelease() {
        let state = ViewerSlotState(slots: 3)
        let ticket = state.acquire()!
        state.release(slot: 0)            // まだ inFlight → 無視
        #expect(state.snapshot.inFlight == [0])
        state.release(slot: 7)            // 範囲外 → 無視
        _ = state.complete(ticket)
        state.release(slot: 0)
        state.release(slot: 0)            // 二重 → 無視
        #expect(state.snapshot.free == [0, 1, 2])
    }

    @Test("abandon は seq を進めずに空きへ戻す")
    func abandon() {
        let state = ViewerSlotState(slots: 3)
        let ticket = state.acquire()!
        state.abandon(ticket)
        #expect(state.snapshot.free == [0, 1, 2])
        #expect(state.complete(state.acquire()!) == 0, "abandon 後の最初の complete が seq 0")
    }

    @Test("reset（resize / 切断）で世代が進み、旧世代の complete は捨てられる")
    func resetInvalidatesOldGeneration() {
        let state = ViewerSlotState(slots: 3)
        let old = state.acquire()!
        state.reset()
        let fresh = state.acquire()!
        #expect(fresh.slot == 0 && fresh.generation == old.generation + 1)
        #expect(state.complete(old) == nil, "旧世代の blit 完了は frame にならない")
        #expect(state.snapshot.inFlight == [0], "新世代の slot 0 は in-flight のまま")
        #expect(state.complete(fresh) == 0)
    }
}
