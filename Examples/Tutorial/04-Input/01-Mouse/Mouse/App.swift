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
