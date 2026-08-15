---
title: GPU を使う
part: 6
slug: gpu
description: 自分で書いたカーネルで GPU に計算させ、100 万粒を動かし、描き終えた絵に効果をかけます。
draft: false
---

# 第 6 部 GPU を使う

ここまでのスケッチでも GPU は動いていました。`circle()` や `box()` を呼ぶたびに、metaphor が図形を GPU へ送って描かせていたからです。ただし**何を描くかを決めているのは、いつも CPU 側の Swift のコード**でした。

この部では、その分担を動かします。やることは 4 つです。**計算そのものを GPU にさせる**（`compute()`）、**データを CPU に降ろさずに動かし続ける**（GPU パーティクル）、**描き終えた絵にまとめて効果をかける**（ポストプロセス）、**図形をどう塗るかを自分のシェーダーで決める**（2D カスタムシェーダー）。前の 3 つは「1 つずつ Swift で処理していたら間に合わない量」を扱うための道具で、最後の 1 つは「Swift の側では書けない絵」を図形に流し込むための口です。

新しく覚える言語が 1 つあります。**MSL（Metal Shading Language）**です。C++ に似た小さな言語で、GPU 上で動く関数を書きます。この部で書くのは 20 行程度のものだけです。

## この部の前提

第 1 部 1.3 の `setup()` / `draw()` の役割分担と、第 2 部の図形・色・ブレンドの語彙を使います。6.2 は第 3 部 3.9 の CPU パーティクルと対比しながら読むと違いがはっきりします。3D の知識は要りません（座標の考え方だけ第 5 部 5.1 と同じです）。

## 6.1 GPU に計算させる

