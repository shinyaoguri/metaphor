@preconcurrency import Metal
import CoreImage

/// Wrap CoreImage filters for direct application to Metal textures.
///
/// Share a CIContext with the MTLCommandQueue for zero-copy Metal to CoreImage interop.
@MainActor
public final class CIFilterWrapper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace
    private var texturePool: [String: MTLTexture] = [:]

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
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

    // MARK: - Apply to MTLTexture (PostProcess Pipeline Use)

    /// Encode a CIFilter operation from source to destination within a command buffer.
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - commandBuffer: The command buffer to encode into.
    func apply(
        filterName: String,
        parameters: [String: Any],
        source: MTLTexture,
        destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let ciInput = CIImage(mtlTexture: source, options: [.colorSpace: colorSpace]) else { return }

        // CoreImage flips the Y axis
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

    // MARK: - Apply to MImage (Standalone Use)

    /// Apply a CIFilter to an MImage in place.
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - image: The image to apply the filter to.
    func apply(
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

    // MARK: - Generator (no input image)

    /// Generate an MTLTexture using a generator filter (no input image required).
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - width: The output texture width.
    ///   - height: The output texture height.
    /// - Returns: The generated texture, or nil on failure.
    func generate(
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

    // MARK: - Texture Management

    /// Invalidate and release all cached textures.
    func invalidateTextures() {
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
