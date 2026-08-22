import Foundation
import os

/// viewer frame IPC の slot の状態機械（純ロジック・スレッド安全）。
///
/// slot は 3 つの状態を巡る:
///
/// ```text
/// free ──acquire()──▶ inFlight（GPU が blit 中）──complete()──▶ heldByParent（親が読んでいる）──release()──▶ free
/// ```
///
/// `acquire` はメインアクター（`post()`）、`complete` は command buffer の完了ハンドラ（任意スレッド）、
/// `release` は socket の受信スレッドから呼ばれるので、状態はロックで守る。
/// 3 枚とも親が握っている（か GPU が書いている）なら `acquire` は `nil` を返し、呼び出し側は
/// そのフレームの publish を飛ばす（latest-wins。描画は止めない）。
///
/// world（共有メモリ）を作り直す（resize）と ``reset()`` で世代が進み、旧世代の blit の完了は
/// `complete` で捨てられる（新世代で同じ番号の slot を取り直していても誤って親へ渡さない）。
final class ViewerSlotState: @unchecked Sendable {
    /// `acquire` で得た slot と、その時点の世代。
    struct Ticket: Equatable, Sendable {
        let slot: Int
        let generation: Int
    }

    struct Snapshot: Equatable, Sendable {
        var free: Set<Int>
        var inFlight: Set<Int>
        var heldByParent: Set<Int>
        var nextSeq: Int
        var generation: Int
    }

    private let state: OSAllocatedUnfairLock<Snapshot>
    let slots: Int

    init(slots: Int = ViewerFrameLayout.slotCount) {
        precondition(slots > 0)
        self.slots = slots
        self.state = OSAllocatedUnfairLock(initialState: Snapshot(
            free: Set(0..<slots), inFlight: [], heldByParent: [], nextSeq: 0, generation: 0
        ))
    }

    /// 空いている slot を 1 つ取り、`inFlight` にする。無ければ `nil`。
    /// 番号の小さい順に返すので、親が返した順とは無関係に決定的。
    func acquire() -> Ticket? {
        state.withLock { snapshot in
            guard let slot = snapshot.free.min() else { return nil }
            snapshot.free.remove(slot)
            snapshot.inFlight.insert(slot)
            return Ticket(slot: slot, generation: snapshot.generation)
        }
    }

    /// GPU の書き込みが終わった。`heldByParent` に移し、その `frame` に付ける `seq` を返す。
    /// 世代が進んでいる（resize / 切断で world が捨てられた）か未 acquire なら `nil`（`frame` を送らない）。
    func complete(_ ticket: Ticket) -> Int? {
        state.withLock { snapshot in
            guard ticket.generation == snapshot.generation,
                  snapshot.inFlight.remove(ticket.slot) != nil
            else { return nil }
            snapshot.heldByParent.insert(ticket.slot)
            let seq = snapshot.nextSeq
            snapshot.nextSeq += 1
            return seq
        }
    }

    /// blit を積めなかった（encoder が作れない等）ので slot を空きへ戻す。`seq` は進めない。
    func abandon(_ ticket: Ticket) {
        state.withLock { snapshot in
            guard ticket.generation == snapshot.generation,
                  snapshot.inFlight.remove(ticket.slot) != nil
            else { return }
            snapshot.free.insert(ticket.slot)
        }
    }

    /// 親が読み終えた。範囲外・二重 release・未 complete の slot は無視する（壊れた親に引きずられない）。
    func release(slot: Int) {
        state.withLock { snapshot in
            guard snapshot.heldByParent.remove(slot) != nil else { return }
            snapshot.free.insert(slot)
        }
    }

    /// 新しい world（resize）や切断で全 slot を空きに戻し、世代を進める。
    /// 進行中の blit は完了時に `nil` を受け取る。`seq` は接続内で単調なので戻さない。
    func reset() {
        state.withLock { snapshot in
            snapshot.free = Set(0..<slots)
            snapshot.inFlight = []
            snapshot.heldByParent = []
            snapshot.generation += 1
        }
    }

    var snapshot: Snapshot {
        state.withLock { $0 }
    }
}
