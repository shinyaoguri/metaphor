import metaphor

/// 接続中のカメラを列挙し、数字キーで切り替えるサンプル。
///
/// `listCaptureDevices()` / `createCapture(device:)` による明示的なデバイス選択、
/// 要求解像度に対して実際に選ばれた解像度（`actualWidth` / `actualHeight`）、
/// `onDisconnect` による切断検知の使い方を示す。
///
/// 操作方法:
/// - 1〜9 キー: 対応する番号のカメラへ切り替え
/// - R キー: カメラ一覧を再取得（接続・切断後の更新）
@main
final class CameraSwitching: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "Camera Switching")
    }

    var devices: [CaptureDeviceInfo] = []
    var capture: CaptureDevice?
    var statusMessage = ""

    func setup() {
        devices = listCaptureDevices()
        // 引数なしの createCapture() は OS のユーザー/システム優先カメラを開く
        open { createCapture() }
    }

    func draw() {
        background(0)
        drawCamera()
        drawOverlay()
    }

    func keyPressed() {
        guard let key else { return }
        if key == "r" {
            devices = listCaptureDevices()
            statusMessage = ""
            return
        }
        if let digit = key.wholeNumberValue, digit >= 1, digit <= devices.count {
            let info = devices[digit - 1]
            open { createCapture(device: info) }
        }
    }

    /// 現在のキャプチャを止めて新しいキャプチャに切り替える
    private func open(_ make: () -> CaptureDevice) {
        capture?.stop()
        let cam = make()
        let name = cam.deviceInfo?.name ?? "camera"
        cam.onDisconnect = { [weak self] in
            self?.statusMessage = "\(name) disconnected — press R to rescan, 1-9 to switch"
        }
        capture = cam
        statusMessage = ""
    }

    /// カメラ映像をアスペクト比を保って中央に描画
    private func drawCamera() {
        guard let cam = capture, cam.isAvailable else {
            fill(Color(gray: 0.5))
            textAlign(.center, .center)
            textSize(24)
            text(capture == nil ? "No camera found" : "Camera unavailable", width / 2, height / 2)
            return
        }
        let cw = Float(cam.actualWidth ?? cam.width)
        let ch = Float(cam.actualHeight ?? cam.height)
        let scale = min(width / cw, height / ch)
        let w = cw * scale
        let h = ch * scale
        image(cam, (width - w) / 2, (height - h) / 2, w, h)
    }

    /// デバイス一覧と現在の状態をオーバーレイ表示
    private func drawOverlay() {
        noStroke()
        textAlign(.left, .top)
        textSize(16)

        fill(Color(gray: 1, alpha: 0.9))
        text("Cameras (1-\(min(devices.count, 9)): switch, R: rescan)", 20, 20)

        var y: Float = 48
        for (i, device) in devices.enumerated() {
            let isCurrent = capture?.deviceInfo?.id == device.id
            fill(isCurrent ? Color(r: 0.3, g: 1, b: 0.5) : Color(gray: 0.8))
            let marker = isCurrent ? ">" : " "
            text("\(marker) \(i + 1): \(device.name) [\(device.kind.rawValue)]", 20, y)
            y += 24
        }
        if devices.isEmpty {
            fill(Color(gray: 0.6))
            text("(no cameras)", 20, y)
            y += 24
        }

        if let cam = capture {
            fill(Color(gray: 1, alpha: 0.9))
            var resolution = "requested \(cam.width)x\(cam.height)"
            if let aw = cam.actualWidth, let ah = cam.actualHeight {
                resolution += "  /  actual \(aw)x\(ah)"
            }
            text(resolution, 20, y + 8)
        }

        if !statusMessage.isEmpty {
            fill(Color(r: 1, g: 0.5, b: 0.3))
            text(statusMessage, 20, height - 40)
        }
    }
}
