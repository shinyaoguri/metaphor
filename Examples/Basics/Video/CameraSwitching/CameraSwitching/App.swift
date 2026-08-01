import metaphor

/// Lists connected cameras and demonstrates switching between them using number keys.
///
/// Shows how to use explicit device selection via `listCaptureDevices()` / `createCapture(device:)`,
/// check actual resolution negotiated (`actualWidth` / `actualHeight`) against requested values,
/// and detect disconnection via `onDisconnect` callback.
///
/// Controls:
/// - 1–9 keys: Switch to the corresponding camera
/// - R key: Rescan camera list (use after connecting/disconnecting devices)
///
/// On first run, macOS asks for camera permission — see `docs/permissions.md`
/// at the repository root for how that dialog works with a `swift run`
/// binary and how to recover if you denied it.
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
        // createCapture() with no arguments opens the OS's user/system preferred camera
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

    /// Stops the current capture and switches to a new one
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

    /// Draws camera video maintaining aspect ratio centered on canvas
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

    /// Displays device list and current status as an overlay
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
