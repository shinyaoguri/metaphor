import CoreML
import Metal

/// スタイル転送 / 画像変換モデルラッパー
///
/// image-to-image 型の CoreML モデルを簡単に使用するための
/// 特化クラス。MLProcessor の薄いラッパー。
///
/// ```swift
/// var style: MLStyleTransfer!
/// func setup() {
///     style = try! loadStyleTransfer("starry_night.mlmodelc")
/// }
/// func draw() {
///     style.update()
///     cam.read()
///     if let tex = cam.texture { style.apply(tex) }
///     if let result = style.outputTexture {
///         image(result, 0, 0, width, height)
///     }
/// }
/// ```
@MainActor
public final class MLStyleTransfer {

    // MARK: - Public Properties

    /// 出力テクスチャ（apply() + update() 後に有効）
    public private(set) var outputTexture: MImage?

    /// 推論実行中かどうか
    public private(set) var isProcessing: Bool = false

    /// 最後の推論にかかった時間（秒）
    public private(set) var inferenceTime: Double = 0

    /// モデルが読み込み済みかどうか
    public var isLoaded: Bool { model.isLoaded }

    // MARK: - Private

    private let model: MLProcessor

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.model = MLProcessor(device: device, commandQueue: commandQueue)
    }

    // MARK: - Loading

    /// モデルを読み込む
    public func load(_ path: String, computeUnit: MLComputeUnit = .all) throws {
        model.computeUnit = computeUnit
        try model.load(path)
    }

    /// バンドルリソースから読み込む
    public func load(named name: String, computeUnit: MLComputeUnit = .all) throws {
        model.computeUnit = computeUnit
        try model.load(named: name)
    }

    // MARK: - Apply

    /// テクスチャにスタイル転送を適用（非同期推論）
    public func apply(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        isProcessing = true
        model.predict(texture: texture)
    }

    /// MImage にスタイル転送を適用
    public func apply(_ image: MImage) {
        apply(image.texture)
    }

    // MARK: - Update

    /// 毎フレーム呼ぶ更新メソッド
    public func update() {
        model.update()
        if model.outputTexture != nil {
            outputTexture = model.outputTexture
            inferenceTime = model.inferenceTime
            isProcessing = false
        }
    }
}
