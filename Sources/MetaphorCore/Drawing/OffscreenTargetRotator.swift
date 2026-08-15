import Metal

/// オフスクリーンバッファ（``Graphics`` / ``Graphics3D``）の描画先テクスチャを
/// copy-on-write でローテーションします（#745）。
///
/// `toImage()` / `texture` で外へ渡したテクスチャは「その時点の絵」として凍結し、
/// 次の `beginDraw()` では別のテクスチャへ描きます。
///
/// これが無いと、同一フレーム内でバッファを描き換えて複数回 `image()` したときに
/// **すべての貼り付けが最後の内容**になります。メインキャンバスの 2D バッチは
/// `image()` を呼んだ時点のテクスチャ参照を持つだけで、実際の描画はフレーム末に
/// まとめて実行されるためです（オフスクリーンのパスは `endDraw()` ごとに commit
/// されるので、同一キューの commit 順序ではメインパスより先に全部完了する）。
///
/// 通常の使い方（毎フレーム `background()` で塗り直す）ではコピーは起きません。
/// 次のパスの `loadAction` が `.clear` だからです。`background()` を呼ばずに前の
/// 内容へ描き足すときだけ、旧テクスチャから新テクスチャへ blit コピーします。
@MainActor
final class OffscreenTargetRotator {

    /// メインレンダラーの in-flight フレーム数（``MetaphorRenderer`` のセマフォと同じ 3）。
    ///
    /// フレーム F の描画が始まる時点で完了していないフレームは高々 F-1・F-2 なので、
    /// F-3 以前のフレームで手放したテクスチャはメインパスに読み終えられている。
    private static let mainInflightFrames: UInt32 = 3

    /// 手放したテクスチャの控えの上限。あふれたぶんは参照を落とす（読み手が
    /// 保持していれば Metal 側で生き続け、読み終わったところで解放される）。
    private static let retiredCapacity = 32

    private let textureManager: TextureManager

    /// 前回のローテーション以降に描画先テクスチャを外へ渡したか。
    private var handedOut = false

    /// 外へ渡した `MImage`。描画は渡した時点のテクスチャで凍結する一方、
    /// ピクセル読み出し（`loadPixels()`）は常に最新を指すよう張り替える（#158 の挙動）。
    private var handedOutImages: [WeakImage] = []

    /// 手放したテクスチャと、手放したフレーム番号。
    private var retired: [(texture: MTLTexture, frame: UInt32)] = []

    /// フレーム番号の供給元。未設定なら再利用せず毎回確保する
    /// （スケッチのフレーム進行が分からず、再利用してよい時期を判定できないため）。
    var frameCountProvider: (() -> UInt32)?

    init(textureManager: TextureManager) {
        self.textureManager = textureManager
    }

    // MARK: - 貸し出し

    /// 描画先テクスチャを外部へ渡したことを記録します。
    ///
    /// - Parameter image: テクスチャをラップして返した `MImage`（生テクスチャを
    ///   渡した場合は `nil`）。ローテーション時に最新のテクスチャへ張り替える。
    func markHandedOut(_ image: MImage? = nil) {
        handedOut = true
        if let image {
            handedOutImages.append(WeakImage(image))
        }
    }

    // MARK: - ローテーション

    /// 貸し出し済みなら描画先を別のテクスチャへ回します（`beginDraw()` の先頭で呼ぶ）。
    ///
    /// - Parameter commandQueue: 内容を引き継ぐ場合の blit に使うキュー。描画と同じ
    ///   キューへ載せることで、commit 順序でコピー → 描画の順になる。
    func rotateIfNeeded(commandQueue: MTLCommandQueue) {
        guard handedOut else { return }
        handedOut = false

        let frame = frameCountProvider?() ?? 0
        let previous = textureManager.colorTexture
        guard let next = acquireTexture(frame: frame) else { return }

        // 前の内容へ描き足すパス（background() を呼ばなかった次のフレーム）は
        // 描き先が変わるぶんを引き継ぐ。クリアするパスではコピーしない。
        if textureManager.renderPassDescriptor.colorAttachments[0].loadAction == .load {
            copy(from: previous, to: next, commandQueue: commandQueue)
        }

        textureManager.replaceColorTexture(next)

        retired.append((previous, frame))
        if retired.count > Self.retiredCapacity {
            retired.removeFirst(retired.count - Self.retiredCapacity)
        }

        for box in handedOutImages { box.image?.replaceTexture(next) }
        handedOutImages.removeAll { $0.image == nil }
    }

    // MARK: - プライベート

    private func acquireTexture(frame: UInt32) -> MTLTexture? {
        if frameCountProvider != nil,
           let index = retired.firstIndex(where: { frame &- $0.frame >= Self.mainInflightFrames }) {
            return retired.remove(at: index).texture
        }
        return try? textureManager.makeMatchingColorTexture()
    }

    private func copy(from source: MTLTexture, to destination: MTLTexture, commandQueue: MTLCommandQueue) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        commandBuffer.commit()
    }

    private final class WeakImage {
        weak var image: MImage?
        init(_ image: MImage) { self.image = image }
    }
}
