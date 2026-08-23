import Testing
import Foundation
import MetaphorCore
import MetaphorTestSupport

// MARK: - CI 実行環境のガード（Issue #329 / v1-release-plan G5）
//
// GPU 依存のテストは 19 ファイル・数百件が `.enabled(if: MetalTestHelper.isGPUAvailable)`
// でゲートされている。ランナーから Metal が消えるとそれらは「skip」に変わるだけで、
// swift test は 0 件失敗のまま green を返す ＝ 検証が丸ごと蒸発しても誰も気付けない。
//
// そこで「GPU があるはず」の環境（CI）は `METAPHOR_REQUIRE_GPU=1` を宣言し、
// この suite が 2 段で守る:
//
//   1. Metal デバイスの存在（= 大量 skip の握り潰しを防ぐ）
//   2. その GPU が実際に描画結果を返すこと（= 「device はあるが出力が全黒」を防ぐ）
//
// 1 は env が立っている環境でのみ走るため、GPU の無いローカル環境・サンドボックスの
// 挙動は変わらない。2 は GPU があれば手元でも走る常設のカナリアで、
// 「GPU 系テストが軒並み落ちる」ときに原因がランナー側か個別機能かを切り分ける
// （例: Issue #353 のゴールデン系フレークが、環境起因かどうかをここで判別できる）。

@Suite("CI Environment Guard")
@MainActor
struct CIEnvironmentGuardTests {

    /// GPU 必須を宣言している環境でのみ、デバイス不在を失敗として扱う。
    ///
    /// ここが赤いとき、テスト結果全体（特に GPU ゲートされた suite）は信頼できない。
    @Test(
        "METAPHOR_REQUIRE_GPU=1 の環境では Metal デバイスが存在する",
        .enabled(if: ProcessInfo.processInfo.environment["METAPHOR_REQUIRE_GPU"] == "1")
    )
    func metalDeviceMustExistWhenRequired() {
        #expect(
            MetalTestHelper.isGPUAvailable,
            """
            MTLCreateSystemDefaultDevice() が nil を返した。この環境は \
            METAPHOR_REQUIRE_GPU=1 で「GPU あり」と宣言しているため、これは設定ミス \
            （ランナーイメージ / 仮想化設定の変更）である。\
            GPU ゲートされたテストはすべて skip されており、他が green でも \
            レンダリングは一切検証されていない。
            """
        )
    }

    /// GPU があるなら「描いたものが読み戻せる」ところまでを常設で確認するカナリア。
    ///
    /// device の存在だけでは、ソフトウェアフォールバックや壊れたドライバで
    /// 出力が全黒になるケースを捕まえられない。clear と描画の両方を 1 フレームで
    /// 検証し、失敗時のメッセージで「環境が壊れている」ことを明示する。
    @Test(
        "GPU で描いた 1 フレームが読み戻せる（全黒・空フレームの検出）",
        .enabled(if: MetalTestHelper.isGPUAvailable)
    )
    func gpuActuallyProducesPixels() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.rect(8, 8, 16, 16)
        }

        let inside = helper.readPixel(x: 16, y: 16)
        #expect(
            inside.r > 200 && inside.g > 200 && inside.b > 200,
            """
            描画した白い矩形の中心が白く読み戻せない \
            (r=\(inside.r) g=\(inside.g) b=\(inside.b))。GPU パイプラインが \
            出力を生んでいない可能性が高く、この環境のレンダリング結果は信用できない。
            """
        )

        let outside = helper.readPixel(x: 1, y: 1)
        #expect(
            outside.r < 40 && outside.g < 40 && outside.b < 40,
            """
            矩形の外側が clear color（黒）にならない \
            (r=\(outside.r) g=\(outside.g) b=\(outside.b))。clear / blit / readback の \
            いずれかが機能していない。
            """
        )
    }
}
