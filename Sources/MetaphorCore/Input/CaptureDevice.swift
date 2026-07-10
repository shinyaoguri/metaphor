@preconcurrency import AVFoundation
import CoreVideo
import Metal
import ObjectiveC.runtime
import os

/// キャプチャに使用するカメラ位置の指定
///
/// - Note: macOS では内蔵・外付けを問わずほとんどのカメラが位置情報を持たない
///   （`.unspecified` を返す）ため、位置によるマッチングは通常失敗し、
///   システムデフォルトのカメラへフォールバックします。特定のカメラを
///   確実に選択するには ``CaptureDevice/list()`` と
///   `createCapture(width:height:device:)` を使用してください。
public enum CameraPosition {
    /// 前面カメラ
    case front
    /// 背面カメラ
    case back
}

/// 接続中のカメラの種類
public enum CaptureDeviceKind: String, Sendable, Codable {
    /// Mac 内蔵カメラ
    case builtIn
    /// 外付けカメラ（USB 接続の Web カメラ・キャプチャデバイスなど）
    case external
    /// Continuity Camera（連係カメラとしての iPhone / iPad）
    case continuityCamera
    /// デスクビューカメラ
    case deskView
    /// 上記以外
    case unknown
}

/// 接続中のカメラ 1 台を表す情報。
///
/// ``CaptureDevice/list()`` で取得し、`createCapture(width:height:device:)` へ
/// 渡すことで、複数カメラ環境で使用するカメラを明示的に選択できます。
///
/// ```swift
/// for cam in listCaptureDevices() {
///     print(cam.name, cam.kind)
/// }
/// let capture = createCapture(device: listCaptureDevices()[1])
/// ```
public struct CaptureDeviceInfo: Sendable, Identifiable, Hashable {
    /// デバイスの一意な識別子（`AVCaptureDevice.uniqueID`）
    public let id: String
    /// ユーザーに表示できるデバイス名（例: "FaceTime HD カメラ"）
    public let name: String
    /// デバイスの種類
    public let kind: CaptureDeviceKind
}

extension CaptureDeviceInfo {
    /// AVCaptureDevice から情報を抽出
    fileprivate init(avDevice: AVCaptureDevice) {
        self.id = avDevice.uniqueID
        self.name = avDevice.localizedName
        switch avDevice.deviceType {
        case .builtInWideAngleCamera: self.kind = .builtIn
        case .external: self.kind = .external
        case .continuityCamera: self.kind = .continuityCamera
        case .deskViewCamera: self.kind = .deskView
        default: self.kind = .unknown
        }
    }
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

    /// 実際に使用しているカメラの情報（セッション設定に成功した場合のみ非 nil）
    public private(set) var deviceInfo: CaptureDeviceInfo?

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

