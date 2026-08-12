import metaphor

@main
final class Camera: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Camera")
    }

    // 接続中のカメラ一覧。R キーで取り直す
    var devices: [CaptureDeviceInfo] = []
    var capture: CaptureDevice?

    func setup() {
        devices = listCaptureDevices()
        // 引数なしの createCapture() は OS の既定のカメラを開く。
        // createAudioInput() と違い、start() は要らない（作った時点で始まる）
        capture = createCapture(width: 1280, height: 720)
    }

    func draw() {
        background(12)

        if let capture, capture.isAvailable {
            // 実際に開けた解像度は要求と違うことがある。歪めずに収める
            let cameraWidth = Float(capture.actualWidth ?? capture.width)
            let cameraHeight = Float(capture.actualHeight ?? capture.height)
            let scale = min(width / cameraWidth, height / cameraHeight)
            let w = cameraWidth * scale
            let h = cameraHeight * scale
            // 画像と同じ image()。CaptureDevice をそのまま渡せる
            image(capture, (width - w) / 2, (height - h) / 2, w, h)
        } else {
            noStroke()
            fill(Color(gray: 0.6))
            textSize(16)
            textAlign(.center, .center)
            let reason = capture == nil ? "カメラが見つかりません" : "カメラの映像を待っています"
            text(reason, width / 2, height / 2)
        }

        drawDeviceList()
    }

    func keyPressed() {
        guard let key else { return }
        if key == "r" {
            // 接続・切断はスケッチの実行中に起きる。一覧は撮り直せるようにしておく
            devices = listCaptureDevices()
            return
        }
        // 1〜9 で切り替える。開き直す前に、いま開いているカメラを止める
        if let digit = key.wholeNumberValue, digit >= 1, digit <= devices.count {
            capture?.stop()
            capture = createCapture(width: 1280, height: 720, device: devices[digit - 1])
        }
    }

    /// 接続中のカメラと、いま映しているものを重ねて出す
    private func drawDeviceList() {
        noStroke()
        textSize(13)
        textAlign(.left, .top)

        fill(Color(gray: 1, alpha: 0.9))
        text("1-\(min(devices.count, 9)): 切り替え   R: 一覧を取り直す", 16, 16)

        var y: Float = 40
        for (index, device) in devices.enumerated() {
            let isCurrent = capture?.deviceInfo?.id == device.id
            fill(isCurrent ? Color(r: 0.3, g: 1, b: 0.6) : Color(gray: 0.75))
            text("\(isCurrent ? ">" : " ") \(index + 1): \(device.name)", 16, y)
            y += 20
        }
        if devices.isEmpty {
            fill(Color(gray: 0.6))
            text("(カメラなし)", 16, y)
        }
    }
}
