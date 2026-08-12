import metaphor

@main
final class OSCSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "OSC")
    }

    // 送信先は自分自身。外部アプリへ送るなら host を相手のアドレスに変える
    let host = "127.0.0.1"
    let port: UInt16 = 9000

    var sender: OSCSender?
    var receiver: OSCReceiver?

    // 受信して初めて入る値。送った値をそのまま描かないのがこのスケッチの要点
    var received: Vec2?
    var receivedSize: Float = 0
    var log = "まだ 1 通も届いていません"

    func setup() {
        let receiver = createOSCReceiver(port: port)

        // アドレスごとにハンドラを登録する。呼ばれるのは poll() の中だけ
        receiver.on("/pointer") { [weak self] values in
            guard values.count >= 3,
                case .float(let x) = values[0],
                case .float(let y) = values[1],
                case .float(let size) = values[2]
            else { return }  // 型や個数が違う相手からのメッセージは黙って捨てる
            self?.received = Vec2(x, y)
            self?.receivedSize = size
        }

        do {
            // ポートが他のアプリに使われていると投げる
            try receiver.start()
            self.receiver = receiver
        } catch {
            log = "ポート \(port) を開けませんでした: \(error.localizedDescription)"
        }

        // 作れなかったときは nil が返る（理由はコンソールへ）
        sender = createOSCSender(host: host, port: port)
    }

    func draw() {
        background(16)

        // 送る — マウスの位置と、そこから決めた大きさを 3 つの float で
        let size = map(mouseY, 0, height, 30, 110)
        sender?.send("/pointer", .float(mouseX), .float(mouseY), .float(size))

        // 受ける — poll() が届いた順にハンドラを呼び、同じものを返す
        for message in receiver?.poll() ?? [] {
            log = ([message.address] + message.values.map(describe)).joined(separator: "  ")
        }

        drawSent()
        drawReceived()
        drawPanel()
    }

    /// 送った位置。細い十字で置く
    private func drawSent() {
        stroke(Color(gray: 0.55))
        strokeWeight(1)
        line(mouseX - 14, mouseY, mouseX + 14, mouseY)
        line(mouseX, mouseY - 14, mouseX, mouseY + 14)
    }

    /// 返ってきた位置。塗りの円で置く。往復が成立していれば十字に重なる
    private func drawReceived() {
        guard let received else { return }
        noStroke()
        fill(Color(r: 0.3, g: 0.75, b: 1, a: 0.85))
        circle(received.x, received.y, receivedSize)
    }

    private func drawPanel() {
        noStroke()
        fill(Color(gray: 0, alpha: 0.55))
        rect(0, height - 76, width, 76)

        fill(Color(gray: 0.95))
        textSize(13)
        textAlign(.left, .top)
        text("送信 → \(host):\(port)   /pointer x y size", 16, height - 66)
        text("受信 ← \(log)", 16, height - 46)

        fill(Color(gray: 0.65))
        textSize(11)
        text("十字が送った位置、円が返ってきた位置", 16, height - 24)
    }

    /// OSC の値は型ごとに case が分かれている。表示のために文字列へ均す
    private func describe(_ value: OSCValue) -> String {
        switch value {
        case .float(let v): return String(format: "%.1f", v)
        case .int(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .blob(let data): return "<\(data.count) バイト>"
        }
    }
}
