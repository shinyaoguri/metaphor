import AVFoundation
import CoreVideo
import Metal

/// カメラ位置
public enum CameraPosition {
    case front
    case back
}

/// カメラ入力デバイス
///
/// AVCaptureSession + CVMetalTextureCache を使用して、
/// カメラフレームを MTLTexture としてゼロコピーで取得する。
///
/// ```swift
/// let cam = createCapture()
/// // draw() 内で:
/// image(cam, 0, 0, width, height)
/// ```
@MainActor
public final class CaptureDevice: NSObject {

    // MARK: - Public Properties

    /// 最新フレームのテクスチャ（read() 後に有効）
    public private(set) var texture: MTLTexture?

    /// カメラが使用可能かどうか
    public private(set) var isAvailable: Bool = false

    /// リクエストされた幅
    public let width: Int

    /// リクエストされた高さ
    public let height: Int

    // MARK: - Private Properties

    private let device: MTLDevice
    private var captureSession: AVCaptureSession?
    private var textureCache: CVMetalTextureCache?
    private let delegateHelper: CaptureDelegate
    private var isRunning: Bool = false

    // MARK: - Initialization

    /// カメラ入力デバイスを初期化
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - width: 映像幅（デフォルト 1280）
    ///   - height: 映像高さ（デフォルト 720）
    ///   - position: カメラ位置（デフォルト .front）
    init(device: MTLDevice, width: Int = 1280, height: Int = 720, position: CameraPosition = .front) {
        self.device = device
        self.width = width
        self.height = height
        self.delegateHelper = CaptureDelegate()
        super.init()

        setupTextureCache()
        setupCaptureSession(position: position)
    }

    // MARK: - Public Methods

    /// キャプチャを開始
    public func start() {
        guard !isRunning, let session = captureSession else { return }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// キャプチャを停止
    public func stop() {
        guard isRunning, let session = captureSession else { return }
        isRunning = false
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// 最新フレームをテクスチャに反映
    public func read() {
        guard let pixelBuffer = delegateHelper.latestPixelBuffer else { return }

        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        guard let cache = textureCache else { return }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, bufferWidth, bufferHeight, 0, &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else { return }
        texture = CVMetalTextureGetTexture(cvTex)
    }

    /// 最新フレームを MImage として取得
    public func toImage() -> MImage? {
        guard let tex = texture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Private Setup

    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    private func setupCaptureSession(position: CameraPosition) {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: avPosition
        ) ?? AVCaptureDevice.default(for: .video) else {
            isAvailable = false
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            isAvailable = false
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(delegateHelper, queue: delegateHelper.queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        self.captureSession = session
        self.isAvailable = true
    }
}

// MARK: - Capture Delegate (Thread-safe)

/// AVCaptureVideoDataOutputSampleBufferDelegate（非 @MainActor、バックグラウンドスレッドで動作）
private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "metaphor.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?

    var latestPixelBuffer: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPixelBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        _latestPixelBuffer = pixelBuffer
        lock.unlock()
    }
}
