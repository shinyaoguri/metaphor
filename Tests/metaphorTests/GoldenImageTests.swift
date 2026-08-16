import Foundation
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// ゴールデンイメージ回帰（Issue #330）。
///
/// #70 / ADR-0002 で決定論レンダリング（同一入力 → 同一スナップショット）は保証済みだが、
/// `DeterminismTests` の比較は**中心 1 ピクセル**だけだった。ここではフレームバッファ
/// **全体**を対象に
///
/// 1. 同一環境で 2 回レンダリングして SHA256 が一致すること（決定論の全画素版）
/// 2. リポジトリにコミットされたゴールデン PNG と一致すること（見た目の回帰検知）
///
/// を代表シーンごとに固定する。ゴールデンの更新手順は
/// `docs/ai/README.md`「ゴールデンイメージ回帰」を参照。
///
/// シーンの定義は ``GoldenScenes``、レンダリングハーネスは ``OffscreenSketchHarness``
/// にあり、どちらもコマンド記録パリティ（``CommandRecordParityTests``）と共有している。
///
/// ## 比較方式について
///
/// ゴールデン照合は**閾値つきピクセル比較**（``GoldenTolerance``）で行う。SHA256 は
/// 「同一環境での再現性」を測るためだけに使い、ゴールデンの合否判定には使わない。
///
/// 実測（Issue #330）では CI の macOS ランナーと手元の Apple Silicon で 6 シーン中
/// 5 シーンがバイト単位で一致し、PBR シーンだけが 16384 画素中 1 画素・1/255 ずれた。
/// つまり環境差はごく小さいが、**1 画素でもズレたらハッシュは不一致**になる。
/// ハッシュ完全一致を合否条件にすると環境ごとにゴールデンを持つしかなくなり、
/// 意図した見た目変更のたびに全環境ぶんの更新が必要になって保守が破綻する。
@Suite("Golden Image Regression", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GoldenImageTests {

    /// ゴールデン PNG の置き場（ソースツリー内）。
    ///
    /// テストリソースとして bundle 経由で読むのではなくソースパスを直接見る。
    /// `METAPHOR_UPDATE_GOLDEN=1` での更新が「その場で書き戻すだけ」で済み、
    /// 差分が `git diff` にそのまま出るため。
    static let goldenDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden", isDirectory: true)

    // MARK: - 代表シーン

    /// 1 シーンぶんの検証: 決定論（2 回描いてハッシュ一致）+ ゴールデン照合。
    ///
    /// 2 回描くコストはハーネス生成込みでも軽く、「非決定論なのかゴールデンが古いのか」を
    /// 失敗メッセージだけで切り分けられる価値の方が大きい。
    @Test("ゴールデン照合", arguments: goldenSceneNames)
    func goldenScene(name: String) throws {
        let scene = try GoldenScenes.scene(named: name)
        let first = try OffscreenSketchHarness.render(
            size: scene.size, mode: scene.goldenMode,
            effects: scene.makeEffects(), draw: scene.draw
        )
        let second = try OffscreenSketchHarness.render(
            size: scene.size, mode: scene.goldenMode,
            effects: scene.makeEffects(), draw: scene.draw
        )

        // CI と手元でハッシュを突き合わせられるよう、必ずログに残す。
        print("[golden] \(scene.name) \(scene.size)x\(scene.size) sha256=\(first.sha256)")

        if first.sha256 != second.sha256 {
            let drift = first.compare(to: second)
            Issue.record(
                """
                シーン '\(scene.name)' が同一環境で再現しない（非決定論）。
                \(drift.summary)
                1回目 sha256=\(first.sha256) / 2回目 sha256=\(second.sha256)
                """
            )
        }

        try GoldenImageStore.verify(
            first, name: scene.name, in: Self.goldenDirectory, tolerance: scene.tolerance
        )
    }

    /// カタログに足したシーンを名前リストへ書き忘れると、そのシーンは**どのテストからも
    /// 呼ばれない**まま緑になる。名前リストとカタログの対応をここで固定する。
    @Test("シーン名リストがカタログを網羅している")
    func sceneNameListsCoverCatalog() {
        let catalog = Set(GoldenScenes.all.map(\.name))
        let referenced = Set(goldenSceneNames).union(commandRecordParitySceneNames)
        #expect(referenced.subtracting(catalog).isEmpty, "カタログに無いシーン名がある")
        #expect(catalog.subtracting(referenced).isEmpty, "どのテストからも参照されないシーンがある")
        #expect(Set(goldenSceneNames).count == goldenSceneNames.count, "ゴールデン名が重複している")
    }

    /// 影オフ（既定）経路と記録経路が、**1 フレーム描画**で同じ画素を出す（Issue #373）。
    ///
    /// 記録経路は `draw()` がメインエンコーダー生成**前**に走るので `background()` が
    /// 同一フレームの `loadAction = .clear` に載る。影オフ経路は初回フレームだけ
    /// 全画面クワッドで塗る。#327 の全画素比較では 3 フレーム描画後は 1 ビットも
    /// 違わないのに、1 フレームだけだと上端 1 行・左端 1 列が食い違っていた
    /// （影オフ側がクワッドのカバレッジ不足で半輝度）。
    ///
    /// 単一フレームのキャプチャ（`noLoop` / Probe snapshot）はこの経路差の上に乗るため、
    /// 「どちらの経路で描いても 1 フレーム目が一致する」ことを画素で固定する。
    @Test("1 フレーム描画で影オフ経路と記録経路が一致する")
    func singleFrameMatchesRecordedPath() throws {
        let scene: (SketchContext) -> Void = { c in
            c.background(Color(r: 0.08, g: 0.09, b: 0.12))
            c.noStroke()
            c.fill(Color(r: 0.90, g: 0.30, b: 0.25))
            c.rect(10, 10, 44, 30)
            c.fill(Color(r: 0.20, g: 0.70, b: 0.90))
            c.circle(92, 30, 40)
        }
        let immediate = try OffscreenSketchHarness.render(
            size: goldenImageSize, mode: .immediate, draw: scene
        )
        let recorded = try OffscreenSketchHarness.render(
            size: goldenImageSize, mode: .shadows, draw: scene
        )

        let diff = immediate.compare(to: recorded)
        #expect(diff.isIdentical, "\(diff.summary)")
    }

    // NOTE: テキストレンダリングのゴールデンは意図的に持たない。
    // グリフのラスタライズは OS のフォントスタック（Core Text のヒンティング・
    // フォント差し替え）に依存し、macOS のマイナー更新でも画素が変わり得るため、
    // 「ライブラリの退行」と「OS 更新」を区別できない。テキストは
    // `GlyphAtlasTests` / `DrawingTests` の構造的な検証に委ねる。

    // MARK: - 基盤そのもののテスト

    /// PNG の往復（保存 → 読み込み）が 1 バイトも変えないこと。
    ///
    /// ゴールデンを PNG で持つ以上、往復が非可逆なら比較の土台が崩れる。
    /// 書き込み・読み込みとも DeviceRGB で統一していることをここで固定する。
    @Test("PNG ラウンドトリップが画素を変えない")
    func pngRoundTripIsLossless() throws {
        let w = 37, h = 23  // 4 の倍数でない幅 = 行パディングの取り違えも検出する
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                bytes[i + 0] = UInt8((x * 7 + y * 3) % 256)
                bytes[i + 1] = UInt8((x * 13 + y * 29) % 256)
                bytes[i + 2] = UInt8((x &* y) % 256)
                bytes[i + 3] = 255
            }
        }
        let original = try GoldenImage(width: w, height: h, rgba: bytes)

        try TempFileHelper.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("roundtrip.png")
            try original.write(pngTo: url)
            let reloaded = try GoldenImage.load(pngAt: url)

            #expect(reloaded.width == w && reloaded.height == h)
            #expect(reloaded.rgba == original.rgba, "PNG 往復で画素が変化した")
            #expect(reloaded.sha256 == original.sha256)
        }
    }

    /// **半透明の画素も** PNG 往復で 1 バイトも変わらないこと（#850）。
    ///
    /// 以前は `rgba`（straight）を `premultipliedLast` と宣言して書いていたため、
    /// ImageIO が PNG（straight）へ書くときに α で割って飽和させ、
    /// **α=128 の白で 127 もずれて**いた。「非不透明画素は再現しない」という
    /// ゴールデンの前提はこの取り違えから来ていたので、往復が可逆であることを
    /// α の全域で固定する。
    @Test("PNG ラウンドトリップが半透明の画素も変えない")
    func pngRoundTripPreservesTranslucentPixels() throws {
        let alphas: [UInt8] = [0, 1, 4, 16, 64, 128, 192, 254, 255]
        let colors: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255), (128, 128, 128), (51, 204, 102), (255, 0, 0), (0, 0, 0),
        ]
        var bytes: [UInt8] = []
        for a in alphas {
            for c in colors {
                bytes.append(contentsOf: [c.0, c.1, c.2, a])
            }
        }
        let original = try GoldenImage(width: colors.count, height: alphas.count, rgba: bytes)

        try TempFileHelper.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("roundtrip-alpha.png")
            try original.write(pngTo: url)
            let reloaded = try GoldenImage.load(pngAt: url)

            #expect(reloaded.rgba == original.rgba,
                    "半透明の画素が PNG 往復で変化した — #850")
            #expect(reloaded.sha256 == original.sha256)
        }
    }

    /// 許容差の意味（`maxChannelDiff` を超えた画素の割合で判定する）を固定する。
    @Test("許容差の判定: 微差は通り、局所的な大差は落ちる")
    func toleranceSemantics() throws {
        let w = 16, h = 16
        var base = [UInt8](repeating: 128, count: w * h * 4)
        for i in stride(from: 3, to: base.count, by: 4) { base[i] = 255 }
        let a = try GoldenImage(width: w, height: h, rgba: base)

        // 全画素が 2 だけずれる → 既定の許容差（<=2）内なので超過ゼロ。
        var tinyBytes = base
        for i in stride(from: 0, to: tinyBytes.count, by: 4) {
            tinyBytes[i] = 130; tinyBytes[i + 1] = 126; tinyBytes[i + 2] = 130
        }
        let tiny = try GoldenImage(width: w, height: h, rgba: tinyBytes)
        let tinyResult = a.matches(tiny, tolerance: .default)
        #expect(tinyResult.maxChannelDiff == 2)
        #expect(tinyResult.exceedingPixels == 0, "±2 の量子化揺れは許容されるべき")
        #expect(!tinyResult.isIdentical, "差はあるので完全一致ではない")

        // 1 画素だけ大きくずれる → 既定（超過率 0）では落ちる。
        var spotBytes = base
        spotBytes[0] = 255
        let spot = try GoldenImage(width: w, height: h, rgba: spotBytes)
        let spotResult = a.matches(spot, tolerance: .default)
        #expect(spotResult.exceedingPixels == 1, "127 の差は許容外")
        #expect(spotResult.exceedingRatio > GoldenTolerance.default.maxExceedingRatio)

        // 同一画像同士は完全一致。
        #expect(a.compare(to: a).isIdentical)
        #expect(a.sha256 == (try GoldenImage(width: w, height: h, rgba: base)).sha256)
    }

    /// サイズ違いは「一致」と判定されない（更新漏れで解像度が変わった場合の保険）。
    @Test("サイズ不一致は常に不一致")
    func sizeMismatchNeverMatches() throws {
        let a = try GoldenImage(width: 4, height: 4, rgba: [UInt8](repeating: 255, count: 64))
        let b = try GoldenImage(width: 8, height: 2, rgba: [UInt8](repeating: 255, count: 64))
        let result = a.compare(to: b)
        #expect(!result.sizeMatches)
        #expect(!result.isIdentical)
        #expect(a.diffImage(against: b) == nil)
    }
}
