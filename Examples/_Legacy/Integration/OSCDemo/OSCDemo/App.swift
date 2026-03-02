import metaphor

/// Feature 9: OSC レシーバー
///
/// UDP ポート 9000 で OSC メッセージを受信し、ビジュアルに反映する。
/// 外部の OSC 送信アプリ（TouchOSC, Max/MSP, Pure Data 等）から
/// 以下のアドレスにメッセージを送信して試す:
///
///   /color   f f f     → RGB (0.0〜1.0)
///   /size    f         → 円のサイズ
///   /pos     f f       → 位置 (0.0〜1.0, 正規化)
///   /note    i         → ノートオン（パルス効果）
///
/// テスト送信例（oscsend コマンド）:
///   oscsend localhost 9000 /color fff 1.0 0.0 0.5
///   oscsend localhost 9000 /size f 200.0
///   oscsend localhost 9000 /pos ff 0.5 0.5
@main
final class OSCDemoExample: Sketch {
    var osc: OSCReceiver!

    // OSC で制御されるパラメータ
    var circleColor = Color(r: 0.3, g: 0.7, b: 1.0)
    var circleSize: Float = 150
    var posX: Float = 0.5
    var posY: Float = 0.5
    var pulse: Float = 0.0

    // メッセージログ
    var messageLog: [(time: Float, msg: String)] = []

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "OSC Receiver (Port 9000)")
    }

    func setup() {
        osc = createOSCReceiver(port: 9000)

        osc.on("/color") { [self] values in
            if values.count >= 3,
               case .float(let r) = values[0],
               case .float(let g) = values[1],
               case .float(let b) = values[2] {
                circleColor = Color(r: r, g: g, b: b)
                addLog("/color \(r) \(g) \(b)")
            }
        }

        osc.on("/size") { [self] values in
            if case .float(let s) = values.first {
                circleSize = s
                addLog("/size \(s)")
            }
        }

        osc.on("/pos") { [self] values in
            if values.count >= 2,
               case .float(let x) = values[0],
               case .float(let y) = values[1] {
                posX = x
                posY = y
                addLog("/pos \(x) \(y)")
            }
        }

        osc.on("/note") { [self] values in
            if case .int(_) = values.first {
                pulse = 1.5
                addLog("/note")
            }
        }

        // 全メッセージをログに記録
        osc.onAny { [self] address, values in
            let desc = values.map { v -> String in
                switch v {
                case .int(let i): return "\(i)"
                case .float(let f): return String(format: "%.2f", f)
                case .string(let s): return "\"\(s)\""
                case .blob(let d): return "blob(\(d.count))"
                }
            }.joined(separator: " ")
            if !["/color", "/size", "/pos", "/note"].contains(address) {
                addLog("\(address) \(desc)")
            }
        }

        do {
            try osc.start()
        } catch {
            addLog("OSC start failed: \(error)")
        }
    }

    func addLog(_ msg: String) {
        messageLog.append((time: time, msg: msg))
        if messageLog.count > 15 { messageLog.removeFirst() }
    }

    func draw() {
        // OSC メッセージをポーリング
        osc.poll()

        background(Color(gray: 0.05))

        // パルス減衰
        pulse = max(0, pulse - deltaTime * 3)

        // --- メイン円 ---
        let cx = posX * width
        let cy = posY * height
        let size = circleSize * (1.0 + pulse * 0.5)

        noStroke()

        // グロー
        for i in stride(from: 4, to: 0, by: -1) {
            let glowSize = size * (1.0 + Float(i) * 0.2)
            let alpha: Float = 0.08
            fill(Color(r: circleColor.r, g: circleColor.g, b: circleColor.b, a: alpha))
            circle(cx, cy, glowSize)
        }

        fill(circleColor)
        circle(cx, cy, size)

        // --- 右側: メッセージログ ---
        let logX = width - 400
        fill(Color(gray: 0.0, alpha: 0.5))
        rect(logX - 10, 15, 395, 25 + Float(messageLog.count) * 20)

        fill(Color(gray: 0.6))
        textSize(14)
        textAlign(.left, .top)
        text("OSC Messages (port 9000):", logX, 20)

        for (i, entry) in messageLog.enumerated() {
            let age = time - entry.time
            let alpha = max(0.3, 1.0 - age * 0.2)
            fill(Color(r: 0.5, g: 1.0, b: 0.7, a: alpha))
            text(entry.msg, logX, 45 + Float(i) * 20)
        }

        // --- 左上: 状態表示 ---
        fill(Color(gray: 0.7))
        textSize(13)
        textAlign(.left, .top)
        text("Listening on UDP :9000", 20, 20)
        text("Color: (\(String(format: "%.1f", circleColor.r)), \(String(format: "%.1f", circleColor.g)), \(String(format: "%.1f", circleColor.b)))", 20, 40)
        text("Size:  \(String(format: "%.0f", circleSize))", 20, 60)
        text("Pos:   (\(String(format: "%.2f", posX)), \(String(format: "%.2f", posY)))", 20, 80)

        // --- 操作ガイド ---
        fill(Color(gray: 0.35))
        textSize(11)
        textAlign(.left, .bottom)
        text("Send OSC to localhost:9000  |  /color fff  |  /size f  |  /pos ff  |  /note i", 20, height - 20)
    }
}
