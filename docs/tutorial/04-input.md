---
title: 入力を受ける
part: 4
slug: input
description: マウスとキーボードで絵を動かし、当たり判定から UI を組み立て、ウィンドウの設定を扱います。
draft: false
---

# 第 4 部 入力を受ける

第 3 部までのスケッチは、時間だけを頼りに動いていました。この部では動きのきっかけを**外から**受け取ります。

入力の受け取り方は 2 通りです。**毎フレーム値を聞く**（いまマウスはどこか、キーは押されているか）か、**起きた瞬間に呼ばれる関数を書く**（押された、離された）か。この 2 つは競合しません。同じスケッチの中で、目的に応じて使い分けます。

| 受け取り方 | 形 | 向いていること |
|---|---|---|
| 毎フレーム聞く（ポーリング） | `mouseX`, `isMousePressed`, `isKeyDown(_:)` | 位置に追従させる、押している間だけ変える |
| 瞬間に呼ばれる（コールバック） | `mousePressed()`, `keyPressed()` | 1 回だけ起こす（記録、切り替え、生成） |

## この部の前提

第 1 部 1.4 の座標系（原点は左上）と、第 2 部の図形・変換を使います。第 3 部からは 3.1 の `deltaTime`（押しっぱなしの移動をフレームレートに依らせないため）と、3.2 の `constrain()` / `norm()`（4.3 のスライダーで値を範囲に収めるため）が出てきます。

## 4.1 マウス

