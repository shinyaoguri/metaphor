import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// 「定常フレーム」とみなすまでに描くフレーム数。
///
/// #327 の実測と同じ 3 フレーム。1 フレーム目は経路ごとの初期化（`background()` が
/// クリアに載るか全画面クワッドになるか等）が絵に出うるため、2 フレーム目以降が定常。
/// `@Test(arguments:)` と同じくファイルスコープに置く（`@MainActor` な Suite の
/// static は nonisolated な文脈から参照できない）。
private let steadyStateFrames = 3

/// コマンド記録 ON/OFF の全画素パリティ（Issue #375）。
///
/// ADR-0003 Amendment（2026-08-02, #327 / PR #372）は「コマンド記録の既定 ON 化は
/// 見送り」を確定したうえで、次を **1.0 の確定仕様**として宣言した:
///
/// > 影オン／opt-in と影オフ既定で、定常フレームの描画結果は同一である。
///
/// 判断時に実測（7 シーンで `differingPixels = 0`）はしているが、その検証は
/// 使い捨てコードで行われリポジトリに残っていなかった。ADR の保証として宣言した以上
/// CI で守られていなければ意味がないので、ここで常設する。
///
/// ## 何が守られるか
///
/// 即時経路（`draw()` がメインエンコーダーへ直接エンコード）と記録経路
/// （`draw()` をエンコーダー無しで走らせて 2D/3D を別ストリームへ溜め、
/// `DrawStreamMerge.mergeOrder` で呼び出し順の 1 本へマージしてから再生）が、
/// **同じ画素**を出すこと。したがって
///
/// - `SketchContext.replayDeferredMain` の順序マージ
/// - `Deferred2DCommand` / `Deferred2DSlot`（記録した 2D コマンドとそのパイプライン）
/// - `Canvas3D` の `recordedDrawCalls` と再生時の状態スナップショット（#201）
///
/// のいずれかが壊れると、`interleaved-2d-3d` を筆頭にここが赤くなる。
///
/// ## 比較方式
///
/// ゴールデン照合と違い**閾値を置かない**（`GoldenComparison.isIdentical`）。
/// 環境差を許容する必要があるゴールデンと違って、ここは同一プロセス・同一 GPU で
/// 同じ絵を 2 通りの経路から出す比較なので、1 ビットの差も経路差そのものを意味する。
///
/// シーン定義は ``GoldenScenes``、ハーネスは ``OffscreenSketchHarness`` で
/// ``GoldenImageTests`` と共有している。
@Suite("Command Record Parity", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CommandRecordParityTests {

    private static func render(
        _ scene: GoldenScene, mode: MainPassMode, frames: Int
    ) throws -> GoldenImage {
        try OffscreenSketchHarness.render(
            size: scene.size, mode: mode, frames: frames,
            effects: scene.makeEffects(), draw: scene.draw
        )
    }

    /// 定常フレームで記録 OFF / ON が bit-identical であること（ADR-0003 Amendment の保証）。
    @Test("定常フレームで記録 OFF/ON が 1 ビットも違わない", arguments: commandRecordParitySceneNames)
    func steadyStateParity(name: String) throws {
        let scene = try GoldenScenes.scene(named: name)
        let off = try Self.render(scene, mode: .immediate, frames: steadyStateFrames)
        let on = try Self.render(scene, mode: .commandRecord, frames: steadyStateFrames)

        let diff = off.compare(to: on)
        guard !diff.isIdentical else { return }

        // 失敗したときだけ対照（OFF↔OFF / ON↔ON）を取る。「経路差」なのか
        // 「そもそも非決定論」なのかを、再現の手間なく失敗メッセージだけで切り分けるため。
        let offAgain = try Self.render(scene, mode: .immediate, frames: steadyStateFrames)
        let onAgain = try Self.render(scene, mode: .commandRecord, frames: steadyStateFrames)
        Issue.record(
            """
            シーン '\(scene.name)': 記録 OFF/ON で定常フレーム（\(steadyStateFrames) フレーム描画後）の画素が一致しない。
            ADR-0003 Amendment が 1.0 の確定仕様として宣言した「影オン／opt-in と影オフ既定で、
            定常フレームの描画結果は同一である」に反する。
            OFF vs ON      : \(diff.summary)
            対照 OFF vs OFF: \(off.compare(to: offAgain).summary)
            対照 ON  vs ON : \(on.compare(to: onAgain).summary)
            """
        )
    }

    /// 1 フレーム目も記録 OFF / ON で一致すること。
    ///
    /// もともと初回フレームだけは縁 1px が食い違っていた（#373。記録経路とは独立した
    /// 2D 側の不具合で、影オフ経路の全画面クワッドがカバレッジ不足だった）ため、
    /// #375 の当初計画では 1 フレーム目を比較対象から外す予定だった。#373 は
    /// 2026-08-11 に修正済みなので、ここでは 1 フレーム目も含めて固定する。
    ///
    /// 単一フレームのキャプチャ（`noLoop` / Probe snapshot）はこの経路差の上に乗るため、
    /// 定常フレームだけでなく初回フレームの一致にも実用上の意味がある。全シーンで
    /// 見ると 2 倍のレンダリングになるので、記録経路の検出力がもっとも高い
    /// `interleaved-2d-3d` に絞る（2D 単独の初回フレームは
    /// ``GoldenImageTests/singleFrameMatchesRecordedPath`` が影オン経路で押さえている）。
    @Test("初回フレームでも記録 OFF/ON が 1 ビットも違わない")
    func firstFrameParity() throws {
        let scene = try GoldenScenes.scene(named: "interleaved-2d-3d")
        let off = try Self.render(scene, mode: .immediate, frames: 1)
        let on = try Self.render(scene, mode: .commandRecord, frames: 1)

        let diff = off.compare(to: on)
        #expect(diff.isIdentical, "初回フレームの記録 OFF/ON が一致しない: \(diff.summary)")
    }

    // NOTE: 記録経路のもう一方の入り口である**影オン**（`shadowMap != nil`）は、ここでは
    // 即時経路と突き合わせない。影を有効にすると影そのものが絵を変えるため、
    // 「一致するはず」と言えるのは影が可視でないシーンに限られ、テストとして安定しない
    // （ADR-0003 Amendment の Decision 3 は 2 つの入り口をひとまとめに書いているが、
    // §2 の実測は opt-in 側で採られている）。影オン経路と即時経路の一致は、影の影響を
    // 受けない 2D シーンで `GoldenImageTests.singleFrameMatchesRecordedPath` が押さえている。
}
