import AVFoundation
import CoreVideo
import Metal

/// Specify the camera position to use for capture.
public enum CameraPosition {
    /// The front-facing camera.
    case front
    /// The rear-facing camera.
    case back
}

/// Capture live video frames from a camera and provide them as Metal textures.
///
/// ``CaptureDevice`` uses an `AVCaptureSession` and a `CVMetalTextureCache`
/// to deliver camera frames as `MTLTexture` instances with zero-copy
/// GPU access. Call ``read()`` each frame to update the texture with the
/// latest camera frame.
///
/// ```swift
/// let cam = createCapture()
/// // In draw():
/// cam.read()
/// image(cam, 0, 0, width, height)
/// ```
@MainActor
public final class CaptureDevice: NSObject {

    // MARK: - Public Properties

    /// The latest camera frame as a Metal texture, available after calling ``read()``.
    public private(set) var texture: MTLTexture?

    /// Indicate whether the camera is available and the capture session was configured successfully.
    public private(set) var isAvailable: Bool = false

    /// The requested capture width in pixels.
    public let width: Int

    /// The requested capture height in pixels.
    public let height: Int

    // MARK: - Private Properties

    /// The Metal device used for texture cache creation.
    private let device: MTLDevice

    /// The AVFoundation capture session.
    private var captureSession: AVCaptureSession?

    /// The Metal texture cache for zero-copy pixel buffer conversion.
    private var textureCache: CVMetalTextureCache?

    /// The delegate helper that receives sample buffers on a background thread.
    private let delegateHelper: CaptureDelegate

    /// Whether the capture session is currently running.
    private var isRunning: Bool = false

    // MARK: - Initialization

    /// Create a new camera capture device.
    ///
    /// - Parameters:
    ///   - device: The Metal device for texture cache creation.
    ///   - width: The requested video width in pixels (defaults to 1280).
    ///   - height: The requested video height in pixels (defaults to 720).
    ///   - position: The camera position to use (defaults to `.front`).
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

    /// Start the camera capture session.
    ///
    /// The session starts asynchronously on a background thread.
    public func start() {
        guard !isRunning, let session = captureSession else { return }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// Stop the camera capture session.
    ///
    /// The session stops asynchronously on a background thread.
    public func stop() {
        guard isRunning, let session = captureSession else { return }
        isRunning = false
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// Update the ``texture`` property with the latest camera frame.
    ///
    /// Call this once per frame before using the texture for rendering.
    /// The texture is created from the latest pixel buffer via the
    /// `CVMetalTextureCache` for zero-copy GPU access.
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

    /// Convert the latest camera frame to an ``MImage`` instance.
    ///
    /// - Returns: An ``MImage`` wrapping the current texture, or `nil` if no frame is available.
    public func toImage() -> MImage? {
        guard let tex = texture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Private Setup

    /// Create the CVMetalTextureCache for zero-copy texture conversion.
    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    /// Configure the AVCaptureSession with the requested camera and output settings.
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

/// Receive video sample buffers on a background thread and store the latest pixel buffer.
///
/// This class is intentionally not marked `@MainActor` because it operates
/// on the capture session's background dispatch queue. Thread safety is
/// ensured via an `NSLock`.
private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// The dispatch queue for receiving sample buffers.
    let queue = DispatchQueue(label: "metaphor.capture", qos: .userInteractive)

    /// The lock protecting access to the latest pixel buffer.
    private let lock = NSLock()

    /// The backing storage for the latest pixel buffer.
    private var _latestPixelBuffer: CVPixelBuffer?

    /// The most recently captured pixel buffer, accessed in a thread-safe manner.
    var latestPixelBuffer: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPixelBuffer
    }

    /// Store the pixel buffer from the incoming sample buffer.
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