![マウスでなぞった軌跡。押しながら動かした区間が太い青、押さずに動かした区間が細い灰色で描き分けられ、押した位置に赤い点が付いている](https://i.gyazo.com/69b1224c0d3fb08ef7610cf74546dbc0.png)

マウスの状態は 6 つの値で読めます。座標はすべて**キャンバス座標系**（第 1 部 1.4）で、原点は左上です。

| 名前 | 意味 |
|---|---|
| `mouseX` / `mouseY` | 現在の位置 |
| `pmouseX` / `pmouseY` | 前フレームの位置 |
| `isMousePressed` | いずれかのボタンが押されているか |
| `mouseButton` | 最後に押されたボタン（`.left` / `.right` / `.middle`）。まだ一度も押されていなければ `nil` |

前フレームの位置が取れると、線が引けます。Processing 由来の定番の 1 行です。

```swift
line(pmouseX, pmouseY, mouseX, mouseY)   // 前フレームから今の位置まで結ぶ
```

`background()` を呼ばずにこれを毎フレーム描くと、手書きのような線が残ります。逆に毎フレーム背景で塗り潰せば、線は残らず現在位置だけが見えます。

イベントのコールバックは、実装すれば呼ばれます（`Sketch` プロトコルに既定の空実装があるため、要らないものは書かなくてよい）。

| 関数 | 呼ばれるとき |
|---|---|
| `mousePressed()` | ボタンが押された |
| `mouseReleased()` | ボタンが離された |
| `mouseClicked()` | 押して離すまで動かさなかった（＝クリック） |
| `mouseMoved()` | 押さずに動かした |
| `mouseDragged()` | 押しながら動かした（このとき `mouseMoved()` は呼ばれない） |
| `mouseScrolled()` | ホイールやトラックパッドでスクロールした。量は `scrollX` / `scrollY` |

どちらを使うかは「1 回だけ起こしたいか」で決まります。押した回数を数える、押した位置に印を残す、表示を切り替える——こうした処理を `draw()` の中で `isMousePressed` を見て書くと、押している間ずっと実行されてしまいます。

この節のスケッチは軌跡を**コールバックで溜めています**。`pmouseX` / `pmouseY` を使う 1 行より長い代わりに、2 つの利点があります。1 フレームの間に何度も動いたときも全ての点が残ること、そして起動時の位置（原点）から最初の位置へ線が引かれないことです。

<!-- tutorial-snippet: 04-Input/01-Mouse -->
```swift
import metaphor

/// マウスが通った 1 点。押しながら通ったかどうかで描き分ける。
struct Trace {
    let x: Float
    let y: Float
    let pressed: Bool
}

/// 押した / 離した瞬間の位置。
struct Mark {
    let x: Float
    let y: Float
}

@main
final class Mouse: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Mouse")
    }

    /// マウスが通った跡。古いものから捨てて上限を持たせる
    var trail: [Trace] = []
    /// mousePressed() が呼ばれた位置
    var presses: [Mark] = []
    /// mouseReleased() が呼ばれた位置
    var releases: [Mark] = []

    let maxTrail = 3000

    func draw() {
        background(20)

        drawTrail()
        drawMarks()
        drawCursor()
        drawReadout()
    }

    /// 溜めた点を順に線で結ぶ。押しながら通った区間だけ太く濃くする
    private func drawTrail() {
        guard trail.count >= 2 else { return }
        for index in 1..<trail.count {
            let from = trail[index - 1]
            let to = trail[index]
            if to.pressed {
                stroke(120, 200, 255)
                strokeWeight(6)
            } else {
                stroke(90)
                strokeWeight(1)
            }
            line(from.x, from.y, to.x, to.y)
        }
    }

    /// 押した位置と離した位置。軌跡と違って「瞬間」の記録
    private func drawMarks() {
        for press in presses {
            noStroke()
            fill(255, 90, 80)
            circle(press.x, press.y, 14)
        }
        for release in releases {
            noFill()
            stroke(255, 90, 80)
            strokeWeight(2)
            circle(release.x, release.y, 20)
        }
    }

    /// 現在位置の十字。マウスカーソル自体は絵に写らないので自分で描く
    private func drawCursor() {
        stroke(255)
        strokeWeight(1)
        line(mouseX - 12, mouseY, mouseX + 12, mouseY)
        line(mouseX, mouseY - 12, mouseX, mouseY + 12)
        noFill()
        // isMousePressed は「いま押されているか」を毎フレーム聞ける値
        strokeWeight(isMousePressed ? 3 : 1)
        circle(mouseX, mouseY, isMousePressed ? 30 : 22)
    }

    /// いまの入力の値をそのまま並べる
    private func drawReadout() {
        noStroke()
        fill(220)
        textSize(14)
        text("mouseX = \(Int(mouseX))   mouseY = \(Int(mouseY))", 16, 26)
        text("pmouseX = \(Int(pmouseX))   pmouseY = \(Int(pmouseY))", 16, 48)
        text("isMousePressed = \(isMousePressed)", 16, 70)
        text("mouseButton = \(buttonName)", 16, 92)

        // 絵だけで読み解けるように、線の意味を書いておく
        fill(120, 200, 255)
        text("押しながら動かした跡", 16, 316)
        fill(140)
        text("押さずに動かした跡", 16, 338)
        text("presses = \(presses.count)   releases = \(releases.count)", 430, 338)
    }

    /// `mouseButton` は「最後に押されたボタン」で、まだ一度も押されていなければ nil
    private var buttonName: String {
        switch mouseButton {
        case .left: return "left"
        case .right: return "right"
        case .middle: return "middle"
        case .none: return "nil"
        }
    }

    // ここから下はイベントコールバック。draw() の外で、入力が起きた瞬間に呼ばれる

    /// 押さずに動かしたときに呼ばれる
    func mouseMoved() {
        addTrace()
    }

    /// 押しながら動かしたときに呼ばれる（このとき mouseMoved() は呼ばれない）
    func mouseDragged() {
        addTrace()
    }

    func mousePressed() {
        presses.append(Mark(x: mouseX, y: mouseY))
        addTrace()
    }

    func mouseReleased() {
        releases.append(Mark(x: mouseX, y: mouseY))
        addTrace()
    }

    /// 軌跡に 1 点足す。イベントごとに溜めるので、1 フレームの間に何度動いても
    /// 取りこぼさない
    private func addTrace() {
        trail.append(Trace(x: mouseX, y: mouseY, pressed: isMousePressed))
        if trail.count > maxTrail {
            trail.removeFirst(trail.count - maxTrail)
        }
    }
}
```

実行: `cd Examples/Tutorial/04-Input/01-Mouse && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `background(20)` を `setup()` へ移すと、軌跡を溜めなくても線が残ります。そのとき軌跡の配列は何のために要るでしょうか
- `mouseDragged()` の中の `addTrace()` を消すと、押しながら動かした跡はどう変わりますか
- `mouseClicked()` を足して印を打つと、`mouseReleased()` の印とどこが違いますか（押してから動かして離すと分かります）

### ふりかえり

- [ ] `mouseX` / `mouseY` / `pmouseX` / `pmouseY` / `isMousePressed` を読めるようになった
- [ ] マウス座標がキャンバス座標系（原点は左上）で届くと分かった
- [ ] `line(pmouseX, pmouseY, mouseX, mouseY)` で線が引ける定番の 1 行を覚えた
- [ ] 「1 回だけ起こしたいこと」はコールバックに書く、と使い分けられるようになった
- [ ] `mouseDragged()` が呼ばれる間は `mouseMoved()` が呼ばれないと分かった

### もっと詳しく

- [`mouseX`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/mousex), [`mouseY`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/mousey), [`pmouseX`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/pmousex), [`isMousePressed`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/ismousepressed), [`MouseButton`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/mousebutton/)
- [`Basics/Input/Mouse2D`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/Mouse2D), [`Basics/Input/MousePress`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/MousePress), [`Basics/Input/MouseFunctions`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/MouseFunctions), [`Basics/Input/StoringInput`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/StoringInput)

## 4.2 キーボード

![矢印キーで動かしたオレンジの四角と、その通り道。左上にキーコードと押されている矢印キー、下に打ち込んだ文字が出ている](https://i.gyazo.com/38db525078805ca12f02fc149e824c85.png)

キーボードもマウスと同じ 2 通りで受け取ります。ただし**押しっぱなし**の扱いに癖があります。

読める値は 4 つです。

| 名前 | 意味 |
|---|---|
| `key` | 最後に押されたキーの文字（`Character?`） |
| `keyCode` | 最後に押されたキーのキーコード（`UInt16?`） |
| `isKeyPressed` | 何らかのキーが押されているか |
| `isKeyRepeat` | 直前のキー押下がオートリピートによるものか |

`key` は文字なので、`"a"` や `" "` のように比較できます。矢印キーやファンクションキーには文字が無く、代わりに画面に出せない特殊な文字が入ります。そうしたキーは `keyCode` で見分けます。よく使うキーコードには定数が用意されています（`LEFT` / `RIGHT` / `UP` / `DOWN` / `SPACE` / `RETURN` / `ENTER` / `TAB` / `ESCAPE` / `SHIFT` / `COMMAND` など）。

```swift
if keyCode == SPACE { ... }   // 数値の 49 を覚える必要はない
```

**押しっぱなし**を扱うときは `isKeyDown(_:)` を使います。「そのキーがいま押されているか」を 1 つずつ聞ける関数で、同時押しにそのまま対応できます。`key` は最後に押された 1 つしか覚えていないので、2 つのキーを同時に押したときは片方しか見えません。

```swift
if isKeyDown(LEFT) { x -= step }    // 左と上を同時に押せば斜めに動く
if isKeyDown(UP) { y -= step }
```

移動量を**フレーム数ではなく時間で決める**のがコツです（第 3 部 3.1）。`step` を固定値にするとフレームレート次第で速さが変わってしまうので、`speed * deltaTime` にします。

コールバックは 3 つあります。

| 関数 | 呼ばれるとき |
|---|---|
| `keyPressed()` | キーが押された。**押しっぱなしの間はオートリピートで何度も呼ばれる** |
| `keyReleased()` | キーが離された |
| `keyTyped()` | 文字を生むキーが押された（矢印・ファンクションキーでは呼ばれない） |

押した回数を数えたい、1 回だけ切り替えたい、というときはオートリピートを弾きます。

```swift
func keyPressed() {
    if isKeyRepeat { return }   // 2 回目以降の自動発火は無視する
    ...
}
```

なお `keyReleased()` の中で `keyCode` を読むと、「離されたキー」ではなく「最後に押されたキー」が返ります。どのキーが離されたかで処理を分けたいときは、押した側で覚えておきます。

<!-- tutorial-snippet: 04-Input/02-Keyboard -->
```swift
import metaphor

@main
final class Keyboard: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Keyboard")
    }

    /// 動かす四角の位置
    var x: Float = 320
    var y: Float = 200
    /// 通った跡
    var trail: [(x: Float, y: Float)] = []
    /// 打った文字。keyPressed() で 1 文字ずつ足す
    var typed = ""
    /// Space を押すたびに進む色の番号
    var colorIndex = 0
    /// keyPressed() が「単発として」呼ばれた回数（オートリピートは数えない）
    var pressCount = 0
    /// keyReleased() が呼ばれた回数
    var releaseCount = 0

    /// 1 秒あたりに動く距離。フレーム数ではなく時間で動かすので、
    /// フレームレートが変わっても押していた時間ぶんだけ動く
    let speed: Float = 220

    let palette: [(Float, Float, Float)] = [
        (110, 200, 255), (255, 170, 90), (150, 230, 150), (240, 120, 170),
    ]

    func draw() {
        background(18)

        // isKeyDown(_:) は「そのキーがいま押されているか」。押しっぱなしの間ずっと
        // true なので、毎フレーム少しずつ動かせる。同時押しも自然に扱える
        let step = speed * deltaTime
        if isKeyDown(LEFT) { x -= step }
        if isKeyDown(RIGHT) { x += step }
        if isKeyDown(UP) { y -= step }
        if isKeyDown(DOWN) { y += step }
        x = constrain(x, 30, width - 30)
        y = constrain(y, 90, height - 60)

        if let last = trail.last, abs(last.x - x) < 1, abs(last.y - y) < 1 {
            // 動いていないフレームは記録しない
        } else {
            trail.append((x: x, y: y))
            if trail.count > 900 { trail.removeFirst() }
        }

        drawTrail()
        drawBox()
        drawReadout()
    }

    private func drawTrail() {
        guard trail.count >= 2 else { return }
        stroke(70)
        strokeWeight(1)
        for index in 1..<trail.count {
            line(trail[index - 1].x, trail[index - 1].y, trail[index].x, trail[index].y)
        }
    }

    private func drawBox() {
        let (r, g, b) = palette[colorIndex % palette.count]
        noStroke()
        fill(r, g, b)
        rect(x - 18, y - 18, 36, 36)
    }

    private func drawReadout() {
        noStroke()
        fill(220)
        textSize(14)
        text("key = \(keyDescription)", 16, 26)
        text("keyCode = \(keyCode.map(String.init) ?? "nil")", 16, 48)
        text("isKeyPressed = \(isKeyPressed)   isKeyRepeat = \(isKeyRepeat)", 16, 70)
        text("押されている矢印キー = \(heldArrows)", 16, 92)

        fill(150)
        text("矢印キーで移動（同時押しで斜めに）   Space で色   文字キーで下に文字", 16, 330)
        fill(220)
        textSize(20)
        text(typed.isEmpty ? "-" : typed, 16, 306)
        fill(150)
        textSize(14)
        text("keyPressed() = \(pressCount) 回   keyReleased() = \(releaseCount) 回", 350, 306)
    }

    /// いま押されている矢印キーの一覧。`key` は最後の 1 つしか持てないので、
    /// 同時押しを知るには押されているかを 1 つずつ聞く
    private var heldArrows: String {
        var held: [String] = []
        if isKeyDown(LEFT) { held.append("←") }
        if isKeyDown(RIGHT) { held.append("→") }
        if isKeyDown(UP) { held.append("↑") }
        if isKeyDown(DOWN) { held.append("↓") }
        return held.isEmpty ? "なし" : held.joined(separator: " ")
    }

    /// `key` は「最後に押されたキーの文字」。矢印キーのように文字を持たない
    /// キーでは、画面に出せない特殊な文字が入る
    private var keyDescription: String {
        guard let key else { return "nil" }
        if key.isLetter || key.isNumber || key.isPunctuation {
            return "\"\(key)\""
        }
        if key == " " { return "\" \" (Space)" }
        return "表示できない文字"
    }

    func keyPressed() {
        // 押しっぱなしにすると、OS はオートリピートの keyDown を送り続ける。
        // 「押した回数」を数えたいときは、それを弾く必要がある
        if isKeyRepeat { return }
        pressCount += 1

        if keyCode == SPACE {
            colorIndex += 1
            return
        }
        if let key, key.isLetter || key.isNumber {
            typed.append(key)
            if typed.count > 24 { typed.removeFirst() }
        }
    }

    func keyReleased() {
        // 離した瞬間に呼ばれる。矢印キーの移動を止めるために書くことは無い
        // （isKeyDown(_:) が false になるだけで止まる）。
        // なお、ここで `keyCode` を読むと「最後に離したキー」ではなく
        // 「最後に押したキー」が返る。どのキーが離されたかを使いたいときは、
        // 押した側で覚えておく必要がある
        releaseCount += 1
    }
}
```

実行: `cd Examples/Tutorial/04-Input/02-Keyboard && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `keyPressed()` の先頭の `if isKeyRepeat { return }` を消して、キーを押しっぱなしにすると、`keyPressed()` の回数はどうなりますか
- `speed * deltaTime` を固定値の `3` に変えると、`config` の `fps` を 30 にしたときの速さはどう変わりますか
- `isKeyDown(LEFT)` の代わりに `keyCode == LEFT` で移動を書くと、同時押しはどう振る舞いますか

