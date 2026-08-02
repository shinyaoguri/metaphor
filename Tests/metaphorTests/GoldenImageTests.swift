import Foundation
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// ゴールデンの標準解像度。小さいほど速く、退行の検出力は十分に残る。
///
/// `@MainActor` なスイート内の `static let` は既定引数から参照できないため、
/// ファイルスコープに置く。
private let goldenImageSize = 128

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

    // MARK: - レンダリングハーネス

    /// 実スケッチ（`SketchRunner`）と同じ結線でオフスクリーン 1 フレームを描き、
    /// フレームバッファ全体を読み戻す。
    ///
    /// - Parameters:
    ///   - shadows: true なら記録 → shadow → 再生の影オン経路（ADR-0002 フェーズ 3）を通す。
    ///   - effects: 空でなければ、描画後のカラーテクスチャへポストプロセスを適用した結果を返す。
    private func render(
        size: Int = goldenImageSize,
        shadows: Bool = false,
        effects: [any PostEffect] = [],
        draw: @escaping (SketchContext) -> Void
    ) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: size, height: size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        // SketchRunner と同じ配線（DeterminismTests のハーネスと同型）。
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        // 時間依存を排除するため time/deltaTime は常に 0 を渡す（決定論の前提）。
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.onAfterDraw = { commandBuffer in
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
        renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
        renderer.onRecordFrame = { _ in
            context.beginRecordingFrame(time: 0, deltaTime: 0)
            draw(context)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, _ in
            context.replayDeferredMain(encoder: encoder, time: 0)
        }
        renderer.useExternalRenderLoop = true

        if shadows { context.enableShadows(resolution: 512) }
        renderer.renderFrame()

        var output: MTLTexture = renderer.textureManager.colorTexture
        if !effects.isEmpty {
            // renderer.setPostEffects() 経由だと結果が private な lastOutputTexture に
            // 入って読めないため、パイプラインを直接駆動して出力テクスチャを受け取る。
            let pipeline = try #require(renderer.postProcessPipeline)
            pipeline.set(effects)
            let cb = try #require(renderer.commandQueue.makeCommandBuffer())
            output = pipeline.apply(source: output, commandBuffer: cb)
            try MetalTestHelper.commit(cb)
        }
        return try GoldenImage.readback(texture: output, commandQueue: renderer.commandQueue)
    }

    /// 1 シーンぶんの検証: 決定論（2 回描いてハッシュ一致）+ ゴールデン照合。
    ///
    /// 2 回描くコストはハーネス生成込みでも軽く、「非決定論なのかゴールデンが古いのか」を
    /// 失敗メッセージだけで切り分けられる価値の方が大きい。
    private func verifyScene(
        _ name: String,
        size: Int = goldenImageSize,
        shadows: Bool = false,
        tolerance: GoldenTolerance = .default,
        effects: @autoclosure () -> [any PostEffect] = [],
        draw: @escaping (SketchContext) -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let first = try render(size: size, shadows: shadows, effects: effects(), draw: draw)
        let second = try render(size: size, shadows: shadows, effects: effects(), draw: draw)

        // CI と手元でハッシュを突き合わせられるよう、必ずログに残す。
        print("[golden] \(name) \(size)x\(size) sha256=\(first.sha256)")

        if first.sha256 != second.sha256 {
            let drift = first.compare(to: second)
            Issue.record(
                """
                シーン '\(name)' が同一環境で再現しない（非決定論）。
                \(drift.summary)
                1回目 sha256=\(first.sha256) / 2回目 sha256=\(second.sha256)
                """,
                sourceLocation: sourceLocation
            )
        }

        try GoldenImageStore.verify(
            first,
            name: name,
            in: Self.goldenDirectory,
            tolerance: tolerance,
            sourceLocation: sourceLocation
        )
    }

    // MARK: - 代表シーン

    @Test("ゴールデン: 2D 図形（矩形・円・三角形・円弧・線）")
    func shapes2D() throws {
        try verifyScene("shapes-2d") { c in
            c.background(Color(r: 0.08, g: 0.09, b: 0.12))
            c.noStroke()
            c.fill(Color(r: 0.90, g: 0.30, b: 0.25))
            c.rect(10, 10, 44, 30)
            c.fill(Color(r: 0.20, g: 0.70, b: 0.90))
            c.circle(92, 30, 40)
            c.fill(Color(r: 0.95, g: 0.80, b: 0.20))
            c.triangle(20, 118, 60, 62, 100, 118)
            c.noFill()
            c.stroke(Color(r: 1, g: 1, b: 1))
            c.strokeWeight(3)
            c.arc(64, 64, 90, 90, 0, Float.pi)
            c.stroke(Color(r: 0.35, g: 1.0, b: 0.55))
            c.strokeWeight(1)
            c.line(4, 64, 124, 64)
        }
    }

    @Test("ゴールデン: ブレンドモード（additive / multiply / screen / alpha）")
    func blendModes() throws {
        try verifyScene("blend-modes") { c in
            c.background(Color(r: 0.10, g: 0.10, b: 0.12))
            c.noStroke()
            c.fill(Color(r: 0.55, g: 0.20, b: 0.20))
            c.rect(0, 0, 128, 128)

            c.blendMode(.additive)
            c.fill(Color(r: 0.30, g: 0.30, b: 0.60))
            c.rect(8, 8, 56, 56)

            c.blendMode(.multiply)
            c.fill(Color(r: 0.90, g: 0.90, b: 0.30))
            c.rect(64, 8, 56, 56)

            c.blendMode(.screen)
            c.fill(Color(r: 0.20, g: 0.60, b: 0.30))
            c.rect(8, 64, 56, 56)

            c.blendMode(.alpha)
            c.fill(Color(r: 1, g: 1, b: 1, a: 0.5))
            c.rect(64, 64, 56, 56)
        }
    }

    @Test("ゴールデン: 3D ライティング（Blinn-Phong）")
    func lightingBlinnPhong() throws {
        try verifyScene("lighting-blinn-phong", tolerance: .shaded) { c in
            c.background(Color(r: 0.05, g: 0.05, b: 0.10))
            c.pbr(false)
            // カメラ（-z 方向を向く）側から当てて前面を照らす。真下からの光だと
            // 可視面がほぼ環境光だけになり、ゴールデンの識別力が落ちる。
            c.ambientLight(0.35)
            c.directionalLight(-0.4, -0.5, -1)
            c.specular(0.9)
            c.shininess(48)
            c.fill(Color(r: 0.85, g: 0.55, b: 0.25))
            c.pushMatrix()
            c.translate(64, 64, 0)
            c.rotateY(0.6)
            c.rotateX(0.35)
            c.box(58)
            c.popMatrix()
        }
    }

    @Test("ゴールデン: 3D ライティング（PBR）")
    func lightingPBR() throws {
        try verifyScene("lighting-pbr", tolerance: .shaded) { c in
            c.background(Color(r: 0.03, g: 0.03, b: 0.05))
            c.pbr(true)
            // 環境マップを持たないため metallic を上げすぎると真っ黒になる。
            // 拡散と鏡面が両方見える範囲に収める（ゴールデンの識別力を確保）。
            c.metallic(0.25)
            c.roughness(0.45)
            c.ambientLight(0.75)
            c.directionalLight(-0.4, -0.5, -1)
            c.pointLight(30, 20, 140, color: Color(r: 1.0, g: 0.8, b: 0.6))
            c.fill(Color(r: 0.75, g: 0.75, b: 0.80))
            c.pushMatrix()
            c.translate(64, 64, 0)
            c.sphere(40, detail: 24)
            c.popMatrix()
        }
    }

    @Test("ゴールデン: シャドウマッピング（記録→shadow→再生 経路）")
    func shadowCast() throws {
        try verifyScene("shadow-cast", shadows: true, tolerance: .shaded) { c in
            c.background(Color(r: 0.08, g: 0.08, b: 0.12))
            // 既定カメラは -z 方向を向くので、影の受け手は「床」ではなく
            // 背面の壁にする（床だと厚みの側面しか映らず影が見えない）。
            // 光もカメラ寄りから当てる: 真上からの平行光は影オン経路で
            // シーン全体が自己遮蔽して真っ黒になる（Issue #364 に記録）。
            c.ambientLight(0.35)
            c.directionalLight(-0.4, -0.5, -1)
            c.noStroke()
            c.fill(Color(r: 0.85, g: 0.85, b: 0.88))
            c.pushMatrix()
            c.translate(64, 64, -60)
            c.box(124, 124, 6)                 // 影を受ける背面の壁
            c.popMatrix()
            c.fill(Color(r: 0.90, g: 0.40, b: 0.30))
            c.pushMatrix()
            c.translate(58, 58, 20)
            c.rotateY(0.5)
            c.box(34)                          // 影を落とす箱
            c.popMatrix()
        }
    }

    @Test("ゴールデン: ポストプロセス（Grayscale → Vignette）")
    func postProcess() throws {
        try verifyScene(
            "post-process",
            tolerance: .shaded,
            effects: [GrayscaleEffect(), VignetteEffect(intensity: 0.6, smoothness: 0.4)]
        ) { c in
            c.background(Color(r: 0.10, g: 0.12, b: 0.20))
            c.noStroke()
            c.fill(Color(r: 0.95, g: 0.35, b: 0.20))
            c.circle(48, 48, 60)
            c.fill(Color(r: 0.20, g: 0.80, b: 0.95))
            c.rect(60, 60, 56, 44)
        }
    }

    /// 2D 変換（`translate`/`rotate`/`scale` の 2D 側オーバーロード）が 3D 描画にも
    /// 効くこと（ADR-0005 Amendment 2026-08-02 の P3D 意味論統一）を画素で凍結する。
    ///
    /// 既存の 3D シーンはすべて 3 引数 `translate` を使っているため、統一前後で
    /// 1 画素も動かなかった。**このシーンだけが変換ファミリの適用先に検出力を持つ**
    /// （Issue #325 / #385）。統一を戻すと 3 つのボックスがすべてワールド原点
    /// （= 左上）へ集まり、画像が壊れる。
    @Test("ゴールデン: 2D 変換 + 3D 描画（P3D 意味論統一の検出用）")
    func transform2DAppliedTo3D() throws {
        try verifyScene("transform-2d-on-3d", tolerance: .shaded) { c in
            c.background(Color(r: 0.06, g: 0.07, b: 0.10))
            c.pbr(false)
            c.ambientLight(0.45)
            c.directionalLight(-0.4, -0.5, -1)
            c.noStroke()

            // 1) translate(x, y): 中央寄せしてから箱を置く（P3D 移植の最頻出イディオム）。
            c.pushMatrix()
            c.fill(Color(r: 0.90, g: 0.40, b: 0.30))
            c.translate(40, 44)
            c.box(30)
            c.popMatrix()

            // 2) translate + rotate(a): 2D の rotate が 3D では z 軸回転になる。
            c.pushMatrix()
            c.fill(Color(r: 0.30, g: 0.75, b: 0.90))
            c.translate(92, 40)
            c.rotate(0.6)
            c.box(34, 16, 16)
            c.popMatrix()

            // 3) translate + scale(sx, sy): 非均一スケールが z 等倍で効く。
            c.pushMatrix()
            c.fill(Color(r: 0.95, g: 0.82, b: 0.25))
            c.translate(64, 98)
            c.scale(1.6, 0.6)
            c.box(28)
            c.popMatrix()
        }
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
