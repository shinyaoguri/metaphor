@preconcurrency import AVFoundation
import CoreVideo
import Metal
import os

/// キャプチャに使用するカメラ位置の指定
public enum CameraPosition {
    /// 前面カメラ
    case front
    /// 背面カメラ
    case back
}

/// カメラからのライブビデオフレームをキャプチャし、Metal テクスチャとして提供します。
///
/// ``CaptureDevice`` は `AVCaptureSession` と `CVMetalTextureCache` を使用して、
/// カメラフレームをゼロコピーの GPU アクセスが可能な `MTLTexture` インスタンスとして
/// 配信します。毎フレーム ``read()`` を呼び出すことで、最新のカメラフレームで
/// テクスチャが更新されます。
///
/// ```swift
/// let cam = createCapture()
/// // In draw():
/// cam.read()
/// image(cam, 0, 0, width, height)
/// ```
@MainActor
public final class CaptureDevice {

    // MARK: - Public Properties

    /// ``read()`` 呼び出し後に利用可能な、最新のカメラフレームの Metal テクスチャ
    public private(set) var texture: MTLTexture?

    /// カメラが利用可能でキャプチャセッションの設定が成功したかどうかを示すフラグ
    public private(set) var isAvailable: Bool = false

    /// 要求されたキャプチャ幅（ピクセル）
    public let width: Int

    /// 要求されたキャプチャ高さ（ピクセル）
    public let height: Int

    // MARK: - Private Properties

    /// テクスチャキャッシュ作成に使用する Metal デバイス
    private let device: MTLDevice

    /// AVFoundation キャプチャセッション
    private var captureSession: AVCaptureSession?

    /// ゼロコピーピクセルバッファ変換用の Metal テクスチャキャッシュ
    private var textureCache: CVMetalTextureCache?

    /// バックグラウンドスレッドでサンプルバッファを受信するデリゲートヘルパー
    private let delegateHelper: CaptureDelegate

    /// キャプチャセッションが現在実行中かどうか
    private var isRunning: Bool = false

    // MARK: - Initialization

    /// 新しいカメラキャプチャデバイスを作成します。
    ///
    /// - Parameters:
    ///   - device: テクスチャキャッシュ作成用の Metal デバイス。
    ///   - width: 要求するビデオ幅（ピクセル、デフォルト: 1280）。
    ///   - height: 要求するビデオ高さ（ピクセル、デフォルト: 720）。
    ///   - position: 使用するカメラ位置（デフォルト: `.front`）。
    init(device: MTLDevice, width: Int = 1280, height: Int = 720, position: CameraPosition = .front) {
        self.device = device
        self.width = width
        self.height = height
        self.delegateHelper = CaptureDelegate()

        setupTextureCache()
        setupCaptureSession(position: position)
    }

    // MARK: - Public Methods

    /// カメラキャプチャセッションを開始します。
    ///
    /// セッションはバックグラウンドスレッドで非同期に開始されます。
    public func start() {
        guard !isRunning, let session = captureSession else { return }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// カメラキャプチャセッションを停止します。
    ///
    /// セッションはバックグラウンドスレッドで非同期に停止されます。
    public func stop() {
        guard isRunning, let session = captureSession else { return }
        isRunning = false
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// ``texture`` プロパティを最新のカメラフレームで更新します。
    ///
    /// レンダリングでテクスチャを使用する前に、毎フレーム一度呼び出してください。
    /// テクスチャはゼロコピー GPU アクセスのため、最新のピクセルバッファから
    /// `CVMetalTextureCache` 経由で作成されます。
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

    /// 最新のカメラフレームを ``MImage`` インスタンスに変換します。
    ///
    /// - Returns: 現在のテクスチャをラップした ``MImage``。フレームが利用できない場合は `nil`。
    public func toImage() -> MImage? {
        guard let tex = texture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Private Setup

    /// ゼロコピーテクスチャ変換用の CVMetalTextureCache を作成
    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    /// 要求されたカメラと出力設定で AVCaptureSession を構成
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

/// バックグラウンドスレッドでビデオサンプルバッファを受信し、最新のピクセルバッファを保持します。
///
/// このクラスはキャプチャセッションのバックグラウンドディスパッチキュー上で
/// 動作するため、意図的に `@MainActor` を付けていません。スレッドセーフティは
/// `NSLock` で保証されています（CVPixelBuffer は Sendable ではないため、
/// OSAllocatedUnfairLock は使用できません）。
private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// サンプルバッファ受信用のディスパッチキュー
    let queue = DispatchQueue(label: "metaphor.capture", qos: .userInteractive)

    /// 最新ピクセルバッファへのアクセスを保護するロック
    private let lock = NSLock()

    /// 最新ピクセルバッファのバッキングストレージ
    private var _latestPixelBuffer: CVPixelBuffer?

    /// スレッドセーフにアクセスされる最新のキャプチャ済みピクセルバッファ
    var latestPixelBuffer: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPixelBuffer
    }

    /// 受信したサンプルバッファからピクセルバッファを保存
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