![GPU が 14400 セルぶん計算したジュリア集合。紫の地に黒い島が広がっている](https://i.gyazo.com/e7815e6f0f7c2cdd05ad6da59bb4b986.png)

キャンバスを 14400 個のセルに区切り、そのすべてについて「ジュリア集合の発散までの回数」を計算しています。計算しているのは GPU で、CPU は返ってきた値で塗り分けているだけです。

### compute() は draw() の前に呼ばれる

`Sketch` には `draw()` のほかに `compute()` というフックがあります。既定は空で、書けばそのフレームの描画の前に呼ばれます。

```swift
func compute() {  // 毎フレーム、draw() の前
    dispatch(kernel, threads: cols * rows) { encoder in ... }
}

func draw() {     // ここは描画専用
    ...
}
```

GPU の計算（コンピュートパス）と描画（レンダーパス）は別のフェーズで、metaphor は両者の間に同期を入れます。`compute()` の中で描画関数を呼んだり、`draw()` の中で `dispatch()` を呼んだりはしません。

### 部品は 3 つ

| 部品 | 作るもの | 役割 |
|---|---|---|
| カーネル | `createComputeKernel(source:function:)` | MSL のソースを実行時にコンパイルする |
| バッファ | `createBuffer(count:type:)` | CPU と GPU が共有するメモリ |
| ディスパッチ | `dispatch(_:threads:configure:)` | スレッドを何本立てて、どのバッファを渡すか |

カーネルは「1 スレッドぶんの仕事」を書いた関数です。`thread_position_in_grid` で自分が何番目のスレッドかを受け取り、その番号のセルだけを計算します。14400 セルなら 14400 本のスレッドが同時に走ります。

```metal
kernel void julia(
    device float *out [[buffer(0)]],           // 書き込み先
    constant FieldParams &p [[buffer(1)]],     // 設定
    uint id [[thread_position_in_grid]]        // 自分の番号
) {
    if (id >= p.cols * p.rows) { return; }     // 端数のスレッドは何もしない
    ...
    out[id] = ...;
}
```

呼ぶ側では、`dispatch()` のクロージャで「何番のスロットに何を渡すか」を指定します。番号は MSL 側の `[[buffer(0)]]` に対応します。

```swift
dispatch(kernel, threads: cols * rows) { encoder in
    encoder.setBuffer(field.buffer, offset: 0, index: 0)
    encoder.setBytes(&params, length: MemoryLayout<FieldParams>.stride, index: 1)
}
```

`encoder` は Metal の型なので、スケッチの先頭に `import Metal` が要ります。

### 構造体は両側で同じ形にする

設定をまとめて渡すときは、Swift と MSL の**両方に同じ構造体を書きます**。フィールドの順番と大きさがずれても、コンパイルは通り、警告も出ません。シェーダーが黙って別の値を読み、絵だけが間違います。

| Swift | MSL |
|---|---|
| `var cols: UInt32` | `uint cols;` |
| `var rows: UInt32` | `uint rows;` |
| `var cx: Float` | `float cx;` |
| `var cy: Float` | `float cy;` |

### 結果が返ってくるのは次のフレーム

`GPUBuffer` は Apple Silicon のユニファイドメモリの上にあるので、CPU からコピー無しで読めます（`buffer[i]` や `contents`、`toArray()`）。ただし**同じフレームのうちには読めません**。

`dispatch()` がしているのは「このフレームのコマンドバッファに命令を積む」ことだけで、GPU が実際に走るのはそのあとです。`draw()` はまだ命令を積んでいる最中なので、そこで読める値は**1 つ前のフレームの結果**です。実際、このスケッチの 1 フレーム目のバッファは全部 0 で、値が入るのは 2 フレーム目からです。

毎フレーム同じ計算を流し続ける使い方（このスケッチもそうです）なら、1 フレームの遅れは見えません。逆に「計算して、その結果をすぐ CPU で使いたい」という書き方は、この経路には向いていません。

### 重いのは GPU ではなく往復

セルを 2 ピクセル角にすると 57600 セルになります。GPU の計算は 4 倍ですが、絵はほとんど変わらないまま **60fps が約 16fps まで落ちます**。落としているのは GPU ではなく、57600 回の `rect()` を積む CPU 側です（試しに計算だけ 57600 セルのままで、描く矩形を 14400 に戻すと 60fps に戻ります）。

つまり、この節の形（GPU で計算 → CPU で読んで描く）は**セルの数だけ CPU の描画が要る**のが上限になります。それを超える量を動かしたいときは、次の節のようにデータを GPU から降ろさないようにします。

<!-- tutorial-snippet: 06-GPU/01-Compute -->
```swift
import Metal
import metaphor

/// カーネルへ渡す設定。Swift と MSL の両方で同じ並び・同じ大きさにします。
/// ここがずれると、シェーダーは何も言わずに別の値を読みます。
struct FieldParams {
    var cols: UInt32
    var rows: UInt32
    var cx: Float
    var cy: Float
}

@main
final class Compute: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Compute")
    }

    // 4 ピクセル角のセルでキャンバスを埋める
    let cols = 160
    let rows = 90

    var kernel: ComputeKernel?
    var field: GPUBuffer<Float>?

    // GPU 側のカーネル。1 スレッドが 1 セルを担当する
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FieldParams {
        uint  cols;
        uint  rows;
        float cx;
        float cy;
    };

    kernel void julia(
        device float *out [[buffer(0)]],
        constant FieldParams &p [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= p.cols * p.rows) { return; }

        // セルの番号を複素平面の座標へ
        float x = (float(id % p.cols) + 0.5) / float(p.cols) * 3.2 - 1.6;
        float y = (float(id / p.cols) + 0.5) / float(p.rows) * 1.8 - 0.9;

        // 発散するまでの回数を数える（ジュリア集合）
        float2 z = float2(x, y);
        const int maxIter = 120;
        int i = 0;
        for (; i < maxIter; i++) {
            z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + float2(p.cx, p.cy);
            if (dot(z, z) > 256.0) { break; }
        }

        if (i == maxIter) {
            out[id] = 1.0;                    // 発散しなかった = 集合の内側
        } else {
            // 回数を小数まで滑らかにする（整数のままだと縞が出る）
            float smooth = float(i) + 1.0 - log2(log2(length(z)));
            out[id] = clamp(smooth / float(maxIter), 0.0, 0.999);
        }
    }
    """

    func setup() {
        kernel = try? createComputeKernel(source: source, function: "julia")
        field = createBuffer(count: cols * rows, type: Float.self)
        noStroke()
    }

    // draw() の前に呼ばれる GPU 計算のフック
    func compute() {
        guard let kernel, let field else { return }

        var params = FieldParams(cols: UInt32(cols), rows: UInt32(rows), cx: -0.70, cy: 0.27)
        dispatch(kernel, threads: cols * rows) { encoder in
            encoder.setBuffer(field.buffer, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<FieldParams>.stride, index: 1)
        }
    }

    func draw() {
        background(12)
        guard let field else { return }

        // GPU が書いた値をそのまま読む（ユニファイドメモリなのでコピーは要らない）
        let values = field.contents
        let cellW = Float(width) / Float(cols)
        let cellH = Float(height) / Float(rows)

        for iy in 0..<rows {
            for ix in 0..<cols {
                let t = values[iy * cols + ix]
                if t >= 1.0 {
                    fill(16, 18, 34)                     // 集合の内側
                } else {
                    let u = pow(t, 0.35)                 // 外側は縁に色を寄せる
                    fill(30 + 225 * u, 20 + 120 * u * u, 90 + 120 * u)
                }
                rect(Float(ix) * cellW, Float(iy) * cellH, cellW, cellH)
            }
        }

        fill(235)
        textSize(13)
        text("GPU が \(cols * rows) セルを並列に計算し、CPU がその値で塗り分けている", 14, 26)
    }
}
```

実行: `cd Examples/Tutorial/06-GPU/01-Compute && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `cx` / `cy` を `(-0.4, 0.6)` や `(0.285, 0.01)` に変えると、形はどう変わりますか
- `cols` / `rows` を倍にすると、絵と滑らかさはどうなりますか。フレームレートはどうですか
- MSL の `FieldParams` から `rows` の行を消す（Swift 側は残す）と、絵はどうなりますか

### ふりかえり

- [ ] `compute()` が `draw()` の前に呼ばれる GPU 計算専用のフックだと分かった
- [ ] カーネル・バッファ・ディスパッチの 3 つが要ると分かった
- [ ] Swift と MSL の構造体は自分でレイアウトを合わせる必要があると分かった
- [ ] `dispatch()` の結果が CPU から読めるのは次のフレームだと分かった
- [ ] セルごとに CPU が描く形では、描画のほうが先に頭打ちになると分かった

### もっと詳しく

- [`compute()`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/compute%28%29), [`createComputeKernel(source:function:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createcomputekernel%28source:function:%29), [`dispatch(_:threads:configure:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/dispatch%28_:threads:configure:%29)
- [`createBuffer(count:type:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createbuffer%28count:type:%29), [`GPUBuffer`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/gpubuffer), [`ComputeKernel`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/computekernel)

## 6.2 GPU パーティクル

![100 万粒のパーティクルが、円形の口から白い渦を巻いて立ちのぼっている](https://i.gyazo.com/90c559db39efb25bc421c9fb6268f601.png)

![100 万粒が円形の口から噴き出し、渦を巻きながら形を変えていく](https://i.gyazo.com/82f241918e6d2e7b9a4b661f08355ed4.webp)

100 万粒が円形の口から立ちのぼっています。第 3 部 3.9 で作った CPU のパーティクルは配列を Swift のループで回していましたが、ここでは**位置も色も GPU の中だけで更新され、CPU には一度も降りてきません**。

### 3 か所に書くだけ

`ParticleSystem` は metaphor が用意した GPU パーティクルです。書く場所は 3 つに分かれます。

```swift
func setup() {
    let ps = try? createParticleSystem(count: 1_000_000)   // 作る
    ...
}

func compute() { updateParticles(system) }                 // 動かす（GPU 計算フェーズ）

func draw()    { drawParticles(system) }                   // 描く（描画フェーズ）
```

`updateParticles()` は 6.1 と同じコンピュートパスに乗り、`drawParticles()` はビルボード（常にカメラを向く板）を加算合成で描きます。どちらも粒 1 つずつを Swift で触ることはありません。

### 座標はピクセル、既定値は小さい

位置は**ワールド座標 = ピクセル座標**です（第 5 部 5.1 と同じ約束です）。y は下向きなので、上へ立ちのぼらせる重力は負の値になります。

ここで一度つまずきます。`ParticleSystem` の既定値は 1 ワールド単位を 1 メートル程度に見立てた値になっていて、**ピクセル空間ではどれも小さすぎます**。

| プロパティ | 既定値 | ピクセル空間での目安 |
|---|---|---|
| `particleSize` | `0.05` | 見えない。1〜4 程度にします |
| `.gravity(0, -9.8, 0)` | — | ほぼ止まって見える。数十〜数百にします |
| `emissionRate` | `10000` | 100 万粒を 3 秒の寿命で満たすなら 33 万 |

放出口と力はそれぞれ 4 種類・6 種類あります。

| エミッター | 力 |
|---|---|
| `.point` / `.line` / `.circle` / `.sphere` | `.gravity` / `.attraction` / `.repulsion` / `.noise` / `.vortex` / `.damping` |

力は足し算で重なります。このスケッチは「上向きの重力 + ノイズ + 減衰」の 3 つで、減衰があるおかげで速度が上限に落ち着き、炎のような形が保たれます。

### 加算合成なので 1 粒は薄く

粒は加算合成で重ねられます。100 万粒を不透明で描くと、重なったところが**すべて白に飽和します**（実際、最初は形の分からない白い塊になりました）。`startColor` のアルファを 0.05 以下まで落とすと、密度がそのまま明るさとして出て、色のグラデーションも見えるようになります。

`useIndirectDraw = true` にすると、生きている粒だけを描きます（既定が `false` なのは後方互換のためです）。

### 引き換えに手放すもの

100 万粒が 60fps で動く代わりに、**個々の粒に手が届きません**。「この粒だけ色を変える」「マウスに当たった粒を消す」といった操作は、`ParticleForce` の組み合わせで表現できる範囲に限られます。粒ごとの判定や寿命の細工が要るなら、3.9 の CPU パーティクルのほうが向いています。

もう 1 つ、**同じ絵を再現できません**。放出の乱数は時刻から作られ、位置は `deltaTime` で積分されるので、実行のたびに細部が変わります。作品として同じ映像を焼き出したい場合は、この節の仕組みではなく決定論的な経路（第 9 部）を選ぶことになります。

<!-- tutorial-snippet: 06-GPU/02-Particles -->
```swift
import metaphor

@main
final class Particles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Particles")
    }

    let count = 1_000_000
    var system: ParticleSystem?

    func setup() {
        guard let ps = try? createParticleSystem(count: count) else { return }

        // 位置はワールド座標 = ピクセル座標。y は下向き
        ps.setEmitter(.circle(x: 320, y: 290, z: 0, radius: 70))
        ps.particleLife = 3.0
        ps.particleSize = 1.5
        ps.emissionRate = Float(count) / ps.particleLife   // 常に埋まる量を出し続ける
        // 加算合成なので 1 粒はごく薄くする（濃いと重なって真っ白に潰れる）
        ps.startColor = SIMD4(1.0, 0.45, 0.12, 0.025)
        ps.endColor = SIMD4(0.30, 0.45, 1.0, 0.0)
        ps.useIndirectDraw = true                          // 生きている粒だけ描く

        ps.addForce(.gravity(0, -55, 0))                   // 上へ（y が下向きなので負）
        ps.addForce(.noise(scale: 0.01, strength: 90))
        ps.addForce(.damping(1.0))

        system = ps
    }

    func compute() {
        guard let system else { return }
        updateParticles(system)                            // 位置の更新は GPU の中だけで完結する
    }

    func draw() {
        background(8, 10, 20)
        guard let system else { return }
        drawParticles(system)

        fill(235)
        textSize(13)
        text("\(count) 粒。位置も色も GPU の中で更新している", 14, 26)
    }
}
```

実行: `cd Examples/Tutorial/06-GPU/02-Particles && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `count` を 10000 に減らすと、見た目はどう変わりますか。`particleSize` を上げて補えますか
- `.noise` を消して `.vortex(x: 320, y: 180, z: 0, strength: 40)` に替えると、流れはどうなりますか
- `startColor` のアルファを 0.3 に上げると、なぜ形が見えなくなりますか

### ふりかえり

- [ ] `updateParticles()` は `compute()`、`drawParticles()` は `draw()` に置くと分かった
- [ ] パーティクルの位置がピクセル座標で、既定値はピクセル空間には小さすぎると分かった
- [ ] エミッターと力の組み合わせで動きを作ると分かった
- [ ] 加算合成なので 1 粒のアルファを小さくすると分かった
- [ ] 粒ごとの細工と再現性を手放す代わりに数を得ていると分かった

### もっと詳しく

- [`createParticleSystem(count:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createparticlesystem%28count:%29), [`updateParticles(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/updateparticles%28_:%29), [`drawParticles(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/drawparticles%28_:%29)
- [`ParticleSystem`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/particlesystem), [`EmitterShape`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/emittershape), [`ParticleForce`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/particleforce)
- [`Demos/Performance/DynamicParticlesImmediate`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Demos/Performance/DynamicParticlesImmediate)（CPU 側で同じ絵を作った場合との比較）

## 6.3 ポストプロセス

![黄色い点の輪と中央の白い点に Bloom と Vignette がかかり、光がにじんで四隅が落ちている](https://i.gyazo.com/d0e134c2855732fac4734defc7b02bce.png)

![同じ絵に、効果無し → Bloom → Bloom + Vignette → Grayscale の 4 通りを順にかけていく](https://i.gyazo.com/5c4727eeab63d554e4b093b5d3743765.webp)

同じ絵に、48 フレームごとに違う効果をかけています。「効果無し」「Bloom」「Bloom + Vignette」「Grayscale」の 4 通りです。

### 描き終えた絵にかける

metaphor は、まずオフスクリーンのテクスチャに 1 フレームを描き切り、それを画面へ転送します。**ポストプロセスはその間に挟まる工程**です。だから `draw()` の中の描画順とは関係なく、**画面に出るものすべて**が対象になります。3D も 2D も、文字も UI も一緒にかかります（実行結果の最後のコマで、ラベルの文字まで灰色になっているのがそれです）。

一部だけにかけたい（光源だけ Bloom、UI には効かせたくない）場合は、この節の API ではなく RenderGraph を使います（[`Samples/RenderGraphCompose`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Samples/RenderGraphCompose)）。

### 組み込みのエフェクト

| エフェクト | 効果 | 主な引数 |
|---|---|---|
| `BloomEffect` | 明るいところをにじませる | `intensity`, `threshold` |
| `BlurEffect` | ぼかす | `radius` |
| `VignetteEffect` | 周辺を暗くする | `intensity`, `smoothness` |
| `ChromaticAberrationEffect` | 色収差（RGB をずらす） | `intensity` |
| `ColorGradeEffect` | 明るさ・コントラスト・彩度・色温度 | `brightness` ほか |
| `GrayscaleEffect` / `InvertEffect` | 灰色化 / 反転 | — |

`BloomEffect` の `threshold` は「どれくらい明るい画素をにじませるか」です。このスケッチでは 0.45 にしてあるので、明るい点だけがにじみ、暗い点はそのまま残ります。

`VignetteEffect` の `intensity` は **0.0 で無効、1.0 で最も強い**という素直な強度です。このスケッチは 0.4 にしてあるので、四隅がうっすら落ちる程度に留まります。

### 並べる、入れ替える

エフェクトは配列として並び、**書いた順に**適用されます。順番が変われば結果も変わります（にじませてから暗くするのと、暗くしてからにじませるのは別物です）。

```swift
addPostEffect(BloomEffect())          // 末尾に足す
setPostEffects([bloom, vignette])     // 丸ごと置き換える
removePostEffect(at: 0)               // 位置を指定して外す
clearPostEffects()                    // 全部外す
```

エフェクトは設定値を持つだけの軽い入れ物なので、このスケッチのように**毎フレーム作り直して差し替えても構いません**。逆に、値だけを動かしたいときはプロパティを持たせて `effect.intensity = ...` と書き換えるほうが素直です。

<!-- tutorial-snippet: 06-GPU/03-PostProcess -->
```swift
import metaphor

@main
final class PostProcess: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PostProcess")
    }

    // 48 フレームごとに 4 通りの重ねがけを切り替える
    let phaseLength = 48

    func setup() {
        noStroke()
    }

    func draw() {
        let phase = (frameCount / phaseLength) % 4

        // エフェクトは毎フレーム丸ごと差し替える（追加ではなく置き換え）
        switch phase {
        case 0:
            setPostEffects([])
        case 1:
            setPostEffects([BloomEffect(intensity: 2.2, threshold: 0.45)])
        case 2:
            setPostEffects([
                BloomEffect(intensity: 2.2, threshold: 0.45),
                VignetteEffect(intensity: 0.4, smoothness: 0.35),
            ])
        default:
            setPostEffects([GrayscaleEffect()])
        }

        background(10, 12, 22)

        // 光の点を円周に並べて回す。明るいところだけ Bloom がにじむ
        let t = Float(frameCount) * 0.02
        for i in 0..<12 {
            let a = t + Float(i) / 12 * TWO_PI
            let x = 320 + cos(a) * 120
            let y = 180 + sin(a) * 90
            fill(255, 210, 120)
            circle(x, y, 14)
            fill(70, 80, 110)                     // 暗い点は Bloom のしきい値に届かない
            circle(320 - cos(a) * 60, 180 - sin(a) * 45, 10)
        }

        fill(255, 255, 255)
        circle(320, 180, 26)

        fill(235)
        textSize(14)
        textAlign(.center)
        text(label(for: phase), 320, 330)
    }

    func label(for phase: Int) -> String {
        switch phase {
        case 0: return "エフェクト無し"
        case 1: return "Bloom"
        case 2: return "Bloom + Vignette"
        default: return "Grayscale（文字も一緒に灰色になる）"
        }
    }
}
```

実行: `cd Examples/Tutorial/06-GPU/03-PostProcess && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `setPostEffects([vignette, bloom])` のように順番を逆にすると、周辺の明るさはどうなりますか
- `BloomEffect` の `threshold` を 0.9 に上げると、どの点がにじまなくなりますか
- `ChromaticAberrationEffect(intensity: 0.01)` を最後に足すと、点の輪郭はどう見えますか

### ふりかえり

- [ ] ポストプロセスが「描き終えた 1 枚」に対する工程だと分かった
- [ ] 画面に出るものすべて（文字や UI も）が対象になると分かった
- [ ] エフェクトは配列で、書いた順に適用されると分かった
- [ ] `BloomEffect` の `threshold` がにじむ明るさの境目だと分かった
- [ ] 一部にだけかけたいときは RenderGraph を使うと分かった

### もっと詳しく

- [`addPostEffect(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/addposteffect%28_:%29), [`setPostEffects(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/setposteffects%28_:%29), [`clearPostEffects()`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/clearposteffects%28%29)
- [`BloomEffect`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/bloomeffect), [`VignetteEffect`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/vignetteeffect), [`PostEffect`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/posteffect)

## 6.4 カスタムポストエフェクト

![自作シェーダーで波打たせた市松模様の上に、オレンジ色の円がひとつ乗っている](https://i.gyazo.com/e042c95161502b815cc24aa8db5d93d5.png)

組み込みのエフェクトで足りないときは、フラグメントシェーダーを自分で書いて同じ列に並べられます。ここでは画面中心からの距離に応じてサンプリング位置をずらし、格子を波打たせています。

### フラグメント関数を書く

`createPostEffect(name:source:fragmentFunction:)` に MSL のソースを渡します。ソースに書くのは**フラグメント関数だけ**です。前文（Metal 標準ライブラリの取り込みと、`PPVertexOut`（頂点シェーダーからの入力）・`PostProcessParams`（組み込みのパラメータ）の定義）は metaphor が**必ず**足します。規約は 1 行で言えます——**足される構造体を自分で定義しない**。

```swift
let source = """
fragment float4 ripple(
    PPVertexOut in [[stage_in]],                       // in.texCoord が 0〜1 の画面座標
    texture2d<float> tex [[texture(0)]],               // 直前までに描き上がった絵
    constant PostProcessParams &params [[buffer(0)]],  // 組み込みのパラメータ
    constant RippleParams &rp [[buffer(1)]]            // 自前のパラメータ
) { ... }
"""
let effect = try createPostEffect(name: "ripple", source: source, fragmentFunction: "ripple")
addPostEffect(effect)
```

受け取れるものは決まっています。

| 場所 | 中身 |
|---|---|
| `texture(0)` | 入力の絵。`in.texCoord` の位置を `sample()` で読む |
| `buffer(0)` | `texelSize`（1 画素の大きさ）と `intensity` / `threshold` / `radius` / `smoothness` |
| `buffer(1)` | `setParameters()` で渡した自前の構造体 |

`intensity` などは `CustomPostEffect` のプロパティとしてそのまま書き込めます（`effect.intensity = 0.006`）。それ以外の値を渡したいときが `setParameters()` の出番で、6.1 と同じく**Swift と MSL でレイアウトを合わせる**必要があります。

```swift
struct RippleParams {          // MSL 側にも同じ並びの struct を書く
    var frequency: Float
    var phase: Float
}
effect.setParameters(RippleParams(frequency: 42, phase: Float(frameCount) * 0.08))
```

`texelSize` は縦横比を戻すのにも使えます。`in.texCoord` は 0〜1 に正規化されていて縦横で尺度が違うため、そのまま距離を測ると楕円になります。

### 書き換えながら試す

シェーダーを書くときは、値を少し変えては絵を見る往復になります。**MSL を別ファイルに置いて `createPostEffectFromFile(name:path:fragmentFunction:)` で読む**と、この往復からビルドが消えます。

```swift
effect = try createPostEffectFromFile(
    name: "ripple", path: "Sources/Ripple/ripple.metal", fragmentFunction: "ripple")
```

読み込んだ `.metal` ファイルは自動で監視されます。**保存するとその場で再コンパイルされ、絵が変わります**——ウィンドウは開いたまま、Swift の再ビルドもありません。同じことが 3D の `createMaterialFromFile()` と、次の 6.5 で扱う 2D の `loadShader()` でも起きます。

書きかけの MSL はコンパイルに落ちますが、そのとき画面は**直前の動くシェーダーのまま**で、エラーだけがコンソールに出ます。直して保存すればそのまま戻ります。

| | 何が要るか |
|---|---|
| ファイルを保存する | 何も要らない（自動リロード） |
| Swift のコードを変えた | `metaphor watch`（保存のたびに再ビルド、ウィンドウは開いたまま） |

自動リロードが働くのは開発中のビルド（`swift run`）だけで、`swift build -c release` で作った配布用のビルドではファイル監視は起きません。切り替えたいときは `SketchConfig(shaderHotReload:)` か、環境変数 `METAPHOR_SHADER_HOT_RELOAD`（`1` で有効・`0` で無効）を使います。

ソース文字列から作った `createPostEffect(name:source:)` にはファイルがないので、この自動リロードは働きません。任意のタイミングで自分で読み直したいときは `reloadShaderFromFile(key:path:)` が残っています（キーは `"user.posteffect.<name>"`）。

<!-- tutorial-snippet: 06-GPU/04-CustomPostEffect -->
```swift
import metaphor

/// シェーダーの buffer(1) へ渡す自前のパラメータ。
/// MSL 側の struct と並びと大きさを合わせます。
struct RippleParams {
    var frequency: Float
    var phase: Float
}

@main
final class Ripple: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "CustomPostEffect")
    }

    var effect: CustomPostEffect?

    // 前文（PPVertexOut / PostProcessParams の定義）は metaphor が足すので、
    // 書くのは自作の構造体とフラグメント関数だけ
    let source = """
    struct RippleParams {
        float frequency;
        float phase;
    };

    fragment float4 ripple(
        PPVertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]],
        constant PostProcessParams &params [[buffer(0)]],
        constant RippleParams &rp [[buffer(1)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        // 画面中心からの距離。texelSize から縦横比を戻して真円にする
        float aspect = params.texelSize.y / params.texelSize.x;
        float2 d = in.texCoord - float2(0.5);
        d.x *= aspect;
        float dist = length(d);

        // 距離に応じた波で、サンプリング位置を中心方向へずらす
        float wave = sin(dist * rp.frequency - rp.phase);
        float2 offset = normalize(d + 1e-6) * wave * params.intensity;
        offset.x /= aspect;

        float4 color = tex.sample(s, in.texCoord + offset);
        return float4(color.rgb + wave * 0.035, color.a);   // 波の峰をわずかに明るく
    }
    """

    func setup() {
        effect = try? createPostEffect(name: "ripple", source: source, fragmentFunction: "ripple")
        if let effect {
            effect.intensity = 0.006          // 組み込みの枠（PostProcessParams.intensity）
            addPostEffect(effect)
        }
        noStroke()
    }

    func draw() {
        // 波の位相だけを毎フレーム送る
        effect?.setParameters(RippleParams(frequency: 42, phase: Float(frameCount) * 0.08))

        background(14, 16, 26)

        // 歪みが見えるように、まっすぐな格子を敷く
        for iy in 0..<9 {
            for ix in 0..<16 {
                let odd = (ix + iy) % 2 == 0
                fill(odd ? 46 : 30, odd ? 58 : 38, odd ? 96 : 62)
                rect(Float(ix) * 40, Float(iy) * 40, 40, 40)
            }
        }

        fill(240, 180, 90)
        circle(320, 180, 90)
        fill(255)
        textSize(15)
        textAlign(.center)
        text("自作シェーダーで画面全体を波打たせている", 320, 336)
    }
}
```

実行: `cd Examples/Tutorial/06-GPU/04-CustomPostEffect && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `effect.intensity` を 0.02 に上げると、格子と文字はどこまで読めますか
- `frequency` を 12 に下げると、波の間隔はどうなりますか
- 戻り値を `float4(1.0 - color.rgb, color.a)` にすると、`InvertEffect` と同じものが自作できますか

### ふりかえり

- [ ] 自作のフラグメントシェーダーを組み込みエフェクトと同じ列に並べられると分かった
- [ ] MSL に書くのはフラグメント関数だけで、前文は metaphor が足すと分かった
- [ ] 入力の絵が `texture(0)`、組み込みパラメータが `buffer(0)` で来ると分かった
- [ ] 自前の値は `setParameters()` で `buffer(1)` へ渡すと分かった
- [ ] MSL を別ファイルに置けば、保存するだけでビルド無しに反映されると分かった
- [ ] 壊れたシェーダーを保存しても、直前のシェーダーのまま描き続けると分かった

### もっと詳しく

- [`createPostEffect(name:source:fragmentFunction:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createposteffect%28name:source:fragmentfunction:%29), [`CustomPostEffect`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/customposteffect), [`PostProcessShaders`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/postprocessshaders)
- [`createPostEffectFromFile(name:path:fragmentFunction:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createposteffectfromfile%28name:path:fragmentfunction:%29), [`reloadShaderFromFile(key:path:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/reloadshaderfromfile%28key:path:%29)

## 6.5 図形をシェーダーで塗る

![橙と紺の同心円の縞で塗られた画面。中央の円だけ縞が細かく明るく、下の帯に「矩形と円はシェーダー、この帯と文字は resetShader() のあと」と出ている](https://i.gyazo.com/4b5f419b68e54b8cfe2d6a1408c18c9d.png)

同心円の縞を GPU で計算し、その縞で矩形と円を塗っています。図形の側で呼んでいるのは `rect()` と `circle()` だけで、**どの画素を何色にするかを決めているのは自分で書いたフラグメントシェーダー**です。

6.3 / 6.4 のポストプロセスが「描き終えた絵にかける」ものだったのに対し、こちらは**描いている最中の塗り方**を置き換えます。Processing / p5.js の `loadShader()` / `shader()` にあたる口です。`fill()` に色ではなく関数を渡すようなもの、と考えると近いです。

### 適用して、描いて、解除する

型は 3 つの呼び出しです。

```swift
let paint = try createShader(source: source, fragment: "paint")

shader(paint)              // ここから
rect(0, 0, width, height)  // 図形が「シェーダーを通す面」になる
circle(320, 170, 220)
resetShader()              // ここまで
```

`shader()` から `resetShader()` までに描いた図形は、組み込みのシェーダーではなく自分の関数で塗られます。`fill()` や `noStroke()` と同じく**以降の描画すべてに効く設定**で、解除するまで続きます。

シェーダーの作り方は 2 通りあります。どちらも返るものは同じ `Shader2D` です。

| 作り方 | いつ使うか |
|---|---|
| `createShader(source:fragment:)` | MSL を Swift の文字列で持つ。スケッチが 1 ファイルで完結する |
| `loadShader(_:fragment:)` | MSL を `.metal` ファイルに置く。保存するだけで絵が変わる（後述） |

### 前文は metaphor が足す

ソースに書くのは**フラグメント関数だけ**です。6.4 のポストエフェクトと同じく、2D の描画シェーダーでも 3D のカスタムマテリアル（`createMaterial()`）でも metaphor が前文（Metal 標準ライブラリの取り込みと構造体の定義）を**必ず**足します。規約は 1 行で言えます——**足される構造体を自分で定義しない**。定義すると再定義エラーになります。

```metal
fragment float4 paint(
    Canvas2DVertexOut in [[stage_in]],                 // 図形の頂点から来るもの
    constant Canvas2DShaderUniforms &u [[buffer(3)]],  // metaphor が入れる組み込みの値
    constant PaintParams &p [[buffer(4)]]              // 自分で渡す値
) { ... }
```

`Canvas2DVertexOut` は `rect()` / `circle()` / `line()` などが流す stage_in です（`image()` / `text()` のテクスチャ系は `Canvas2DTexVertexOut`）。`in.color` に `fill()` の色とアルファが入っているので、返す色に掛ければ図形ごとの色分けをそのまま残せます。

### 座標は自分で作る

2D の頂点は UV を持ちません。テクスチャ座標を運ぶ代わりに、フラグメントの `in.position` が**画面のピクセル座標**になっているので、`u.resolution` で割って 0〜1 を作ります。Shadertoy の `fragCoord / iResolution` がそのまま移ります。

```metal
float2 uv = in.position.xy / u.resolution;
```

`buffer(3)` で受け取れる組み込みの値は 4 つです。

| フィールド | 中身 |
|---|---|
| `resolution` | キャンバスの寸法（ピクセル） |
| `mouse` | マウス位置（ピクセル） |
| `time` | スケッチ開始からの経過時間（秒） |
| `frameCount` | 描画したフレーム数 |

### 自前の値は setParameters() で渡す

それ以外の値は `setParameters()` で `buffer(4)` へ渡します。6.1 や 6.4 と同じく、**Swift と MSL でレイアウトを合わせる**必要があります。

```swift
paint.setParameters(PaintParams(phase: phase, bands: 14))
shader(paint)
rect(0, 0, width, height)

paint.setParameters(PaintParams(phase: -phase, bands: 40))  // 値を変えたら
shader(paint)                                               // 呼び直す
circle(320, 170, 220)
```

値は**描画バッチが確定した時点**のものが焼き込まれます。metaphor は同じ設定の図形をまとめて GPU へ送るので、`setParameters()` だけを呼んで図形を描き続けると、最後に渡した値で全部が塗られます。`shader()` は呼ぶたびにバッチをそこで切るため、図形ごとに値を変えたいときは**値を変えるたびに呼び直します**。

### 保存するだけで書き換わる

`loadShader()` で `.metal` ファイルから読むと、6.4 のポストエフェクトとまったく同じ自動リロードが効きます。**保存すればその場で再コンパイルされ、ウィンドウは開いたまま絵が変わります**。書きかけの MSL を保存しても画面は直前の動くシェーダーのままで、エラーだけがコンソールに出ます。有効・無効の切り替え（`SketchConfig(shaderHotReload:)` と `METAPHOR_SHADER_HOT_RELOAD`）も 6.4 と共通です。

`.metal` ファイルを使う形は [`Examples/Topics/Shaders/CustomShader2D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders/CustomShader2D) にあります。走らせたまま `wave.metal` の数値を書き換えて保存すると、往復からビルドが消えていることが分かります。

### 一緒に使えないもの

`blendMode(.difference)` と `.exclusion` は、カスタムシェーダーとは同時に使えません。この 2 つは「描き込み先の色を読む」専用のフラグメントで実装されていて、自分の関数と入れ替える場所が同じだからです。カスタムシェーダーの適用中は通常のアルファ合成に落ち、コンソールへ 1 度だけ警告が出ます。ほかのブレンドモード（`.add` / `.multiply` など、2.10 で扱ったもの）はそのまま使えます。

<!-- tutorial-snippet: 06-GPU/05-ShapeShader -->
```swift
import metaphor

/// シェーダーの buffer(4) へ渡す自前のパラメータ。
/// MSL 側の struct と並びと大きさを合わせます。
struct PaintParams {
    var phase: Float
    var bands: Float
}

@main
final class ShapeShader: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ShapeShader")
    }

    var paint: Shader2D?

    // 前文（Metal 標準ライブラリと Canvas2DVertexOut / Canvas2DShaderUniforms の定義）は
    // metaphor が必ず先頭へ足すので、フラグメント関数だけを書きます
    let source = """
    struct PaintParams {
        float phase;
        float bands;
    };

    fragment float4 paint(
        Canvas2DVertexOut in [[stage_in]],
        constant Canvas2DShaderUniforms &u [[buffer(3)]],
        constant PaintParams &p [[buffer(4)]]
    ) {
        // 2D の頂点は UV を持たないので、画面ピクセル座標を resolution で割って作る
        float2 uv = in.position.xy / u.resolution;
        float2 c = uv * 2.0 - 1.0;
        c.x *= u.resolution.x / u.resolution.y;   // 縦横比を戻して同心円を真円にする

        float wave = sin(length(c) * p.bands - p.phase);
        float band = smoothstep(-0.6, 0.6, wave);
        float3 rgb = mix(float3(0.09, 0.13, 0.30), float3(0.98, 0.55, 0.25), band);

        return float4(rgb, 1.0) * in.color;       // fill() の色とアルファが掛かる
    }
    """

    func setup() {
        paint = try? createShader(source: source, fragment: "paint")
        noStroke()
    }

    func draw() {
        background(14, 16, 26)
        guard let paint else { return }

        // 位相はフレーム数から作る（同じフレームなら必ず同じ絵になる）
        let phase = Float(frameCount) * 0.06

        // 画面いっぱいの矩形。fill() の色が掛かるので、暗い灰色で敷いて奥へ下げる
        paint.setParameters(PaintParams(phase: phase, bands: 14))
        fill(110)
        shader(paint)
        rect(0, 0, width, height)

        // 同じシェーダーを別のパラメータで円に掛ける。
        // shader() を呼び直すとバッチが切れ、その時点のパラメータが焼き込まれる
        paint.setParameters(PaintParams(phase: -phase * 1.6, bands: 40))
        fill(255)
        shader(paint)
        circle(320, 170, 220)

        resetShader()

        // 解除したので、ここから下は組み込みシェーダーに戻る
        fill(0, 150)
        rect(0, 316, width, 44)
        fill(255)
        textSize(15)
        textAlign(.center)
        text("矩形と円はシェーダー、この帯と文字は resetShader() のあと", 320, 342)
    }
}
```

実行: `cd Examples/Tutorial/06-GPU/05-ShapeShader && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `bands` を 4 まで下げると、縞は何本になりますか
- 矩形の `fill(110)` を `fill(255)` に戻すと、円と背景の関係はどう変わりますか
- `phase` を `Float(frameCount) * 0.06` から `u.time * 3.0`（MSL 側で計算）に変えると、動きは同じに見えますか
- `resetShader()` を消すと、下の帯と文字はどう描かれますか

### ふりかえり

- [ ] `shader()` から `resetShader()` までの図形が自分のシェーダーで塗られると分かった
- [ ] MSL に書くのはフラグメント関数だけで、前文は metaphor が足すと分かった
- [ ] 2D には UV が無く、`in.position` を `u.resolution` で割って座標を作ると分かった
- [ ] 自前の値は `setParameters()` で渡し、値を変えたら `shader()` を呼び直すと分かった
- [ ] `.metal` ファイルから読めば、保存するだけで絵が変わると分かった

### もっと詳しく

- [`createShader(source:fragment:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createshader%28source:fragment:%29), [`loadShader(_:fragment:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/loadshader%28_:fragment:%29), [`shader(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/shader%28_:%29), [`resetShader()`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/resetshader%28%29)
- [`Shader2D`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/shader2d), [`Canvas2DShaderUniforms`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/canvas2dshaderuniforms)
- [`Examples/Topics/Shaders/CustomShader2D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders/CustomShader2D)

## 6.6 いまできないこと

GPU まわりには、まだ口が開いていない場所があります。作品を組み立て始める前に、境界を知っておくと遠回りをせずに済みます。

### 2D で差し替えられるのはフラグメントだけ

6.5 で置き換えたのは「画素の色を決める関数」です。**頂点をどこへ動かすかを決める頂点シェーダーは、2D では組み込みのまま**で、差し替える口がありません。図形の形そのものを GPU で歪ませたいときは、Swift 側で座標を作って `beginShape()` / `vertex()` で流すか、6.1 のように GPU で計算した値を読んで図形に反映させます。

3D は事情が違い、`createMaterial(source:fragmentFunction:vertexFunction:)` で頂点シェーダーも一緒に渡せます。面の塗り方を変えるだけなら 2D と同じくフラグメントだけで足ります（前文も 2D と同じく metaphor が足すので、`Canvas3DVertexOut` や `Canvas3DUniforms` は自分で定義しません）。実物は [`Examples/Topics/Shaders/ToonShading`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders/ToonShading) で、明るさを 4 段に量子化するフラグメント関数だけを書き、頂点は組み込みのまま使っています。

### Topics/Shaders の大半は参考にならない

[`Examples/Topics/Shaders/`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders) には Monjori や Nebula といった名前のサンプルが並んでいますが、これらは**元の GLSL の絵を CPU 側で近似したもの**で、`.metal` ファイルが入っていません。Processing の移植として残しているだけなので、シェーダーの書き方を探しているなら 6.4 / 6.5 と、実際に `.metal` を読む 2 本 — 2D の [`CustomShader2D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders/CustomShader2D) と 3D の [`ToonShading`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders/ToonShading) — が実際の入口です。

### 実装されたら本文へ

こうした制約は、機能が入った時点でこの節から本文の節へ移ります。6.5 はまさにそれで、長らくこの節に「2D の描画シェーダーは差し替えられない」と書かれていたものが実装されて昇格しました。最新の状態は [`docs/README.md`](https://github.com/shinyaoguri/metaphor/blob/main/docs/README.md) から辿れる Issue が持っています。

### ふりかえり

- [ ] 2D で差し替えられるのはフラグメントシェーダーだけだと分かった
- [ ] 3D のカスタムマテリアルは頂点シェーダーも渡せると分かった
- [ ] `Topics/Shaders/` が CPU 近似で、シェーダーの参考にはならないと分かった

### もっと詳しく

- [`createMaterial(source:fragmentFunction:vertexFunction:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/creatematerial%28source:fragmentfunction:vertexfunction:%29), [`material(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/material%28_:%29), [`CustomMaterial`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/custommaterial)

---

GPU に仕事を渡す 3 つの道具（コンピュートカーネル・GPU パーティクル・ポストプロセス）が揃いました。ここまでで、量に負けない絵の作り方はひととおり手に入っています。

次の第 7 部では、外から入ってくるもの（音・カメラ・動画）を絵の材料にします。
