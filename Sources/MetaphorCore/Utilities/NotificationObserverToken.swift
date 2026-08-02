import Foundation

/// Owns a block-based `NotificationCenter` observer token and unregisters it on
/// deallocation.
///
/// Block-based observers are not auto-removed, so the token has to outlive the
/// registration and be handed back to `NotificationCenter`. Holding it here (rather
/// than in a `@MainActor` property that `deinit` reads) keeps teardown correct under
/// strict concurrency: `deinit` is `nonisolated`, so it cannot touch actor-isolated
/// storage of a non-`Sendable` type.
///
/// `@unchecked Sendable` rationale: the token is stored once, never handed out, and
/// its only use is `NotificationCenter.removeObserver(_:)` — and `NotificationCenter`
/// is documented as thread-safe. There is no mutable state to race on.
///
/// (Internal. `MetaphorAudio` / `MetaphorVideo` carry their own copies because Tier 1
/// modules must not depend on `MetaphorCore`; see Issue #328.)
final class NotificationObserverToken: @unchecked Sendable {
    private let token: any NSObjectProtocol
    private let center: NotificationCenter

    init(_ token: any NSObjectProtocol, center: NotificationCenter = .default) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
