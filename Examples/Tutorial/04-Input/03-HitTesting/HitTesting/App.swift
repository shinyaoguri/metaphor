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
