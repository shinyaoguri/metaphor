import Metal
import metaphor

// MARK: - Graphics → RenderPassNode アダプタ
//
// `Graphics` は独自のコマンドキューを共有して描画済みテクスチャを保持する。
// その texture を RenderGraph のノード出力として公開するだけの薄いラッパー。
// 実際の描画は draw() の中で `pg.beginDraw()`〜`pg.endDraw()` で行われ、
// このノードの execute は何もしない。
@MainActor
final class GraphicsNode: RenderPassNode {
    let label: String
    let graphics: Graphics
    var output: MTLTexture? { graphics.texture }

    init(label: String, graphics: Graphics) {
        self.label = label
        self.graphics = graphics
    }

    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // Graphics 側で既に描画＆コミット済み。同一キューの commit-order により
        // 後段（EffectPass / MergePass）から正しく読まれる。
    }
}

// MARK: - サンプル本体
//
// レンダーグラフの本領を見せるサンプル。3つの独立したソースに、
// それぞれ別のエフェクトをかけてから2段階でマージする。
//
// ─── なぜ RenderGraph があると嬉しいのか ───────────────────────────────
//
// 通常の Sketch API（`addPostEffect` など）は **画面全体** に対して
// 一律に処理をかける。これはシンプルな反面、以下のようなことが原理的にできない:
//
//   1. 「この要素だけにエフェクトをかけたい」が表現できない。
//      例えば「光源だけ Bloom させたい、UI には Bloom を効かせたくない」は
//      addPostEffect では不可能。Bloom は画面全体の明るい部分すべてに作用する。
//
//   2. 「同じソースを複数の経路で使い回す」ができない。
//      例: 背景シーンを (a) ぼかして遠景に、(b) 鮮明なまま近景に同時に使う、
//      といった枝分かれ処理は、命令的な draw() では書けない。
//
//   3. 「レイヤーごとに合成方法を変える」が局所化できない。
//      .add / .alpha / .multiply / .screen を混ぜて多層構造を作るのは、
//      手続き的に書くと毎回テクスチャと encoder を手動で繋ぐ羽目になる。
//
// RenderGraph は「描画の依存関係」をデータ構造（DAG）として宣言する仕組みで、
// 上の3つを**コードに対する小さな追加**で全部解決する。
// グラフのノードを差し替えるだけでエフェクトのオン/オフ、ルートの組み替えが
// できるので、実験的な制作とも相性がいい。
//
// ─── 構造図 ──────────────────────────────────────────────────────────
//
//   ┌────────────┐    ┌──────────────┐    ┌──────────────┐
//   │  pgStars   │    │   pgScene    │    │  pgOverlay   │
//   │  (星空)    │    │ (背景+図形)  │    │  (光の点)    │
//   └─────┬──────┘    └──────┬───────┘    └──────┬───────┘
//         │                  │                    │
//         ▼                  │                    ▼
//   ┌────────────┐           │             ┌──────────────────┐
//   │ EffectPass │           │             │ EffectPass       │
//   │ (色収差)   │           │             │ (Vignette)       │
//   └─────┬──────┘           │             └────────┬─────────┘
//         │                  │                      │
//         └─► MergePass(.add) ◄─┘                   │
//                    │                              │
//             (背景 + 星)                            │
//                    ▼                              ▼
//                MergePass(.alpha)  ←────  Overlay を上載せ
//                    │
//                    ▼
//                 画面出力
//
// このサンプルでの可視化:
//   - 3つのソースを **完全に独立** して描画している。
//   - Vignette は Overlay だけ、ChromaticAberration は Stars だけにかかる。
//     Scene の青い円にはどちらも作用しない（DAG が要素を分離している証拠）。
//   - 二段マージで **ブレンドモードを使い分けている**。背景と星は加算 (.add)、
//     その上にオーバーレイをアルファ合成 (.alpha) で乗せる。
//
// ─── どんなときに使うか（典型シナリオ）─────────────────────────────────
//
//   • UI / HUD と 3D シーンの分離
//     ゲームやインタラクティブ作品で、3D シーンには色収差や被写界深度を効かせて、
//     UI（スコア、メニュー、字幕）にはまったく効かせたくないケース。
//     UI を別 SourcePass に描いて、3D シーンだけ EffectPass を通す。
//
//   • 多レイヤー合成（Photoshop / After Effects 的なワークフロー）
//     背景 / メイン / 装飾 / グレイン / ビネット のように層を積み、
//     層ごとに別のフィルタをかけ、層ごとに違うブレンドモードで重ねる。
//     コンポジションの構造そのものをコードで宣言できる。
//
//   • ライブ VJ / マルチソース合成
//     カメラ入力、ビデオファイル、ジェネレーティブパターンといった複数ソースを、
//     それぞれ違うエフェクトチェーンを通してから合成する。
//     入力単位でルートを差し替えやすいので、現場での即興にも向く。
//
//   • レンダリング負荷の最適化
//     重いエフェクト（被写界深度、ブルーム）を低解像度のソースパスに限定して、
//     最終合成だけフル解像度で行う、といった解像度別のパイプラインを組める。
//
//   • A/B 比較・パラメータ探索
//     同じソースを2系統に分岐させ、片方にだけ違うエフェクトをかけて並べる。
//     エフェクトの効きや調整値を視覚的に比較しやすい。
//
//   • 反射・屈折・ミニマップなどの「シーン内の別視点」描画
//     反射プローブやミラー、ピクチャー・イン・ピクチャー的なミニマップを
//     独立した SourcePass で描いて、メインに合成する。
//
// 一発の `draw()` で同じことを書こうとすると、テクスチャ管理・パス順序・
// 同期を全部手で組む羽目になる。RenderGraph は **その配線を構造として記述する**
// ためのレイヤーで、増やす・減らす・差し替える操作の単位がノードになる。
@main
final class RenderGraphCompose: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 960, height: 540, title: "RenderGraph Compose")
    }

    // 3つの独立したオフスクリーンキャンバス
    var pgStars: Graphics!
    var pgScene: Graphics!
    var pgOverlay: Graphics!

    func setup() {
        // 1. 3つの Graphics を用意（解像度はメインと同じ）
        let w = Int(width)
        let h = Int(height)
        guard let stars = createGraphics(w, h),
              let scene = createGraphics(w, h),
              let overlay = createGraphics(w, h) else {
            fatalError("createGraphics に失敗")
        }
        pgStars = stars
        pgScene = scene
        pgOverlay = overlay

        // 2. 星空は静的なので setup() で一度だけ描いて固定する。
        //    以降 beginDraw を呼ばなければテクスチャ内容は保持される。
        drawStars()

        // 3. RenderPassNode に変換
        let starsNode = GraphicsNode(label: "stars", graphics: pgStars)
        let sceneNode = GraphicsNode(label: "scene", graphics: pgScene)
        let overlayNode = GraphicsNode(label: "overlay", graphics: pgOverlay)

        // 4. Stars に色収差を適用（単パスシェーダで安全）
        guard let chromaticStars = createEffectPass(
            starsNode,
            effects: [ChromaticAberrationEffect(intensity: 0.012)]
        ) else {
            fatalError("createEffectPass(stars) に失敗")
        }

        // 5. Overlay に強めの Vignette を適用
        //
        // パラメータを強くして、軌道点が画面端に近づくと
        // 明らかに暗くなる/明るくなるのが見えるように。
        //
        // 注: Bloom や大半径 Blur など複数の中間ヒープテクスチャを使う
        // 多パスエフェクトは EffectPass 経由 + Graphics 入力で
        // 描画が崩れる既知の問題があるため、単パスエフェクトのみを使う。
        guard let vignetteOverlay = createEffectPass(
            overlayNode,
            effects: [VignetteEffect(intensity: 0.5, smoothness: 0.5)]
        ) else {
            fatalError("createEffectPass(overlay) に失敗")
        }

        // 6. 一段目マージ: Scene の上に星空を加算（背景レイヤー作成）
        guard let bgWithStars = createMergePass(
            sceneNode, chromaticStars, blend: .add
        ) else {
            fatalError("createMergePass(stars) に失敗")
        }

        // 7. 二段目マージ: 背景レイヤーの上に Overlay を **アルファ合成**
        //
        // .alpha (B over A) を使うことで、Overlay の不透明な点は背景に
        // 「上書き」される。これにより Vignette の明暗変化が点の見た目に
        // ダイレクトに反映され、画面端で点が露骨に暗くなる/中央付近で
        // ひときわ明るく見えるという差がはっきり可視化される。
        // .add のままだと背景に足し込まれるので減光が見えにくい。
        guard let composite = createMergePass(
            bgWithStars, vignetteOverlay, blend: .alpha
        ) else {
            fatalError("createMergePass(overlay) に失敗")
        }

        // 8. グラフをレンダラーに登録
        setRenderGraph(RenderGraph(root: composite))
    }

    func draw() {
        let t = Float(frameCount) * 0.02
        let cx = width * 0.5
        let cy = height * 0.5

        // ======== Scene パス ========
        // 落ち着いた色の背景＋大きな図形。エフェクトはかからない。
        pgScene.beginDraw()
        pgScene.background(20, 28, 50)
        pgScene.noStroke()
        pgScene.fill(80, 120, 220)
        pgScene.circle(cx + cos(t) * 180, cy, 220)
        pgScene.fill(255, 255, 255, 60)
        pgScene.rect(0, cy - 2, width, 4)
        pgScene.endDraw()

        // ======== Overlay パス ========
        // 透明背景の上に小さな高輝度点を配置。Vignette で周辺減光される。
        pgOverlay.beginDraw()
        pgOverlay.background(0, 0, 0, 0)
        pgOverlay.noStroke()
        pgOverlay.fill(255, 240, 120)
        // 軌道は広めにとって、画面端まで届くようにする。
        // Vignette で外周は明らかに暗く、中央付近は明るく見える。
        let count = 6
        for i in 0..<count {
            let a = t * 1.4 + Float(i) * (.pi * 2 / Float(count))
            let r: Float = 320
            let x = cx + cos(a) * r
            let y = cy + sin(a) * r * 0.55
            pgOverlay.circle(x, y, 26)
        }
        // 中央のひときわ明るい点（Vignette のピーク = 100% で見える）
        pgOverlay.fill(255, 255, 255)
        pgOverlay.circle(cx, cy, 16)
        pgOverlay.endDraw()

        // 星空 (pgStars) は静的なので毎フレーム描き直さない。
        // メインの draw() の出力は RenderGraph に置き換わるため、
        // ここで何か描いても画面には出ない。
    }

    // MARK: - 星空（静的・setup() で一度だけ描画）

    /// 決定論的なハッシュ。同じ index に対して常に同じ値を返す。
    private func hash(_ i: Int, _ k: Int) -> Float {
        let v = sin(Float(i) * 12.9898 + Float(k) * 78.233) * 43758.5453
        return v - floor(v)
    }

    private func drawStars() {
        pgStars.beginDraw()
        pgStars.background(0)
        pgStars.noStroke()
        let count = 90
        for i in 0..<count {
            let x = hash(i, 0) * width
            let y = hash(i, 1) * height
            let s = 1.0 + hash(i, 2) * 2.5
            // ばらつかせた明るさ。一部だけ強めに光らせる
            let bright = 140 + hash(i, 3) * 115
            pgStars.fill(bright, bright, bright)
            pgStars.circle(x, y, s)
        }
        pgStars.endDraw()
    }
}
