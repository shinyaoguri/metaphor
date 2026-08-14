---
title: GPU を使う
part: 6
slug: gpu
description: 自分で書いたカーネルで GPU に計算させ、100 万粒を動かし、描き終えた絵に効果をかけます。
draft: false
---

# 第 6 部 GPU を使う

ここまでのスケッチでも GPU は動いていました。`circle()` や `box()` を呼ぶたびに、metaphor が図形を GPU へ送って描かせていたからです。ただし**何を描くかを決めているのは、いつも CPU 側の Swift のコード**でした。

この部では、その分担を動かします。やることは 3 つです。**計算そのものを GPU にさせる**（`compute()`）、**データを CPU に降ろさずに動かし続ける**（GPU パーティクル）、**描き終えた絵にまとめて効果をかける**（ポストプロセス）。どれも「1 つずつ Swift で処理していたら間に合わない量」を扱うための道具です。

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

![黄色い点の輪と中央の白い点に Bloom と Vignette がかかり、光がにじんで四隅が落ちている](https://i.gyazo.com/dda4dd3bbf40a95bc833a885767807d0.png)

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
                VignetteEffect(intensity: 1.0, smoothness: 0.35),
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

![自作シェーダーで波打たせた市松模様の上に、オレンジ色の円がひとつ乗っている](https://i.gyazo.com/3ddb574bfde49d497bebfa7db26be179.png)

組み込みのエフェクトで足りないときは、フラグメントシェーダーを自分で書いて同じ列に並べられます。ここでは画面中心からの距離に応じてサンプリング位置をずらし、格子を波打たせています。

### 共通の構造体に自作の関数を足す

`createPostEffect(name:source:fragmentFunction:)` に MSL のソースを渡します。ソースの先頭には `PostProcessShaders.commonStructs` を置きます。これに `PPVertexOut`（頂点シェーダーからの入力）と `PostProcessParams`（組み込みのパラメータ）の定義が入っています。

```swift
let source = PostProcessShaders.commonStructs + """
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

シェーダーを書くときは、値を少し変えては絵を見る往復になります。手段は 2 つあります。

- `metaphor watch` で走らせる（保存のたびに再ビルドされ、ウィンドウは開いたまま）
- MSL を別ファイルに置き、`reloadShaderFromFile(key:path:)` で読み直す。キーは `createPostEffect(name:)` の名前から決まり、`"user.posteffect.<name>"` になります

後者は再ビルドが要らない代わりに、読み直す操作を自分で呼ぶ必要があります（キー入力に割り当てるなど）。

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

    // 共通の構造体定義（PPVertexOut / PostProcessParams）に自作の関数を足す
    let source = PostProcessShaders.commonStructs + """

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
- [ ] ソースの先頭に `PostProcessShaders.commonStructs` が要ると分かった
- [ ] 入力の絵が `texture(0)`、組み込みパラメータが `buffer(0)` で来ると分かった
- [ ] 自前の値は `setParameters()` で `buffer(1)` へ渡すと分かった
- [ ] シェーダーを書き換えながら試す手段が 2 つあると分かった

### もっと詳しく

- [`createPostEffect(name:source:fragmentFunction:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createposteffect%28name:source:fragmentfunction:%29), [`CustomPostEffect`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/customposteffect), [`PostProcessShaders`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/postprocessshaders)
- [`reloadShaderFromFile(key:path:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/reloadshaderfromfile%28key:path:%29)

## 6.5 いまできないこと

GPU まわりには、まだ口が開いていない場所があります。作品を組み立て始める前に、境界を知っておくと遠回りをせずに済みます。

### 2D の描画シェーダーは差し替えられない

Processing / p5.js の `loadShader()` / `shader()` にあたるもの、つまり**図形そのものをどう塗るかを自分のシェーダーで置き換える**手段は、2D にはまだありません（[#291](https://github.com/shinyaoguri/metaphor/issues/291)）。

いまできるのは次の 2 つです。

| やりたいこと | いまの手段 |
|---|---|
| 画面全体を加工する | 6.3 / 6.4 のポストプロセス |
| 3D の面の塗り方を変える | `createMaterial()` で作って `material()` で適用する |

2D で「シェーダーらしい絵」を出したいときは、当面はポストプロセス側に寄せるか、6.1 のように値を GPU で計算して図形で表現することになります。

### Topics/Shaders の例は参考にならない

[`Examples/Topics/Shaders/`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Shaders) には Monjori や Nebula といった名前のサンプルが並んでいますが、これらは**元の GLSL の絵を CPU 側で近似したもの**で、`.metal` ファイルは 1 つも入っていません。カスタムシェーダーの書き方を探しているなら、この節までの 6.1 と 6.4 が実際の入口です。

### 実装されたら本文へ

これらの制約は、機能が入った時点でこの節から本文の節へ移ります。現状は [`docs/README.md`](https://github.com/shinyaoguri/metaphor/blob/main/docs/README.md) から辿れる Issue が最新の状態を持っています。

### ふりかえり

- [ ] 2D の描画シェーダー差し替えが未実装だと分かった
- [ ] 3D にはカスタムマテリアルという別の口があると分かった
- [ ] `Topics/Shaders/` が CPU 近似で、シェーダーの参考にはならないと分かった

### もっと詳しく

- [`createMaterial(source:fragmentFunction:vertexFunction:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/creatematerial%28source:fragmentfunction:vertexfunction:%29), [`material(_:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/material%28_:%29), [`CustomMaterial`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/custommaterial)

---

GPU に仕事を渡す 3 つの道具（コンピュートカーネル・GPU パーティクル・ポストプロセス）が揃いました。ここまでで、量に負けない絵の作り方はひととおり手に入っています。

次の第 7 部では、外から入ってくるもの（音・カメラ・動画）を絵の材料にします。
