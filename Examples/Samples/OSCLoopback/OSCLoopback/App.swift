import metaphor

// OSC Loopback
// OSCSender でマウス位置を送信し、同一プロセスの OSCReceiver で受けて円を描く
// 送受ループの例。送信先の host/port を変えれば TouchDesigner / Max / TouchOSC 等の
// 外部ツールへそのまま送れる（受信側も同じポートを聞けば双方向になる）。

@main
final class OSCLoopback: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "OSCLoopback")
    }

    let port: UInt16 = 12000
    var sender: OSCSender?
    var receiver: OSCReceiver?
    var received = Vec2.zero

    func setup() {
        receiver = createOSCReceiver(port: port)
        receiver?.on("/mouse") { [weak self] values in
            guard case .float(let x) = values.first,
                  values.count > 1, case .float(let y) = values[1] else { return }
            self?.received = Vec2(x, y)
        }
        do {
            try receiver?.start()
        } catch {
            print("Failed to start OSC receiver: \(error)")
        }
        sender = createOSCSender(host: "127.0.0.1", port: port)
    }

    func draw() {
        background(51)

        // マウス位置を毎フレーム OSC 送信
        sender?.send("/mouse", .float(mouseX), .float(mouseY))

        // 受信キューを処理(登録したハンドラが呼ばれる)
        receiver?.poll()

        // 受信した座標に円を描く
        stroke(255)
        strokeWeight(2)
        fill(120, 180, 255)
        circle(received.x, received.y, 40)

        fill(255)
        textAlign(.left)
        textSize(12)
        text("sending /mouse to 127.0.0.1:\(port) and drawing what comes back", 10, height - 10)
    }
}
