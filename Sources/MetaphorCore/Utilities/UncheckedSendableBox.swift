/// A box that carries a non-`Sendable` value into a `@Sendable` closure or across an
/// `async` boundary.
///
/// Its use is deliberately narrow: reach for it only when **both** of the following
/// hold (Issue #328):
///
/// 1. The handling of the value can be explained as safe by design (a thread-safe type,
///    already serialized on a serial queue, index-partitioned so the written ranges do
///    not overlap, and so on).
/// 2. Neither an `import` nor a design change can suppress the diagnostic. In
///    particular, the compiler of the minimum supported Swift 5.10 (Xcode 15.4)
///    **does not take `nonisolated(unsafe)` on a local variable into account when
///    diagnosing captures in a `@Sendable` closure** (measured: Issue #328), so only a
///    type-level `Sendable` conformance silences it there.
///
/// `@unchecked Sendable` rationale: the box itself is an immutable value type with a
/// single `let` and no mutable state. Its safety depends on **the calling convention at
/// the use site**, so every use must carry a comment stating the rationale.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
