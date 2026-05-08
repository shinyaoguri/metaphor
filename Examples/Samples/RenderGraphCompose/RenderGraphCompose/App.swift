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
// レンダーグラフの典型的な使い方を示すサンプル。
//
//   ┌──────────────┐                  ┌──────────────┐
//   │  pgScene     │                  │  pgOverlay   │
//   │ (背景+図形)  │                  │ (発光する点) │
//   └──────┬───────┘                  └──────┬───────┘
//          │                                  │
//          │                                  ▼
//          │                          ┌───────────────┐
//          │                          │ EffectPass    │
//          │                          │ (BloomEffect) │
//          │                          └──────┬────────┘
//          │                                  │
//          ▼                                  ▼
//          ┌──────────────────────────────────┐
//          │      MergePass (.add)            │
//          └──────────────┬───────────────────┘
//                         ▼
//                      画面出力
//
// 重要なポイント:
//   - 二つのシーンを **独立して** 描画している（Graphics A / B）。
//   - Bloom は Overlay にだけかかる（Scene の青い円には bloom が乗らない）。
//   - Merge ノードで二つを合成する。
//   - これらを「コードでグラフとして宣言」しているのが RenderGraph の本体。
//     一発の `draw()` でやろうとすると post-process は画面全体に作用してしまい、
//     「この要素だけぼかす」「この要素はそのまま」が表現できない。
@main
final class RenderGraphCompose: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 960, height: 540, title: "RenderGraph Compose")
    }

    // 二つの独立したオフスクリーンキャンバス
    var pgScene: Graphics!
    var pgOverlay: Graphics!

    func setup() {
        // 1. 二つの Graphics を用意（解像度はメインと同じ）
        let w = Int(width)
        let h = Int(height)
        guard let scene = createGraphics(w, h),
              let overlay = createGraphics(w, h) else {
            fatalError("createGraphics に失敗")
        }
        pgScene = scene
        pgOverlay = overlay

        // 2. それぞれを RenderPassNode に変換
        let sceneNode = GraphicsNode(label: "scene", graphics: pgScene)
        let overlayNode = GraphicsNode(label: "overlay", graphics: pgOverlay)

        // 3. Overlay にだけブルームを適用
        guard let bloomedOverlay = createEffectPass(
            overlayNode,
            effects: [BloomEffect(intensity: 1.6, threshold: 0.4)]
        ) else {
            fatalError("createEffectPass に失敗")
        }

        // 4. Scene と (bloomed) Overlay を加算合成
        guard let composite = createMergePass(
            sceneNode, bloomedOverlay, blend: .add
        ) else {
            fatalError("createMergePass に失敗")
        }

        // 5. グラフをレンダラーに登録
        setRenderGraph(RenderGraph(root: composite))
    }

    func draw() {
        let t = Float(frameCount) * 0.02
        let cx = width * 0.5
        let cy = height * 0.5

        // ======== Scene パス ========
        // 落ち着いた色の背景＋大きな図形。bloom はかからないので
        // どれだけ明るくしても周囲が光らない。
        pgScene.beginDraw()
        pgScene.background(20, 28, 50)
        pgScene.noStroke()
        pgScene.fill(80, 120, 220)
        pgScene.circle(cx + cos(t) * 180, cy, 220)
        pgScene.fill(255, 255, 255, 60)
        pgScene.rect(0, cy - 2, width, 4)
        pgScene.endDraw()

        // ======== Overlay パス ========
        // 透明背景の上に小さな高輝度点を配置。EffectPass で
        // この点群にだけブルームがかかる。
        pgOverlay.beginDraw()
        pgOverlay.background(0, 0, 0, 0)
        pgOverlay.noStroke()
        pgOverlay.fill(255, 240, 120)
        let count = 6
        for i in 0..<count {
            let a = t * 1.4 + Float(i) * (.pi * 2 / Float(count))
            let r: Float = 220
            let x = cx + cos(a) * r
            let y = cy + sin(a) * r * 0.4
            pgOverlay.circle(x, y, 22)
        }
        // 中央のひときわ明るい点
        pgOverlay.fill(255, 255, 255)
        pgOverlay.circle(cx, cy, 14)
        pgOverlay.endDraw()

        // メインの draw() の出力は RenderGraph に置き換わるため、
        // ここで何か描いても画面には出ない（あえて何もしない）。
    }
}
