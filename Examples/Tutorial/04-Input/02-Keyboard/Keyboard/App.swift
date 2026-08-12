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
