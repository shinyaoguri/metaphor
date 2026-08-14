---
title: 動かす
part: 3
slug: motion
description: 時間・補間・三角関数・乱数・ノイズ・ベクトルで、絵に動きを与えます。
draft: false
---

# 第 3 部 動かす

この部では、第 2 部で描いた絵を**時間の関数**にします。`draw()` が毎フレーム呼ばれることを利用して、位置や色をフレームごとに少しずつ変えていきます。

道具は 3 つだけです。**時間**（いま何フレーム目か、何秒経ったか）、**値の変換**（時間を位置や色に読み替える）、**状態**（前のフレームの値を覚えておく）。この 3 つの組み合わせで、跳ねるボールからパーティクルまで作れます。

## この部の前提

第 1 部 1.3 の「フレームをまたぐ値は型のプロパティとして持つ」と、第 2 部の図形・色・変換をひととおり使います。特に 2.5 の `push()` / `pop()` と 2.10 のブレンドモードは、後半のパーティクルの節でそのまま出てきます。

## 3.1 時間を使う

![時間の実行結果](https://i.gyazo.com/a3905609a2aae8bbe7dee3cdd1fd254b.png)

![時間の動き](https://i.gyazo.com/e0dbd11a1c6af08fa2bfc523a8685f47.webp)

動きの出発点は「いまがいつか」を知ることです。`draw()` の中では 3 つの時計が使えます。

| 名前 | 意味 | 単位 |
|---|---|---|
| `frameCount` | `draw()` がこれまでに呼ばれた回数 | 回 |
| `time` | スケッチが始まってからの経過時間 | 秒 |
| `deltaTime` | 前のフレームからの経過時間 | 秒 |

同じ「右へ進む」でも、どの時計を使うかで意味が変わります。

```swift
x = Float(frameCount) * 2.3   // 1 フレームにつき 2.3 ピクセル
x = time * 140                // 1 秒につき 140 ピクセル
```

上の書き方は**フレーム数に比例**します。描画が重くなってフレームレートが落ちると、そのぶん進みが遅くなります。下の書き方は**経過時間に比例**するので、フレームレートが変わっても見かけの速さは同じです。

3 つ目の `deltaTime` は、その 1 フレームぶんの時間です。毎フレーム足し込むと `time` と同じ値になります。

```swift
accumulated += speed * deltaTime   // time * speed と同じところへ着く
```

`time` があるのに `deltaTime` が要るのは、**速さが途中で変わる**ときです。速度を変えながら位置を積み上げていく動き（3.7 のベクトルや 3.9 のパーティクル）は、経過時間からは一発で求められません。前のフレームの値に「今回のぶん」を足していく形になります。

実行結果では 3 本の点がほぼ同じ位置を走ります。フレームレートが指定どおり出ている間、この 3 つは同じ意味になるからです。差が出るのは描画が重くなったときで、そのとき遅れるのは `frameCount` の行だけです。

どちらを選ぶかの目安です。

- **実時間に合わせたい**（音に同期する、何秒で 1 周させる）なら `time` / `deltaTime`
- **同じ絵を再現したい**（画像を撮り直す、動画に焼く）なら `frameCount`

このチュートリアルの動きの証跡が `frameCount` で書かれているのは後者の理由です。フレーム数で決めておけば、何度実行しても同じフレームで同じ絵になります。

<!-- tutorial-snippet: 03-Motion/01-Time -->
```swift
import metaphor

@main
final class Time: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Time")
    }

    // 1 秒あたりに進むピクセル数
    let speed: Float = 140

    // deltaTime を自分で足し込んだ距離。time * speed と同じ値になるはず
    var accumulated: Float = 0

    func draw() {
        background(24)

        // 経過時間のぶんだけ進める。フレームレートが落ちても 1 フレームの
        // deltaTime が伸びるので、見かけの速さは変わらない
        accumulated += speed * deltaTime

        // フレーム数で進める点。1 フレームにつき決まった距離だけ動くので、
        // フレームレートが変わると速さも変わる
        track(y: 96, label: "frameCount * 2.3", distance: Float(frameCount) * 2.3, color: (230, 90, 70))
        track(y: 180, label: "time * speed", distance: time * speed, color: (240, 190, 80))
        track(y: 264, label: "sum of deltaTime * speed", distance: accumulated, color: (110, 200, 160))

        fill(190)
        textSize(13)
        text("frameCount = \(frameCount)", 40, 332)
        text("time = \(rounded(time, digits: 2))s", 250, 332)
        text("deltaTime = \(rounded(deltaTime, digits: 4))s", 420, 332)
    }

    /// 1 本のトラックと、その上を走る点を描く。
    private func track(y: Float, label: String, distance: Float, color: (Float, Float, Float)) {
        let left: Float = 40
        let span = width - 80
        // 右端まで来たら左端へ戻す。余りを取るだけで往復させずに済む
        let x = left + distance.truncatingRemainder(dividingBy: span)
        let (r, g, b) = color

        stroke(70)
        strokeWeight(1)
        line(left, y, left + span, y)

        noStroke()
        fill(r, g, b)
        circle(x, y, 22)

        fill(190)
        textSize(13)
        text(label, left, y - 18)
    }

    /// 表示用に桁を丸める（画面の数字が毎フレーム暴れないように）。
    private func rounded(_ value: Float, digits: Int) -> Float {
        var scale: Float = 1
        for _ in 0..<digits { scale *= 10 }
        return (value * scale).rounded() / scale
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/01-Time && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `setup()` に `frameRate(20)` を足すと、3 本のうちどれの速さが変わりますか
- `accumulated` の行を `accumulated += speed / 60` に変えると、フレームレートを落としたときに何が起きますか
- `truncatingRemainder(dividingBy:)` をやめて `constrain` にすると、点は右端でどうなりますか

### ふりかえり

- [ ] `frameCount` / `time` / `deltaTime` の 3 つが何を指すか区別できるようになった
- [ ] フレーム数に比例させると、描画が重くなったとき進みも遅くなると分かった
- [ ] 速さが途中で変わる動きには `deltaTime` を足し込む形が要ると分かった
- [ ] 実時間に合わせるなら `time` / `deltaTime`、同じ絵を再現するなら `frameCount`、と使い分けられるようになった

### もっと詳しく

- [`frameCount`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/framecount), [`time`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/time), [`deltaTime`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/deltatime)
- [`Topics/Motion/Linear`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Motion/Linear), [`Basics/Input/Milliseconds`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/Milliseconds)

## 3.2 数値を変換する

![数値の変換の実行結果](https://i.gyazo.com/d9ad47839b0e52495d0ad035dec0046a.png)

時間から動きを作るとき、いちばん多い作業は**範囲の読み替え**です。0 から 1 で表された進み具合を、キャンバスの座標や色の濃さに移す、という変換がひたすら出てきます。metaphor には 4 つの関数があります。

```swift
map(v, 0, 100, 40, 600)   // 0〜100 の値を 40〜600 へ移す
norm(v, 0, 100)           // 0〜100 の値を 0〜1 へ移す（map の特別な場合）
constrain(v, 40, 600)     // 40 未満は 40 に、600 超は 600 にする
lerp(40, 600, t)          // 40 と 600 の間を、割合 t（0〜1）で取る
```

`map()` は**範囲外も外挿します**。入力が 0〜100 の想定でも、120 が来れば出力は 600 を超えます。画面からはみ出して困る場合は `constrain()` と組み合わせます。実行結果の 2 行目が、はみ出したぶんが両端に張り付いた状態です。

```swift
constrain(map(v, 0, 100, left, right), left, right)
```

`map()` と `lerp()` は似ていますが、向きが逆です。`map()` は**入力の範囲を知っている**とき、`lerp()` は**すでに 0〜1 の割合が手元にある**ときに使います。割合をそのまま渡さず加工すると、同じ入力でも並び方が変わります。実行結果の 3 行目は `t` の代わりに `t * t` を渡したもので、左に詰まって右で伸びています。**割合を作り替えることが、そのまま動きの表情になります**。これが次の節のイージングにつながります。

`map()` の出力側は逆向きでも構いません。`map(v, 0, 100, 600, 40)` と書けば、値が増えるほど左へ動きます。

<!-- tutorial-snippet: 03-Motion/02-Mapping -->
```swift
import metaphor

@main
final class Mapping: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Mapping")
    }

    // 元になる値。0, 10, 20, ... 100 の 11 個
    let sampleCount = 11

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noStroke()

        let left: Float = 40
        let right = width - 40

        for i in 0..<sampleCount {
            let v = Float(i) * 10

            // map: 0〜100 の値を、キャンバスの左端から右端までへ引き伸ばす。
            // 等間隔の入力は等間隔のまま出てくる
            let mapped = map(v, 0, 100, left, right)

            // constrain: いったん画面の外まではみ出す範囲へ写してから、
            // 描ける範囲へ押し込む。はみ出したぶんが両端に張り付く
            let constrained = constrain(map(v, 0, 100, left - 260, right + 260), left, right)

            // lerp: 0〜1 の割合で 2 つの値の間を取る。割合の作り方を変えると
            // （ここでは 2 乗）同じ入力でも並び方が変わる
            let t = norm(v, 0, 100)
            let interpolated = lerp(left, right, t * t)

            fill(map(v, 0, 100, 70, 240), 150, map(v, 0, 100, 240, 90))
            circle(mapped, 110, 20)
            circle(constrained, 190, 20)
            circle(interpolated, 270, 20)
        }

        textSize(14)
        fill(215)
        text("map(v, 0, 100, left, right)", left, 84)
        text("constrain(map(v, 0, 100, left - 260, right + 260), left, right)", left, 164)
        text("lerp(left, right, t * t)   //  t = norm(v, 0, 100)", left, 244)

        fill(140)
        text("v = 0, 10, 20, ... 100", left, 322)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/02-Mapping && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `lerp(left, right, t * t)` を `lerp(left, right, sqrt(t))` にすると、点はどちら側に詰まりますか
- 2 行目の `constrain` を外すと、点はどこへ描かれますか
- `map(v, 0, 100, left, right)` の出力範囲を入れ替えて `map(v, 0, 100, right, left)` にすると、色と位置の対応はどうなりますか

### ふりかえり

- [ ] `map()` / `norm()` / `constrain()` / `lerp()` の 4 つを使い分けられるようになった
- [ ] `map()` が範囲外も外挿するので、必要なら `constrain()` と組み合わせると分かった
- [ ] `map()` は入力の範囲を知っているとき、`lerp()` は 0〜1 の割合が手元にあるとき、と使い分けられるようになった
- [ ] 割合を加工する（`t * t` にする）と、それがそのまま動きの表情になると分かった

### もっと詳しく

- [`map`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/map%28_:_:_:_:_:%29), [`norm`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/norm%28_:_:_:%29), [`constrain`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/constrain%28_:_:_:%29)
- [`Basics/Math/Map`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Map), [`Basics/Input/Constrain`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/Constrain), [`Basics/Math/Interpolate`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Interpolate)

## 3.3 イージング

![イージングの実行結果](https://i.gyazo.com/adb27aed65a57f762b0f73eaf23ec6c7.png)

![イージングの動き](https://i.gyazo.com/69007e688968a82e15b53820f15861a0.webp)

目標の位置へ図形を動かすとき、いちばん素朴な書き方は「目標の座標をそのまま代入する」ことです。これだと図形は瞬間移動します。

代わりに、**残っている距離の一定割合だけ毎フレーム進む**ようにすると、動きに慣性が生まれます。

```swift
x = lerp(x, targetX, 0.06)   // いまの x から目標へ 6% だけ近づく
```

`lerp(a, b, t)` は `a` と `b` の間を `t`（0..1）で補間した値を返します。`t` を毎フレーム同じ値にしても、`a` のほうが毎フレーム目標へ近づいていくので、**進む量はだんだん小さくなります**。これがイージング（easing）です。目標に近いほどゆっくりになる、という減速が、追加の状態を持たずに手に入ります。

係数の大きさが追従の速さになります。上の実行結果では 3 つの点が同じ目標を追っていて、`0.02` はもたつき、`0.18` はほとんど貼り付いて動きます。`1.0` にすると瞬間移動、`0` にすると動きません。

動きの証跡（アニメーション）は静止画では確かめられないので、この節の画像は連続キャプチャから作っています。撮影のたびに絵が変わらないよう、スケッチ側では乱数の種を `randomSeed(11)` で固定し、目標を切り替えるタイミングも経過時間ではなく `frameCount` で決めています。

<!-- tutorial-snippet: 03-Motion/03-Easing -->
```swift
import metaphor

@main
final class Easing: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Easing")
    }

    // 追従の速さ。0 に近いほどゆっくり、1 なら瞬間移動
    let easings: [Float] = [0.02, 0.06, 0.18]
    let colors: [(Float, Float, Float)] = [
        (230, 90, 70),
        (240, 190, 80),
        (110, 200, 160),
    ]

    // 追いかける側の現在位置（easings と同じ並び）
    var xs: [Float] = []
    var ys: [Float] = []

    // 3 つが共通で追う目標
    var targetX: Float = 0
    var targetY: Float = 0

    func setup() {
        // 実行するたびに同じ動きになるよう、乱数の種を固定する
        randomSeed(11)
        xs = easings.map { _ in width * 0.5 }
        ys = easings.map { _ in height * 0.5 }
        pickTarget()
    }

    func draw() {
        background(24)

        // 75 フレームごとに目標を選び直す。時刻ではなくフレーム数で決めて
        // いるので、何度実行しても同じタイミングで飛ぶ
        if frameCount % 75 == 0 {
            pickTarget()
        }

        // 目標の位置
        noFill()
        stroke(150)
        strokeWeight(2)
        circle(targetX, targetY, 40)

        for i in easings.indices {
            // イージングの本体。目標へ一気に動かさず、残りの距離の一定割合
            // だけ毎フレーム進む。距離が縮むほど進む量も減るので、自然に減速する
            xs[i] = lerp(xs[i], targetX, easings[i])
            ys[i] = lerp(ys[i], targetY, easings[i])

            let (r, g, b) = colors[i]

            // 目標との差。この線の長さが次のフレームの移動量を決める
            stroke(r, g, b, 90)
            strokeWeight(1)
            line(xs[i], ys[i], targetX, targetY)

            // 追いかける側
            noStroke()
            fill(r, g, b)
            circle(xs[i], ys[i], 24)
        }

        // どの色がどの係数かを凡例で示す。文字も図形と同じく fill 色で塗られる
        textSize(14)
        for i in easings.indices {
            let (r, g, b) = colors[i]
            let baseline = 28 + Float(i) * 22
            fill(r, g, b)
            text("easing = \(easings[i])", 20, baseline)
        }
    }

    private func pickTarget() {
        targetX = random(80, width - 80)
        targetY = random(80, height - 80)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/03-Easing && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `easings` の値を `[0.5, 0.9, 1.0]` にすると、3 つの点の違いはどうなりますか
- `lerp(xs[i], targetX, easings[i])` の `easings[i]` を `easings[i] * 2` にすると、行き過ぎ（オーバーシュート）は起きますか
- 目標を切り替える間隔（`frameCount % 75`）を短くすると、遅い点は目標に追いつけますか

### ふりかえり

- [ ] `x = lerp(x, target, t)` を毎フレーム呼ぶだけで慣性のある動きになると分かった
- [ ] 係数が同じでも残り距離が縮むので、自然に減速すると分かった
- [ ] 係数の大きさが追従の速さで、`1.0` なら瞬間移動・`0` なら動かないと分かった
- [ ] 撮り直しても同じ絵にするために、種を固定し `frameCount` で切り替える書き方を覚えた

### もっと詳しく

- [`lerp`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/) — 2 つの値の間を線形補間する
- [`Basics/Input/Easing`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/Easing), [`Topics/Interaction/Follow1`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Interaction/Follow1)

## 3.4 三角関数で動かす

![三角関数の実行結果](https://i.gyazo.com/528ae81542591e2af5742c3e83af2dbe.png)

![三角関数の動き](https://i.gyazo.com/f9cfddc0c9bef07a7c49a78bb8fcafa4.webp)

まっすぐ進む動きの次は、**回る動き**と**揺れる動き**です。どちらも `sin()` と `cos()` の 2 つで書けます。

角度の単位は**ラジアン**です。一周が `TWO_PI`、半周が `PI`、直角が `HALF_PI` で、いずれも定数として使えます。角度を毎フレーム少しずつ進め、その角度を `cos()` と `sin()` に通すと、点は円を描きます。

```swift
let angle = Float(frameCount) * 0.03
let x = centerX + cos(angle) * radius   // cos が横
let y = centerY + sin(angle) * radius   // sin が縦
```

`sin()` と `cos()` はどちらも −1 から 1 の間を往復する関数です。掛ける値（`radius`）が**振幅**、角度の進む速さ（`0.03`）が**周期**を決めます。片方だけ使えば、上下や左右に揺れるだけの動きになります。

同じ関数を横方向に流すと波になります。x が右へ進むほど「少し前の角度」を見るようにするだけです。

```swift
vertex(x, centerY + sin(angle - (x - waveLeft) * 0.03) * radius)
```

角度からずらすこの量を**位相**と呼びます。位相をずらした波を何本か重ねると、複雑なうねりが作れます。実行結果では、左の円で回っている点と波の左端が常に同じ高さになります。円運動と波が同じものの別の見方だ、ということがここで分かります。

逆に、**位置だけが手元にあって角度を知りたい**ときは `atan2()` を使います。

```swift
let angle = atan2(py - centerY, px - centerX)   // 中心から見た方向
```

引数の順が y、x であることに注意します。戻る値の範囲は −`PI` から `PI` なので、回り続けている元の角度とは一致しなくなります。実行結果に並べた 2 つの数字は、点が半周するまでは同じ値で、そこを越えると `atan2()` の側だけが負へ折り返します。向きを知りたいだけのとき（第 4 部でマウスのほうを向かせるときなど）はこれで十分です。

<!-- tutorial-snippet: 03-Motion/04-Trigonometry -->
```swift
import metaphor

@main
final class Trigonometry: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Trigonometry")
    }

    // 左側の円の中心と半径
    let centerX: Float = 150
    let centerY: Float = 170
    let radius: Float = 96

    func draw() {
        background(24)

        // 角度はフレーム数から決める。時刻ではなくフレーム数なので、
        // 何度実行しても同じタイミングで同じ角度になる
        let angle = Float(frameCount) * 0.03

        // 円周上の点。cos が横方向、sin が縦方向を受け持つ
        let px = centerX + cos(angle) * radius
        let py = centerY + sin(angle) * radius

        // 軌道
        noFill()
        stroke(70)
        strokeWeight(1)
        circle(centerX, centerY, radius * 2)
        line(centerX - radius, centerY, centerX + radius, centerY)
        line(centerX, centerY - radius, centerX, centerY + radius)

        // 中心から点へ引いた半径。この線の縦の長さが sin、横の長さが cos
        stroke(150)
        strokeWeight(2)
        line(centerX, centerY, px, py)

        noStroke()
        fill(240, 190, 80)
        circle(px, py, 20)

        // 右側は、同じ sin を横に流した波。x が右へ進むほど過去の角度を
        // 見ていることになるので、角度から x のぶんだけ引く
        let waveLeft: Float = 320
        let waveRight = width - 20
        noFill()
        stroke(110, 200, 160)
        strokeWeight(2)
        beginShape()
        var x = waveLeft
        while x <= waveRight {
            vertex(x, centerY + sin(angle - (x - waveLeft) * 0.03) * radius)
            x += 3
        }
        endShape(.open)

        // 波の左端は、左の円で回っている点と必ず同じ高さになる
        noStroke()
        fill(240, 190, 80)
        circle(waveLeft, py, 12)

        // 位置しか手元にないときは、角度を atan2 で取り戻せる。戻る値の
        // 範囲は -PI 〜 PI なので、回り続ける angle とは一致しなくなる
        let recovered = atan2(py - centerY, px - centerX)
        textSize(13)
        fill(190)
        text("angle = \(rounded(angle)) rad", 40, 322)
        text("atan2(dy, dx) = \(rounded(recovered)) rad", 40, 342)
        fill(110, 200, 160)
        text("sin(angle - x * 0.03)", waveLeft, 322)
    }

    /// 表示用に小数 2 桁へ丸める。
    private func rounded(_ value: Float) -> Float {
        (value * 100).rounded() / 100
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/04-Trigonometry && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `Float(frameCount) * 0.03` の係数を大きくすると、円運動と波のどちらが速くなりますか
- 波の式の `* 0.03` だけを変えると、波の何が変わりますか
- `cos(angle) * radius` を `cos(angle) * radius * 0.4` にすると、軌道はどんな形になりますか

### ふりかえり

- [ ] 角度を進めて `cos()` を横・`sin()` を縦に使うと円運動になると分かった
- [ ] 掛ける値が振幅、角度の進む速さが周期を決めると分かった
- [ ] 位置ごとに角度をずらす（位相）と、同じ関数が波になると分かった
- [ ] 位置から向きを知りたいときは `atan2(dy, dx)` を使い、戻る範囲が −`PI`〜`PI` だと分かった

### もっと詳しく

- [`PI`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/pi), [`TWO_PI`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/two_pi), [`HALF_PI`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/half_pi)
- [`Basics/Math/SineCosine`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/SineCosine), [`Basics/Math/SineWave`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/SineWave), [`Basics/Math/AdditiveWave`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/AdditiveWave), [`Basics/Math/Arctangent`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Arctangent)

## 3.5 乱数

![乱数の実行結果](https://i.gyazo.com/dcee7686eb77c91d82193a8aea1459e5.png)

規則正しい動きに揺らぎを混ぜると、一気に生き物らしくなります。metaphor の乱数は 2 種類です。

```swift
random(10)        // 0 以上 10 未満
random(-5, 5)     // -5 以上 5 未満
randomGaussian()  // 平均 0、標準偏差 1 の正規分布
```

`random()` は範囲の中がどこも同じ確率で出る**一様乱数**です。`randomGaussian()` は平均のまわりに集まり、遠くなるほどまれになる**正規分布**を返します。実行結果は同じ回数だけ値を取り出して数えたもので、上が平ら、下が山になっています。

`randomGaussian()` は平均 0・標準偏差 1 で返るので、掛けて足してから使います。

```swift
let size = 20 + randomGaussian() * 4   // だいたい 20、たまに 12 や 28
```

散らばりの形が違うと、絵の印象も変わります。星をばらまくなら一様乱数、同じ種類のものが少しずつ違う（大きさ・速さ・色みのばらつき）なら正規分布が自然です。

もう一つ大事なのが**種（シード）**です。乱数は本当に予測不能なのではなく、種から計算で作られています。種を固定すると毎回まったく同じ列が出ます。

```swift
randomSeed(7)   // setup() で呼ぶ
```

気に入った配置を再現したいとき、画像を撮り直したいとき、変更の影響だけを見比べたいときに使います。このチュートリアルの画像がどれも同じ絵で撮り直せるのは、各スケッチが種を固定しているからです。

<!-- tutorial-snippet: 03-Motion/05-Random -->
```swift
import metaphor

@main
final class RandomValues: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Random Values")
    }

    let sampleCount = 6000
    let binCount = 48

    // 出た値を入れる箱。何回目の箱にいくつ入ったかを数える
    var uniform: [Int] = []
    var gaussian: [Int] = []

    func setup() {
        noLoop()

        // 種を決めておくと、実行するたびに同じ乱数列が出る。絵が毎回
        // 変わらないので、変更の影響だけを見比べられる
        randomSeed(7)

        uniform = Array(repeating: 0, count: binCount)
        gaussian = Array(repeating: 0, count: binCount)

        for _ in 0..<sampleCount {
            // 一様乱数。範囲のどこも同じくらいの確率で出る
            uniform[binIndex(random(0, 1))] += 1

            // 正規分布。平均のまわりに集まり、遠いほどまれになる
            gaussian[binIndex(0.5 + randomGaussian() * 0.13)] += 1
        }
    }

    func draw() {
        background(24)
        histogram(uniform, top: 56, barHeight: 110, color: (230, 90, 70), label: "random(0, 1)")
        histogram(gaussian, top: 218, barHeight: 110, color: (110, 200, 160), label: "0.5 + randomGaussian() * 0.13")
    }

    /// 値 0〜1 を箱の番号に直す。範囲外は両端の箱に入れる。
    private func binIndex(_ value: Float) -> Int {
        Int(constrain(value, 0, 0.999) * Float(binCount))
    }

    /// 箱の中身を棒グラフにする。棒の高さはいちばん多い箱を基準に揃える。
    private func histogram(_ bins: [Int], top: Float, barHeight: Float, color: (Float, Float, Float), label: String) {
        let left: Float = 40
        let barWidth = (width - 80) / Float(bins.count)
        let peak = Float(bins.max() ?? 1)
        let (r, g, b) = color

        noStroke()
        fill(r, g, b)
        for (i, count) in bins.enumerated() {
            let h = Float(count) / peak * barHeight
            rect(left + Float(i) * barWidth, top + barHeight - h, barWidth - 2, h)
        }

        stroke(70)
        strokeWeight(1)
        line(left, top + barHeight, width - 40, top + barHeight)

        noStroke()
        fill(r, g, b)
        textSize(14)
        text(label, left, top - 12)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/05-Random && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `randomSeed(7)` の数字を変えると、2 つのヒストグラムの形は変わりますか。山の位置はどうですか
- `randomGaussian() * 0.13` の `0.13` を `0.3` にすると、山はどうなりますか
- `sampleCount` を 100 まで減らすと、平らなはずの上のグラフはどう見えますか

### ふりかえり

- [ ] `random()` の一様分布と `randomGaussian()` の正規分布の違いが分かった
- [ ] `randomGaussian()` は平均 0・標準偏差 1 なので、掛けて足してから使うと覚えた
- [ ] 散らばりの形の選び方（ばらまくなら一様、個体差なら正規分布）が分かった
- [ ] `randomSeed()` で種を固定すると同じ列が出て、絵を再現できると分かった

### もっと詳しく

- [`random`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/random%28_:_:%29), [`randomGaussian`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/randomgaussian%28_:_:%29), [`randomSeed`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/randomseed%28_:%29)
- [`Basics/Math/Random`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Random), [`Basics/Math/RandomGaussian`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/RandomGaussian), [`Basics/Math/DoubleRandom`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/DoubleRandom)

## 3.6 ノイズ

![ノイズの実行結果](https://i.gyazo.com/6a52759fc76feed26c2e20db146d9fd6.png)

乱数には弱点があります。**隣同士に関係が無い**ことです。毎フレーム `random()` で位置を決めると、図形は暴れるだけで「動いて」は見えません。

Perlin ノイズは、この隣同士のつながりを持った乱数です。`noise()` は 0 から 1 の値を返し、**近い座標には近い値を返します**。

```swift
noise(x)           // 1 次元
noise(x, y)        // 2 次元
noise(x, y, z)     // 3 次元
```

実行結果の上段が、同じ本数の点を乱数とノイズで結んだものです。乱数は上下に飛び、ノイズはつながった曲線になります。下段は 2 次元のノイズを格子状にサンプルして明るさに使ったもので、縦にも横にもつながっているので雲のような模様になります。

大事なのは**入力の刻み幅**です。

```swift
noise(x * 0.012)   // なめらか
noise(x * 0.5)     // ほとんど乱数と変わらない
```

離れた座標をサンプルすれば値の関係は薄くなり、乱数に近づきます。「なめらかさ」はノイズ関数側ではなく、渡す座標の刻み方で決まります。

次元の使い分けはこうなります。

- **1 次元**: 時間で揺らす（`noise(time * 0.5)` で 1 つの値をゆっくり動かす）
- **2 次元**: 模様を作る（座標を渡す）、または「複数のものを別々に揺らす」（1 次元目に個体番号、2 次元目に時間）
- **3 次元**: 2 次元の模様を時間で流す（3 つ目に時間を渡すと、雲が形を変えながら動きます）

`noiseSeed()` で種を固定できるのは乱数と同じです。`noiseDetail()` は細かさの重ね方（オクターブ）を変えるもので、値を大きくするとざらついた質感になります。

<!-- tutorial-snippet: 03-Motion/06-Noise -->
```swift
import metaphor

@main
final class NoiseBasics: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Noise Basics")
    }

    func setup() {
        noLoop()

        // 乱数と同じく、ノイズにも種がある。固定すれば同じ模様が出る
        noiseSeed(4)
        randomSeed(4)
    }

    func draw() {
        background(24)

        let left: Float = 40
        let right = width - 40
        let axis: Float = 108

        // 上段その 1: 乱数で折れ線を引く。隣り合う点に関係が無いので、
        // 毎回てっぺんから底まで飛ぶ
        noFill()
        strokeWeight(2)
        stroke(230, 90, 70)
        beginShape()
        var x = left
        while x <= right {
            vertex(x, axis - random(-42, 42))
            x += 8
        }
        endShape(.open)

        // 上段その 2: ノイズで折れ線を引く。noise() は 0〜1 を返し、
        // 近い座標には近い値を返すので、線がつながって見える
        stroke(110, 200, 160)
        beginShape()
        x = left
        while x <= right {
            vertex(x, axis - (noise(x * 0.012) - 0.5) * 84)
            x += 8
        }
        endShape(.open)

        // 下段: 2 次元のノイズを格子状にサンプルして明るさに使う。
        // 縦にも横にもつながっているので、雲のような模様になる
        noStroke()
        let cell: Float = 8
        var gy: Float = 190
        while gy < height {
            var gx: Float = 0
            while gx < width {
                fill(noise(gx * 0.012, gy * 0.012) * 255)
                rect(gx, gy, cell, cell)
                gx += cell
            }
            gy += cell
        }

        textSize(13)
        fill(230, 90, 70)
        text("random(-42, 42)", left, 42)
        fill(110, 200, 160)
        text("noise(x * 0.012)", left + 190, 42)
        fill(235)
        text("noise(x * 0.012, y * 0.012)", left, 180)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/06-Noise && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- 下段の `noise(gx * 0.012, gy * 0.012)` の係数を `0.05` にすると、雲の粒はどうなりますか
- `setup()` の `noLoop()` を消し、下段を `noise(gx * 0.012, gy * 0.012, time * 0.3)` にすると何が起きますか
- `setup()` に `noiseDetail(octaves: 1)` を足すと、模様の質感はどう変わりますか

### ふりかえり

- [ ] `noise()` が 0〜1 を返し、近い座標には近い値を返すと分かった
- [ ] なめらかさはノイズ側ではなく、渡す座標の刻み幅で決まると分かった
- [ ] 1 次元は時間の揺らぎ、2 次元は模様、3 次元は模様を時間で流す、と使い分けられるようになった
- [ ] `noiseSeed()` / `noiseDetail()` で再現性と質感を調整できると分かった

### もっと詳しく

- [`noise`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/noise%28_:%29), [`noiseSeed`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/noiseseed%28_:%29), [`noiseDetail`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/noisedetail%28octaves:falloff:%29)
- [`Basics/Math/Noise1D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Noise1D), [`Basics/Math/Noise2D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Noise2D), [`Basics/Math/Noise3D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/Noise3D), [`Basics/Math/NoiseWave`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Math/NoiseWave)

## 3.7 ベクトル

![ベクトルの実行結果](https://i.gyazo.com/c89bc9bf7dbdd534420048f1230e4f43.png)

![ベクトルの動き](https://i.gyazo.com/f92dd69e0691270d79edc1235ea8b1d9.webp)

位置を `x` と `y` の 2 変数で持つと、同じ計算を 2 回ずつ書くことになります。まとめて 1 つの値として扱うのが**ベクトル**です。metaphor では `Vec2`（2 次元）と `Vec3`（3 次元）を使います。実体は `SIMD2<Float>` / `SIMD3<Float>` なので、足し算・引き算・スカラー倍がそのまま書けます。

```swift
var position = Vec2(70, 60)
var velocity = Vec2(4.6, 0)
let gravity = Vec2(0, 0.34)

velocity += gravity     // 加速度を速度へ
position += velocity    // 速度を位置へ
```

**この 2 行が動きの本体です**。加速度は速度の変化、速度は位置の変化、という関係をそのまま書き写しただけで、放物線を描いて落ちる動きになります。重力を別のベクトル（風、引力、反発）に差し替えても、書き換わるのは 1 行目だけです。

よく使う操作が生えています。

| 書き方 | 意味 |
|---|---|
| `v.magnitude` | 長さ。速度の長さが「速さ」 |
| `v.normalized()` | 長さ 1 にした同じ向きのベクトル |
| `v.limited(6)` | 長さの上限を決める（速度制限） |
| `v.heading()` | 向きをラジアンで返す |
| `a.dist(to: b)` | 2 点間の距離 |
| `Vec2.fromAngle(a)` | 角度から単位ベクトルを作る |

壁での反射は、ぶつかった軸の符号を反転するだけです。

```swift
if position.x < radius || position.x > width - radius {
    velocity.x *= -1
}
```

`-1` の代わりに `-0.9` を掛けると、跳ねるたびに勢いを失って最後は床で止まります。反発係数と呼ばれる値で、これだけで手触りが変わります。

<!-- tutorial-snippet: 03-Motion/07-Vectors -->
```swift
import metaphor

@main
final class Vectors: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Vectors")
    }

    // 位置・速度・加速度。どれも同じ Vec2（= SIMD2<Float>）で持てる
    var position = Vec2(70, 60)
    var velocity = Vec2(4.6, 0)
    let gravity = Vec2(0, 0.34)

    let radius: Float = 22

    // 通った跡。古いものから捨てていく
    var trail: [Vec2] = []

    func draw() {
        background(24)

        // 動きの本体はこの 2 行。加速度を速度へ、速度を位置へ足すだけ
        velocity += gravity
        position += velocity

        // 壁で向きを反転する。x か y の符号を変えれば跳ね返る
        if position.x < radius || position.x > width - radius {
            velocity.x *= -1
            position.x = constrain(position.x, radius, width - radius)
        }
        if position.y > height - radius {
            velocity.y *= -1
            position.y = height - radius
        }

        trail.append(position)
        if trail.count > 90 {
            trail.removeFirst()
        }

        // 軌跡
        noStroke()
        for (i, p) in trail.enumerated() {
            fill(90, 110, 130, Float(i) / Float(trail.count) * 120)
            circle(p.x, p.y, 8)
        }

        // ベクトルはそのまま矢印として描ける。長さが速さ、向きが進む方向
        strokeWeight(3)
        stroke(240, 190, 80)
        line(position.x, position.y, position.x + velocity.x * 6, position.y + velocity.y * 6)
        stroke(110, 200, 160)
        line(position.x, position.y, position.x + gravity.x * 90, position.y + gravity.y * 90)

        noStroke()
        fill(230, 90, 70)
        circle(position.x, position.y, radius * 2)

        // magnitude はベクトルの長さ。速度の長さが「速さ」になる
        textSize(13)
        fill(240, 190, 80)
        text("velocity  (magnitude = \(rounded(velocity.magnitude)))", 20, 28)
        fill(110, 200, 160)
        text("gravity  (magnitude = \(rounded(gravity.magnitude)))", 20, 48)
    }

    /// 表示用に小数 2 桁へ丸める。
    private func rounded(_ value: Float) -> Float {
        (value * 100).rounded() / 100
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/07-Vectors && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `velocity.x *= -1` を `velocity.x *= -0.9` に変えると、ボールは最後にどうなりますか
- `gravity` を `Vec2(0.1, 0.34)` にすると、軌道はどう傾きますか
- `velocity += gravity` の直後に `velocity = velocity.limited(9)` を足すと、落下はどう変わりますか

### ふりかえり

- [ ] 位置・速度・加速度を `Vec2` としてまとめて扱えるようになった
- [ ] 「加速度を速度へ、速度を位置へ足す」2 行が動きの本体だと分かった
- [ ] `magnitude` / `normalized()` / `limited(_:)` / `dist(to:)` の使いどころが分かった
- [ ] 壁の反射がぶつかった軸の符号の反転で書け、係数を 1 未満にすると勢いを失うと分かった

### もっと詳しく

- [`Vec2`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/vec2), [`Vec3`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/vec3)
- [`Topics/Vectors/VectorMath`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Vectors/VectorMath), [`Topics/Vectors/BouncingBall`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Vectors/BouncingBall), [`Topics/Vectors/AccelerationWithVectors`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Vectors/AccelerationWithVectors)

## 3.8 たくさんのものを動かす

![たくさんのものの実行結果](https://i.gyazo.com/73e1995a2750cb4fe14e52910b2e4941.png)

![たくさんのものの動き](https://i.gyazo.com/312eaf7df9ec1026b7c07615e432a0e5.webp)

動くものが 1 つから 80 個になっても、書くことは増えません。**1 つぶんの状態を型にまとめ、配列で持つ**だけです。

```swift
struct Mover {
    var position: Vec2
    var velocity: Vec2
    var diameter: Float
    var color: Color

    mutating func update(bounds: Vec2) { ... }
}
```

`struct`（構造体）は値をまとめる箱です。中身を書き換えるメソッドには `mutating` を付けます。`class` でも書けますが、独立した粒を大量に扱う場面では構造体のほうが扱いやすく、速くもなります。

`draw()` では**更新のループと描画のループを分けます**。

```swift
for i in movers.indices { movers[i].update(bounds: bounds) }
for mover in movers { fill(mover.color); circle(...) }
```

分ける理由は 2 つあります。1 つは、あとから「更新だけ止める」「描画順だけ変える」「衝突判定を全体が動き終わってから行う」といった変更が入れやすいこと。もう 1 つは、更新の書き方が変わることです。構造体は値型なので、`for mover in movers` で取り出したものを書き換えても**コピーが書き換わるだけで元の配列には反映されません**。更新のときは `movers.indices` と添字を使います。

個体差は `setup()` で配ります。同じ更新式でも、速さ・大きさ・色を乱数で散らすだけで、群れとしての表情が出ます。

```swift
let angle = random(0, TWO_PI)
let speed = random(0.4, 2.4)
velocity: Vec2(cos(angle), sin(angle)) * speed
```

角度と速さから速度ベクトルを作るこの書き方は、向きを均等にばらけさせたいときの定番です。

<!-- tutorial-snippet: 03-Motion/08-ManyObjects -->
```swift
import metaphor

/// 1 つぶんの状態。位置・速度・見た目をまとめて持つ。
struct Mover {
    var position: Vec2
    var velocity: Vec2
    var diameter: Float
    var color: Color

    /// 毎フレームの更新。描画とは分けておくと、あとから止める・数える・
    /// 並べ替えるといった操作がしやすい。
    mutating func update(bounds: Vec2) {
        position += velocity

        // 画面の外へ出たら反対側から入り直す（ラップアラウンド）
        let margin = diameter
        if position.x < -margin { position.x = bounds.x + margin }
        if position.x > bounds.x + margin { position.x = -margin }
        if position.y < -margin { position.y = bounds.y + margin }
        if position.y > bounds.y + margin { position.y = -margin }
    }
}

@main
final class ManyObjects: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Many Objects")
    }

    let moverCount = 80

    // 同じ型の値を配列で持つと、1 つ動かすコードがそのまま全体に効く
    var movers: [Mover] = []

    func setup() {
        randomSeed(3)
        noStroke()

        for _ in 0..<moverCount {
            // 個体ごとに違う値を配ると、同じ更新式でも動きに幅が出る
            let angle = random(0, TWO_PI)
            let speed = random(0.4, 2.4)
            movers.append(Mover(
                position: Vec2(random(0, width), random(0, height)),
                velocity: Vec2(cos(angle), sin(angle)) * speed,
                diameter: random(10, 38),
                color: Color(hue: random(0.5, 0.95), saturation: 0.65, brightness: 1, alpha: 0.85)
            ))
        }
    }

    func draw() {
        background(24)

        let bounds = Vec2(width, height)

        // 更新のループ
        for i in movers.indices {
            movers[i].update(bounds: bounds)
        }

        // 描画のループ
        for mover in movers {
            fill(mover.color)
            circle(mover.position.x, mover.position.y, mover.diameter)
        }

        // 円が全面に散らばるので、ラベルには下敷きを敷いておく
        fill(24, 210)
        rect(12, 12, 122, 26)
        fill(220)
        textSize(13)
        text("movers = \(movers.count)", 20, 30)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/08-ManyObjects && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- 更新のループを `for mover in movers { var m = mover; m.update(bounds: bounds) }` に書き換えると、動きはどうなりますか
- `moverCount` を 800 にすると、絵と速度はどうなりますか
- 画面外でのラップアラウンドを、3.7 のような反射に変えるとどう見えますか

### ふりかえり

- [ ] 1 つぶんの状態を型にまとめ、配列で持つ形が書けるようになった
- [ ] 中身を書き換えるメソッドに `mutating` が要ると分かった
- [ ] 更新のループと描画のループを分ける理由が分かった
- [ ] 構造体は値型なので、更新には `indices` と添字が要ると分かった
- [ ] 角度と速さから速度ベクトルを作ると、向きを均等に散らせると分かった

### もっと詳しく

- [`Sketch`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/) — `draw()` の中での更新と描画
- [`Basics/Objects/Objects`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Objects/Objects), [`Topics/Motion/BouncyBubbles`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Motion/BouncyBubbles)

## 3.9 パーティクル

![パーティクルの実行結果](https://i.gyazo.com/eebdb00db4e0410464ee2efd07d68d46.png)

![パーティクルの動き](https://i.gyazo.com/4e2ac8a91f229ae8275b891930d21b40.webp)

前の節との違いは**数が変わる**ことです。パーティクル（粒子）は生まれて、動いて、消えます。`draw()` はこの 3 つを順に行うだけです。

```swift
for _ in 0..<3 { particles.append(spawn()) }     // 1. 生む
for i in particles.indices { particles[i].update() }  // 2. 動かす
particles.removeAll { $0.life <= 0 }             // 3. 消す
```

消す処理を忘れると配列は増え続け、やがて描画が追いつかなくなります。**生まれる数と消える数が釣り合っているか**が、パーティクルを書くときの最初の確認点です。実行結果に個数を表示しているのはそのためで、しばらく走らせても数が落ち着いていれば釣り合っています。

寿命は 1 から 0 へ減る値として持ち、そのまま見た目に使います。

```swift
fill(255, 170, 90, particle.life * 190)              // 消えぎわは薄く
circle(p.position.x, p.position.y, p.size * p.life)  // 消えぎわは小さく
```

不透明度と大きさの両方に掛けると、粒が消える瞬間が目立ちません。加算合成（`blendMode(.additive)`、2.10）にすると重なった部分が明るくなり、炎や火花のように見えます。

力の加え方は 3.7 と同じです。`update()` の中で速度に加速度を足しています。重力を風や渦に差し替えれば、まったく違う動きになります。

<!-- tutorial-snippet: 03-Motion/09-Particles -->
```swift
import metaphor

/// 粒 1 つぶんの状態。`life` が寿命で、1 から 0 へ減っていく。
struct Particle {
    var position: Vec2
    var velocity: Vec2
    var life: Float
    var size: Float

    mutating func update() {
        // 力を加える = 加速度を速度に足す。ここでは下向きの重力だけ
        velocity += Vec2(0, 0.07)
        position += velocity
        life -= 0.012
    }
}

@main
final class Particles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Particles")
    }

    var particles: [Particle] = []

    func setup() {
        randomSeed(21)
        noStroke()
    }

    func draw() {
        background(18)

        // 1. 生む。毎フレーム決まった数だけ足す
        for _ in 0..<3 {
            particles.append(spawn())
        }

        // 2. 動かす
        for i in particles.indices {
            particles[i].update()
        }

        // 3. 消す。寿命が尽きたものを配列から取り除かないと、増え続ける
        particles.removeAll { $0.life <= 0 }

        // 加算合成にすると、重なったところが明るくなって炎のように見える
        blendMode(.additive)
        for particle in particles {
            // 残り寿命をそのまま不透明度と大きさに使うと、消えぎわが自然になる
            fill(255, 170, 90, particle.life * 190)
            circle(particle.position.x, particle.position.y, particle.size * particle.life)
        }
        blendMode(.alpha)

        fill(190)
        textSize(13)
        text("particles = \(particles.count)", 20, 28)
    }

    /// 画面の下から、上向きに少しばらつかせて 1 つ生む。
    private func spawn() -> Particle {
        let angle = -HALF_PI + random(-0.32, 0.32)
        let speed = random(2.4, 4.8)
        return Particle(
            position: Vec2(width * 0.5, height - 24),
            velocity: Vec2(cos(angle), sin(angle)) * speed,
            life: 1,
            size: random(10, 26)
        )
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/09-Particles && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `particles.removeAll { $0.life <= 0 }` の行を消すと、個数の表示はどうなりますか
- 1 フレームに生む数を 3 から 20 に増やすと、見た目と個数はどう変わりますか
- `velocity += Vec2(0, 0.07)` を `velocity += Vec2(0.05, -0.02)` にすると、粒はどちらへ流れますか

### ふりかえり

- [ ] パーティクルが「生む → 動かす → 消す」の 3 手順で書けると分かった
- [ ] 消す処理を忘れると配列が増え続けるので、個数の釣り合いを見ると覚えた
- [ ] 寿命を 1 から 0 へ減る値として持ち、不透明度と大きさの両方に使うと消えぎわが自然になると分かった
- [ ] 力の加え方が 3.7 と同じで、重力を差し替えれば別の動きになると分かった

### もっと詳しく

- [`blendMode`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/blendmode%28_:%29), [`BlendMode`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/blendmode/)
- [`Topics/Simulate/SimpleParticleSystem`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Simulate/SimpleParticleSystem), [`Topics/Simulate/SmokeParticleSystem`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Simulate/SmokeParticleSystem), [`Topics/Simulate/ForcesWithVectors`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/Simulate/ForcesWithVectors)

## 3.10 数を増やす

![数を増やす実行結果](https://i.gyazo.com/0eeff71f2a315ef3aae6eb9877b9aa54.png)

3 万個の粒を渦に並べて回します。1 個ずつ描くのではなく、配列ごと 1 回で渡すのがこの節の主題です。

粒の数を増やしていくと、どこかでフレームレートが落ちます。落ちる原因は「円を描く計算」よりも、**描画の指示を出す回数**にあることがほとんどです。

metaphor の 2D 描画は、**同じスタイルで続けて呼ばれた図形をひとまとめにして GPU へ送ります**（自動バッチ）。`fill()` や `stroke()` や `strokeWeight()` を変えるとそこでまとまりが切れ、送る回数が増えます。つまり、

```swift
for dot in dots {
    fill(dot.r, dot.g, dot.b)   // ← 1 個ごとにバッチが切れる
    circle(dot.x, dot.y, 3)
}
```

よりも、色を変えずに描いたほうがずっと軽くなります。スタイルの変更を図形ごとではなく**グループごとにまとめる**のが、最初に効く工夫です（詳しくは [ADR-0003](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0003-unified-command-stream.md) にコマンド列の設計と計測があります）。

それでも足りない規模——数万個——には、明示的な一括描画があります。

```swift
var dots: [CircleInstance] = []
// ...
circles(dots)   // 3 万個を 1 回の呼び出しで渡す
```

`CircleInstance` は「位置・直径・色」だけを持つ小さな値です。配列をそのまま `circles()` に渡すと、GPU がインスタンシングでまとめて描きます。ここでは**色をインスタンスが持つ**ので、`fill()` は「塗るかどうか」しか効きません（`noFill()` の状態では描かれません）。逆に `translate()` などの座標変換はバッチ全体にかかります。

使い分けの目安です。

- **数百個まで**: 普通に `circle()` を並べる。スタイルの変更をまとめるだけで足りる
- **数千個から**: スタイルをグループ化し、変更の回数を数えてみる
- **数万個から**: `circles()` に切り替える。1 個ずつ違う色を付けても速度が落ちない

数字はあくまで目安です。実際の限界は解像度・図形の大きさ・重なり具合で変わるので、自分のスケッチで確かめてください。3.1 で見た `deltaTime` を表示すれば、その場で判断できます。

<!-- tutorial-snippet: 03-Motion/10-Massive -->
```swift
import metaphor

@main
final class Massive: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Massive")
    }

    let dotCount = 30_000

    // CircleInstance は「位置・直径・色」だけを持つ小さな値。この配列が
    // そのまま GPU へ渡せる形になっている
    var dots: [CircleInstance] = []

    // 1 粒ずつの軌道。中心からの距離と、いまの角度
    var radii: [Float] = []
    var angles: [Float] = []

    func setup() {
        randomSeed(5)
        noStroke()
        dots.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            // 3 本の腕に振り分け、外側ほど遅れた角度から始めると渦を巻く
            let arm = Float(i % 3) * TWO_PI / 3
            let radius = random(22, 158) + randomGaussian() * 6
            let angle = arm + radius * 0.028 + randomGaussian() * 0.17

            radii.append(radius)
            angles.append(angle)

            dots.append(CircleInstance(
                x: 0,
                y: 0,
                diameter: random(1.2, 3.2),
                color: Color(hue: 0.54 + radius / 900, saturation: 0.75, brightness: 1, alpha: 0.5)
            ))
        }
    }

    func draw() {
        background(10)

        let center = Vec2(width * 0.5, height * 0.5)

        // 位置の更新は CPU 側。ここは普通の配列操作
        for i in dots.indices {
            angles[i] += 0.006
            dots[i].position = center + Vec2(cos(angles[i]), sin(angles[i])) * radii[i]
        }

        blendMode(.additive)

        // 3 万個を 1 回の呼び出しで渡す。円ごとの色はインスタンスが持つので、
        // fill() は「塗るかどうか」しか効かない
        circles(dots)

        blendMode(.alpha)
    }
}
```

実行: `cd Examples/Tutorial/03-Motion/10-Massive && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `dotCount` を 100_000 にすると、動きは保たれますか
- `circles(dots)` を `for dot in dots { fill(Color(dot.color)); circle(dot.position.x, dot.position.y, dot.diameter) }` に書き換えると、どのくらい遅くなりますか
- `blendMode(.additive)` を外すと、重なりの見え方はどう変わりますか

### ふりかえり

- [ ] 速度の限界が図形の計算よりも「描画の指示を出す回数」で決まりやすいと分かった
- [ ] 同じスタイルで続けて呼ぶと自動でまとまり、スタイルを変えるとそこで切れると分かった
- [ ] 数万個には `circles()` に配列ごと渡す一括描画があると分かった
- [ ] 一括描画では色をインスタンスが持ち、`fill()` は「塗るかどうか」しか効かないと分かった

### もっと詳しく

- [`circles`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/circles%28_:%29), [`CircleInstance`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/circleinstance/)
- [`Demos/Performance/MassiveCircles`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Demos/Performance/MassiveCircles)

---

ここまでで、時間から動きを作る道具がひととおり揃いました。次の第 4 部では、動きのきっかけを**外から**受け取ります。