    /// ``texture`` を支える CVMetalTexture ラッパーの寿命を MTLTexture 自体に
    /// 関連付けるためのキー（MLTextureConverter と同じパターン）。
    private static let cvTextureAssociationKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )

    /// バックグラウンドスレッドでサンプルバッファを受信するデリゲートヘルパー
    private let delegateHelper: CaptureDelegate

    /// キャプチャセッションが現在実行中かどうか
    private var isRunning: Bool = false

    /// `startRunning`/`stopRunning` を直列化するための専用キュー。
    ///
    /// concurrent なグローバルキューに投入すると、素早い start→stop で
    /// stop が先に完了し、その後 start が走ってセッションが止まらない競合が
    /// 起こり得る。専用シリアルキューで投入順＝実行順を保証する。
    private let sessionQueue = DispatchQueue(label: "metaphor.capture.session", qos: .userInitiated)

    // MARK: - Initialization

    /// 新しいカメラキャプチャデバイスを作成します。
    ///
    /// - Parameters:
    ///   - device: テクスチャキャッシュ作成用の Metal デバイス。
    ///   - width: 要求するビデオ幅（ピクセル、デフォルト: 1280）。
    ///   - height: 要求するビデオ高さ（ピクセル、デフォルト: 720）。
    ///   - position: 使用するカメラ位置。`nil`（デフォルト）の場合は
    ///     ユーザー/システムの優先カメラを使用します。
    convenience init(
        device: MTLDevice, width: Int = 1280, height: Int = 720, position: CameraPosition? = nil
    ) {
        self.init(device: device, width: width, height: height,
                  camera: Self.resolveCamera(position: position))
    }

    /// 列挙したデバイス情報を指定してカメラキャプチャデバイスを作成します。
    ///
    /// - Parameters:
    ///   - device: テクスチャキャッシュ作成用の Metal デバイス。
    ///   - width: 要求するビデオ幅（ピクセル、デフォルト: 1280）。
    ///   - height: 要求するビデオ高さ（ピクセル、デフォルト: 720）。
    ///   - captureDevice: ``CaptureDevice/list()`` で取得したデバイス情報。
    ///     既に切断されている場合、``isAvailable`` は `false` になります。
    convenience init(
        device: MTLDevice, width: Int = 1280, height: Int = 720, captureDevice info: CaptureDeviceInfo
    ) {
        self.init(device: device, width: width, height: height,
                  camera: AVCaptureDevice(uniqueID: info.id))
    }

    /// デバイス名を指定してカメラキャプチャデバイスを作成します。
    ///
    /// 大文字小文字を無視した完全一致を優先し、なければ部分一致で選択します。
    ///
    /// - Parameters:
    ///   - device: テクスチャキャッシュ作成用の Metal デバイス。
    ///   - width: 要求するビデオ幅（ピクセル、デフォルト: 1280）。
    ///   - height: 要求するビデオ高さ（ピクセル、デフォルト: 720）。
    ///   - deviceName: 選択するカメラの名前（例: `"FaceTime"`）。
    ///     一致するカメラがない場合、``isAvailable`` は `false` になります。
    convenience init(
        device: MTLDevice, width: Int = 1280, height: Int = 720, deviceName: String
    ) {
        let info = Self.match(deviceName: deviceName, in: Self.list())
        self.init(device: device, width: width, height: height,
                  camera: info.flatMap { AVCaptureDevice(uniqueID: $0.id) })
    }

    /// 解決済みの AVCaptureDevice からセットアップする指定イニシャライザ
    private init(device: MTLDevice, width: Int, height: Int, camera: AVCaptureDevice?) {
        self.device = device
        self.width = width
        self.height = height
        self.delegateHelper = CaptureDelegate()

        setupTextureCache()
        if let camera {
            setupCaptureSession(camera: camera)
        } else {
            isAvailable = false
        }
    }

    deinit {
        // stop() を呼ばずに破棄されてもキャプチャセッションを止める
        // （動いたまま dealloc されるとカメラが掴まれ続ける）
        if let session = captureSession {
            sessionQueue.async {
                if session.isRunning { session.stopRunning() }
            }
        }
    }

    // MARK: - Public Methods

    /// カメラキャプチャセッションを開始します。
    ///
    /// セッションはバックグラウンドスレッドで非同期に開始されます。
    public func start() {
        guard !isRunning, let session = captureSession else { return }
        isRunning = true
        sessionQueue.async {
            session.startRunning()
        }
    }

    /// カメラキャプチャセッションを停止します。
    ///
    /// セッションはバックグラウンドスレッドで非同期に停止されます。
    public func stop() {
        guard isRunning, let session = captureSession else { return }
        isRunning = false
        sessionQueue.async {
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

        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let mtlTexture = CVMetalTextureGetTexture(cvTex) else { return }
        // CoreVideo の契約上、MTLTexture はラッパー（cvTex）が生存している間のみ
        // 有効。トリプルバッファリングでは前々フレームのコマンドがまだ GPU 実行中
        // であり得るため、「次の read() まで 1 世代保持」では足りない。ラッパーを
        // テクスチャ自体に関連付け、テクスチャと同じ寿命で生かし続ける
        // （MLTextureConverter と同じパターン）。
        objc_setAssociatedObject(
            mtlTexture, Self.cvTextureAssociationKey, cvTex, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        texture = mtlTexture
    }

    /// 最新のカメラフレームを ``MImage`` インスタンスに変換します。
    ///
    /// - Returns: 現在のテクスチャをラップした ``MImage``。フレームが利用できない場合は `nil`。
    public func toImage() -> MImage? {
        guard let tex = texture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Device Enumeration

    /// 接続中のカメラを列挙します。
    ///
    /// 内蔵カメラ・外付け（USB）カメラ・Continuity Camera・デスクビューカメラが
    /// 対象です。取得した ``CaptureDeviceInfo`` を `createCapture(width:height:device:)`
    /// へ渡すことで、使用するカメラを明示的に選択できます。
    ///
    /// - Note: Continuity Camera をアプリで使用するには、Info.plist に
    ///   `NSCameraUseContinuityCameraDeviceType` キーが必要です。
    ///
    /// - Returns: 接続中のカメラの一覧（接続がなければ空配列）。
    public static func list() -> [CaptureDeviceInfo] {
        discoverySession().devices.map(CaptureDeviceInfo.init(avDevice:))
    }

    /// 対応する全デバイスタイプを対象にした DiscoverySession を作成
    private static func discoverySession() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
    }

    /// 位置指定（または未指定）から使用する AVCaptureDevice を解決します。
    ///
    /// 未指定の場合は、ユーザーが OS レベルで選択したカメラ
    /// （`userPreferredCamera`、なければ `systemPreferredCamera`）を尊重します。
    private static func resolveCamera(position: CameraPosition?) -> AVCaptureDevice? {
        if let position {
            let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
            if let matched = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: avPosition
            ) {
                return matched
            }
        }
        return AVCaptureDevice.userPreferredCamera
            ?? AVCaptureDevice.systemPreferredCamera
            ?? AVCaptureDevice.default(for: .video)
    }

    /// 名前でデバイス情報を選択します。
    ///
    /// 大文字小文字を無視した完全一致を優先し、なければ部分一致（前方から
    /// 最初に見つかったもの）を返します。
    nonisolated static func match(
        deviceName: String, in devices: [CaptureDeviceInfo]
    ) -> CaptureDeviceInfo? {
        let query = deviceName.lowercased()
        guard !query.isEmpty else { return nil }
        if let exact = devices.first(where: { $0.name.lowercased() == query }) {
            return exact
        }
        return devices.first { $0.name.lowercased().contains(query) }
    }

    // MARK: - Private Setup

    /// ゼロコピーテクスチャ変換用の CVMetalTextureCache を作成
    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    /// 指定されたカメラと出力設定で AVCaptureSession を構成
    private func setupCaptureSession(camera: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.sessionPreset = .high

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
        self.deviceInfo = CaptureDeviceInfo(avDevice: camera)
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
