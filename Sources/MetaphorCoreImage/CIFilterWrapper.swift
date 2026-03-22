@preconcurrency import Metal
import CoreImage
import MetaphorCore

/// CoreImage フィルタを Metal テクスチャに直接適用するラッパー。
///
/// CIContext を MTLCommandQueue と共有し、ゼロコピーの Metal ⇔ CoreImage 相互運用を実現します。
@MainActor
public final class CIFilterWrapper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace
    private var texturePool: [String: MTLTexture] = [:]

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        self.colorSpace = CGColorSpaceCreateDeviceRGB()
        self.ciContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .outputPremultiplied: true,
                .cacheIntermediates: false
            ]
        )
    }

    // MARK: - MTLTexture に適用（PostProcess パイプライン用）

    /// CIFilter 操作をコマンドバッファ内でソースからデスティネーションにエンコードします。
    /// - Parameters:
    ///   - filterName: CIFilter 名文字列。
    ///   - parameters: フィルタパラメータ辞書。
    ///   - source: ソーステクスチャ。
    ///   - destination: デスティネーションテクスチャ。
    ///   - commandBuffer: エンコード先のコマンドバッファ。
    public func apply(
        filterName: String,
        parameters: [String: Any],
        source: MTLTexture,
        destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let ciInput = CIImage(mtlTexture: source, options: [.colorSpace: colorSpace]) else { return }

        // CoreImage は Y 軸を反転する
        let flipped = ciInput.transformed(
            by: CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -CGFloat(source.height))
        )

        guard let filter = CIFilter(name: filterName) else { return }
        filter.setDefaults()
        filter.setValue(flipped, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }

        guard let output = filter.outputImage else { return }
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let cropped = output.cropped(to: extent)

        ciContext.render(
            cropped, to: destination,
            commandBuffer: commandBuffer,
            bounds: extent,
            colorSpace: colorSpace
        )
    }

    // MARK: - MImage に適用（スタンドアロン使用）

    /// CIFilter を MImage にインプレースで適用します。
    /// - Parameters:
    ///   - filterName: CIFilter 名文字列。
    ///   - parameters: フィルタパラメータ辞書。
    ///   - image: フィルタを適用する画像。
    public func apply(
        filterName: String,
        parameters: [String: Any],
        to image: MImage
    ) {
        let src = image.texture
        let w = src.width, h = src.height

        guard let outTex = getOrCreateTexture(width: w, height: h, tag: "ci_output"),
              let cmdBuf = commandQueue.makeCommandBuffer() else { return }

        apply(filterName: filterName, parameters: parameters,
              source: src, destination: outTex, commandBuffer: cmdBuf)

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        image.replaceTexture(outTex)
        texturePool.removeValue(forKey: "\(w)_\(h)_ci_output")
    }

    // MARK: - ジェネレーター（入力画像不要）

    /// ジェネレーターフィルタ（入力画像不要）を使用して MTLTexture を生成します。
    /// - Parameters:
    ///   - filterName: CIFilter 名文字列。
    ///   - parameters: フィルタパラメータ辞書。
    ///   - width: 出力テクスチャの幅。
    ///   - height: 出力テクスチャの高さ。
    /// - Returns: 生成されたテクスチャ。失敗時は nil。
    public func generate(
        filterName: String,
        parameters: [String: Any],
        width: Int,
        height: Int
    ) -> MTLTexture? {
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setDefaults()
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        guard let output = filter.outputImage else { return nil }

        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let cropped = output.cropped(to: extent)

        guard let outTex = getOrCreateTexture(width: width, height: height, tag: "ci_gen"),
              let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

        ciContext.render(cropped, to: outTex, commandBuffer: cmdBuf,
                         bounds: extent, colorSpace: colorSpace)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        texturePool.removeValue(forKey: "\(width)_\(height)_ci_gen")
        return outTex
    }

    // MARK: - テクスチャ管理

    /// キャッシュ済みテクスチャをすべて無効化・解放します。
    public func invalidateTextures() {
        texturePool.removeAll()
    }

    private func getOrCreateTexture(width: Int, height: Int, tag: String) -> MTLTexture? {
        let key = "\(width)_\(height)_\(tag)"
        if let cached = texturePool[key] { return cached }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        texturePool[key] = tex
        return tex
    }
}