### ふりかえり

- [ ] `key` は文字、`keyCode` はキーコードで、特殊キーは後者で見分けると分かった
- [ ] `LEFT` / `SPACE` などの定数を使って数値を覚えずに書けるようになった
- [ ] 同時押しは `isKeyDown(_:)` で 1 つずつ聞く、と覚えた
- [ ] 押しっぱなしの移動量は `speed * deltaTime` で決めると分かった
- [ ] `keyPressed()` はオートリピートで何度も呼ばれるので、`isKeyRepeat` で弾けると分かった

### もっと詳しく

- [`key`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/key), [`keyCode`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/keycode), [`isKeyDown`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/iskeydown%28_:%29), [`isKeyRepeat`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/iskeyrepeat)
- [`Basics/Input/Keyboard`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/Keyboard), [`Basics/Input/KeyboardFunctions`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Basics/Input/KeyboardFunctions)

## 4.3 当たり判定と UI を自作する

![自作の UI。緑の ON ボタン、つまみを掴んだ状態の青いスライダー、その 2 つの値から大きさを決めた桃色の円](https://i.gyazo.com/3a6f3be2704b68b08c9cd3196979458d.png)

metaphor には調整用の GUI が用意されていますが（`@Param` と `gui.params()`。第 8 部 8.4）、ボタンやスライダーを**自分で描いて自分で判定する**やり方を一度通ると、画面の中の何にでも反応させられるようになります。必要なのは 2 つの判定だけです。

矩形の中にあるか。4 つの比較を並べます。

```swift
let inside = px >= x && px <= x + w && py >= y && py <= y + h
```

円の中にあるか。中心からの距離を半径と比べます。距離は `dist()` が計算します。

```swift
let inside = dist(px, py, cx, cy) <= radius
```

判定を「図形の持ち物」にしておくと、部品が増えても書く場所が 1 つに決まります。この節のスケッチが `Box` 構造体に `contains(_:_:)` を持たせているのはそのためです。

UI の手触りは、状態の数で決まります。

- **hover**: マウスが上にあるか。毎フレーム判定する
- **press**: hover に加えて押されているか。押されている見た目（沈む、濃くなる）に使う
- **drag**: 掴んだあと、マウスが部品から外れても追従させる。掴んでいるかを**自分で覚える**

ドラッグは「押した瞬間に掴み、離した瞬間に放す」と書きます。掴んでいる間は毎フレーム `mouseX` を値に反映し、`constrain()`（第 3 部 3.2）で範囲に収めます。マウスが溝の外へ出ても値が飛ばないのは、判定を押した瞬間の 1 回だけにしているからです。

ボタンは「同じボタンの上で押して離した」ときだけ作動させます。押した場所を覚えておき、離した場所と両方が同じ部品かを見ます。押してから外へ逃がして離せば作動しない——押し間違いを取り消せる、という作法です。

<!-- tutorial-snippet: 04-Input/03-HitTesting -->
```swift
import metaphor

/// 矩形の領域。内外判定を持たせておくと、当たり判定を書く場所が 1 つに決まる。
struct Box {
    let x: Float
    let y: Float
    let w: Float
    let h: Float

    /// 点が矩形の中にあるか。4 つの比較を並べるだけ
    func contains(_ px: Float, _ py: Float) -> Bool {
        px >= x && px <= x + w && py >= y && py <= y + h
    }
}

@main
final class HitTesting: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "HitTesting")
    }

    /// 押すたびに切り替わるボタン
    let button = Box(x: 60, y: 70, w: 170, h: 56)
    var buttonOn = false

    /// スライダーの溝。ハンドルはこの上を左右に動く
    let track = Box(x: 60, y: 210, w: 380, h: 8)
    /// ハンドルの中心の x。溝の左端から右端の間を動く
    var handleX: Float = 150
    let handleRadius: Float = 16
    /// ハンドルを掴んでいるか。掴んでいる間はマウスが溝から離れても追従させる
    var dragging = false
    /// ボタンの上で押し始めたか。押した場所と離した場所が同じ部品のときだけ作動させる
    var pressedInButton = false

    func draw() {
        background(22)

        // ドラッグ中はマウスの x をそのままハンドルへ渡す。溝からはみ出さないように
        // constrain で挟む（第 3 部 3.2）
        if dragging {
            handleX = constrain(mouseX, track.x, track.x + track.w)
        }

        drawButton()
        drawSlider()
        drawResult()
        drawCursor()
    }

    private func drawButton() {
        // 「マウスが上にあるか」は毎フレーム聞く。押している最中はさらに沈んで見せる
        let hovering = button.contains(mouseX, mouseY)
        let pushing = hovering && isMousePressed

        if buttonOn {
            fill(pushing ? 60 : 90, pushing ? 150 : 200, 130)
        } else {
            fill(pushing ? 45 : (hovering ? 70 : 55))
        }
        stroke(hovering ? 230 : 110)
        strokeWeight(hovering ? 2 : 1)
        rect(button.x, button.y, button.w, button.h)

        noStroke()
        fill(235)
        textSize(16)
        text(buttonOn ? "ON" : "OFF", button.x + 20, button.y + 34)
        fill(150)
        textSize(12)
        text(hovering ? "hover 中" : "", button.x + 100, button.y + 34)
        text("ボタン（押して離すと切り替わる）", button.x, button.y - 10)
    }

    private func drawSlider() {
        let hovering = overHandle

        noStroke()
        fill(60)
        rect(track.x, track.y, track.w, track.h)
        // 左端からハンドルまでを塗って、値の大きさを見せる
        fill(110, 170, 240)
        rect(track.x, track.y, handleX - track.x, track.h)

        if dragging {
            fill(255, 210, 120)
        } else if hovering {
            fill(200, 225, 255)
        } else {
            fill(150)
        }
        circle(handleX, sliderY, handleRadius * 2)

        fill(150)
        textSize(12)
        text("スライダー（ハンドルを掴んで動かす）", track.x, track.y - 22)
        text(dragging ? "掴んでいる" : (hovering ? "hover 中" : ""), track.x, track.y + 44)
    }

    private func drawResult() {
        // スライダーの値（0〜1）を絵に反映する。UI は値を作るための道具で、
        // 値をどう使うかは別に書く
        let value = norm(handleX, track.x, track.x + track.w)
        noStroke()
        fill(buttonOn ? 240 : 90, 200, 255)
        let size = 30 + value * 120
        circle(540, 150, size)

        fill(190)
        textSize(13)
        text("value = \((value * 100).rounded() / 100)", 470, 262)
        text("buttonOn = \(buttonOn)", 470, 284)
        fill(140)
        textSize(12)
        text("2 つの値で描いた円", 470, 306)
    }

    /// マウスカーソルは絵に写らないので自分で描く
    private func drawCursor() {
        stroke(255)
        strokeWeight(1)
        line(mouseX - 10, mouseY, mouseX + 10, mouseY)
        line(mouseX, mouseY - 10, mouseX, mouseY + 10)
    }

    /// スライダーのハンドルの中心の y（溝の中心）
    private var sliderY: Float { track.y + track.h / 2 }

    /// マウスがハンドルの上にあるか。円の判定は「中心からの距離が半径以下か」
    private var overHandle: Bool {
        dist(mouseX, mouseY, handleX, sliderY) <= handleRadius
    }

    func mousePressed() {
        // 押した瞬間に「どこを押したか」を覚える。ハンドルなら掴んだ状態にし、
        // ボタンなら作動させずに印だけ付ける（作動は離したとき）
        if overHandle {
            dragging = true
        }
        pressedInButton = button.contains(mouseX, mouseY)
    }

    func mouseReleased() {
        // ボタンは「同じボタンの上で押して離した」ときだけ作動する。押してから
        // 外へ逃がして離せば作動しない — 押し間違いを取り消せる、という作法
        if pressedInButton, button.contains(mouseX, mouseY) {
            buttonOn.toggle()
        }
        pressedInButton = false
        dragging = false
    }
}
```

実行: `cd Examples/Tutorial/04-Input/03-HitTesting && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `mouseReleased()` の判定から `pressedInButton` を外すと、外で押して中で離したときに何が起きますか
- `dragging` を使わず「マウスがハンドルの上にあり、かつ押されている」で値を更新すると、速く動かしたときにどうなりますか
- ボタンを円にして、`contains(_:_:)` を距離の判定に置き換えてみてください

### ふりかえり

- [ ] 矩形は 4 つの比較、円は `dist()` と半径の比較で内外を判定できるようになった
- [ ] 判定を図形の持ち物（`contains(_:_:)`）にしておくと書く場所が 1 つに決まると分かった
- [ ] hover / press / drag という 3 つの状態の違いが分かった
- [ ] ドラッグは掴んだかどうかを自分で覚え、部品から外れても追従させると分かった
- [ ] ボタンは「同じ部品の上で押して離した」ときだけ作動させる作法を覚えた

### もっと詳しく

- [`constrain`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/constrain%28_:_:_:%29), [`norm`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/norm%28_:_:_:%29), [`dist`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/dist%28_:_:_:_:%29)
- [`Topics/GUI/Button`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/GUI/Button), [`Topics/GUI/Rollover`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/GUI/Rollover), [`Topics/GUI/Handles`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/GUI/Handles), [`Topics/GUI/Scrollbar`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Topics/GUI/Scrollbar)

## 4.4 ウィンドウ

![キャンバス 640x360 の枠の中に、ウィンドウ 320x180 の枠が入れ子で描かれている。右には横長・縦長のウィンドウで絵の左右・上下に余白が付く様子](https://i.gyazo.com/15abff75e038538fae6657c390881951.png)

入力を扱い始めると、座標がどの空間の値なのかが気になります。metaphor は**レンダリング解像度とウィンドウの大きさを分けて**持っているためです。

`config` の `width` / `height` は**レンダリング解像度**、つまり絵を描く座標系の大きさです。ウィンドウの大きさは `windowScale` で決まります（ウィンドウ = 解像度 × `windowScale`）。既定は `0.5` なので、`1920x1080` のスケッチは `960x540` のウィンドウに出ます。

```swift
SketchConfig(width: 640, height: 360, title: "Window", windowScale: 0.5)
```

大事なのは、**マウス座標はいつもキャンバス座標系で届く**ことです。ウィンドウを引き伸ばしても、フルスクリーンにしても、`mouseX` は `0` から `width` の範囲で報告されます。ウィンドウの実サイズを気にしてスケッチ側で換算する必要はありません。

ウィンドウの縦横比がキャンバスと違うときは、縦横比を保ったまま余白が入ります（上下に帯なら**レターボックス**、左右なら**ピラーボックス**）。絵が引き伸ばされて歪むことはありません。この転送は 2 パス構成の後半（ブリットパス）が受け持っています。

フルスクリーンで始めるには `config` で指定します。

```swift
SketchConfig(width: 1920, height: 1080, title: "Show", fullScreen: true)
```

`setup()` の中で解像度を決めることもできます（p5.js 風の書き方）。

```swift
func setup() {
    createCanvas(width: 1280, height: 720)
}
```

2 つ目以降のウィンドウは `createWindow()` で開き、返ってきた `SketchWindow` に描画クロージャを渡します。ウィンドウごとに独立した `SketchContext` と `InputManager` を持つので、入力もウィンドウ単位で受け取れます。

```swift
var child: SketchWindow?

func setup() {
    child = createWindow(SketchWindowConfig(width: 400, height: 400, title: "Second"))
}

func draw() {
    background(20)
    child?.draw { ctx in
        ctx.background(0)
        ctx.circle(ctx.width / 2, ctx.height / 2, 120)
        if ctx.input.isMouseDown { ... }   // 子ウィンドウの入力はこちら
    }
}
```

カーソルの表示は `noCursor()` と `cursor()` で切り替えられます。作品を出すときは、カーソルを隠して自分で描いた印を出すと画面が締まります。

### いまできないこと

ウィンドウのリサイズを知らせるコールバックはありません。ウィンドウを引き伸ばしてもレンダリング解像度は変わらない（余白が増減するだけ）ので、多くのスケッチでは気になりませんが、「ウィンドウに合わせて絵の構図を変える」ことは現状できません。

<!-- tutorial-snippet: 04-Input/04-Window -->
```swift
import metaphor

@main
final class Window: Sketch {
    /// レンダリング解像度。絵を描く座標系の大きさで、ウィンドウの大きさとは別
    let renderWidth = 640
    let renderHeight = 360
    /// ウィンドウの大きさ = レンダリング解像度 × この係数
    let scale: Float = 0.5

    var config: SketchConfig {
        SketchConfig(
            width: renderWidth,
            height: renderHeight,
            title: "Window",
            windowScale: scale
        )
    }

    func draw() {
        background(20)

        fill(230)
        textSize(15)
        text("レンダリング解像度とウィンドウは別もの", 24, 34)

        drawScaleMap()
        drawFitDiagram()

        fill(150)
        textSize(12)
        text("width = \(Int(width))   height = \(Int(height))   windowScale = \(scale)", 24, 340)
    }

    /// 解像度とウィンドウサイズの対応。入れ子の枠で縮尺の関係を見せる
    private func drawScaleMap() {
        let x: Float = 24
        let y: Float = 56
        let w: Float = 260
        let h = w * height / width

        noFill()
        stroke(120, 190, 255)
        strokeWeight(2)
        rect(x, y, w, h)

        stroke(255, 190, 110)
        rect(x, y, w * scale, h * scale)

        noStroke()
        fill(120, 190, 255)
        textSize(12)
        text("キャンバス \(renderWidth)x\(renderHeight)", x + 4, y + h + 18)
        fill(255, 190, 110)
        let windowWidth = Int(Float(renderWidth) * scale)
        let windowHeight = Int(Float(renderHeight) * scale)
        text("ウィンドウ \(windowWidth)x\(windowHeight)", x + 4, y + h * scale - 8)

        fill(170)
        text("ウィンドウをどう伸ばしても、マウス座標は", x, y + h + 44)
        text("キャンバスの 0〜\(Int(width)) / 0〜\(Int(height)) で届く", x, y + h + 64)
    }

    /// ウィンドウの縦横比がキャンバスと違うときの余白。帯がどちら側に入るかを見せる
    private func drawFitDiagram() {
        let base: Float = 330
        drawFit(x: base, y: 66, w: 270, h: 106, label: "横長のウィンドウ")
        drawFit(x: base, y: 214, w: 145, h: 126, label: "縦長のウィンドウ")

        noStroke()
        fill(120)
        textSize(12)
        text("縦横比が違うぶんは", base + 165, 246)
        text("余白になり、絵は", base + 165, 266)
        text("歪まない", base + 165, 286)
    }

    /// 1 つのウィンドウ枠と、その中に収まるキャンバスを描く
    private func drawFit(x: Float, y: Float, w: Float, h: Float, label: String) {
        // 縦横比を保って収まる大きさ（実際のブリットパスと同じ考え方）
        let fit = min(w / width, h / height)
        let innerW = width * fit
        let innerH = height * fit
        let innerX = x + (w - innerW) / 2
        let innerY = y + (h - innerH) / 2

        noStroke()
        fill(38)
        rect(x, y, w, h)
        fill(60, 90, 130)
        rect(innerX, innerY, innerW, innerH)

        noFill()
        stroke(110)
        strokeWeight(1)
        rect(x, y, w, h)

        noStroke()
        fill(170)
        textSize(12)
        text(label, x, y - 8)
    }
}
```

実行: `cd Examples/Tutorial/04-Input/04-Window && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `windowScale` を `1.0` にすると、ウィンドウはどのくらいの大きさになりますか。絵の中の数字は変わりますか
- `createCanvas(width: 320, height: 180)` を `setup()` に足すと、`width` / `height` と図はどう変わりますか
- `noCursor()` を `setup()` に足して、4.1 のスケッチと組み合わせてみてください

### ふりかえり

- [ ] ウィンドウの大きさが「レンダリング解像度 × `windowScale`」だと分かった
- [ ] ウィンドウをどう変えてもマウス座標がキャンバス座標系で届くと分かった
- [ ] 縦横比が違うぶんは余白になり、絵は歪まないと分かった
- [ ] `fullScreen` / `createCanvas()` / `createWindow()` / `noCursor()` の使いどころが分かった
- [ ] リサイズを知らせるコールバックがまだ無いと分かった

### もっと詳しく

- [`SketchConfig`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketchconfig/), [`createCanvas`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createcanvas%28width:height:%29), [`createWindow`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/createwindow%28_:%29), [`SketchWindow`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketchwindow/), [`noCursor`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketch/nocursor%28%29)
- [`Demos/Tests/MultipleWindows`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Demos/Tests/MultipleWindows), [`Samples/Syphon/SyphonMultiWindow`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Samples/Syphon/SyphonMultiWindow)

---

ここまでで、絵は時間と入力の両方に応じて動くようになりました。次の第 5 部では、同じ語彙のまま**奥行き**を足します。
