import MetaphorLog
import Testing
@testable import MetaphorPhysics

/// Core 非依存（Tier 1）のモジュールからも共通の診断ログを使えること（Issue #805）。
///
/// 3 関数が `MetaphorCore` の中にあった頃は、Tier 1 から呼ぶと Core への依存が
/// 生まれてしまうため物理的に使えず、`Physics2D.step(_:iterations:)` の
/// 負値ガードは「警告も出せないので無言で返す」実装になっていた。
/// 依存ゼロの `MetaphorLog` ターゲットへ切り出したことで、その制約は無くなった。
@Suite("Log visibility from Tier 1")
struct LogVisibilityTests {

    @Test("診断ログ 3 種は Core 非依存モジュールから呼べる")
    func logFunctionsAreVisibleFromTier1() {
        // 「呼べる」ことの検証はコンパイルが通ること自体。`metaphorWarning`（DEBUG）と
        // `metaphorAlert`（常時）は必ず出力するため、テストログを汚さないよう
        // 参照だけして実行はしない。
        let emitters: [() -> Void] = [
            { metaphorWarning("unused") },
            { metaphorAlert("unused") },
        ]
        #expect(emitters.count == 2)

        // `METAPHOR_DEBUG=1` のときだけ出力するので、こちらは実際に呼んで経路を通す。
        metaphorDiagnostic("#805 Tier 1 visibility check")
    }

    @Test("負の iterations はワールドを進めずに捨てる")
    @MainActor
    func negativeIterationsSkipsStep() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        let before = body.position

        // 警告を出すようになっても「step ごと捨てる」振る舞いは変えない。
        physics.step(1.0 / 60.0, iterations: -1)

        #expect(body.position == before)
    }
}
