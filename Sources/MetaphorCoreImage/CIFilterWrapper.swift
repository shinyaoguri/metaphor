import Metal
import CoreImage
import MetaphorCore

/// A wrapper that applies CoreImage filters directly to Metal textures.
///
/// Shares a CIContext with an MTLCommandQueue to achieve zero-copy Metal <-> CoreImage interoperability.
@MainActor
public final class CIFilterWrapper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace
    private var texturePool: [String: MTLTexture] = [:]
    private var warnedMessages: Set<String> = []
    /// The identifier of the output texture that the most recent in-place
    /// `apply(filterName:parameters:to:)` handed to MImage. Kept so that on the
    /// next call, if the texture being replaced is confirmed to be this wrapper's own previous output, it can be reclaimed (#251).
    private var lastInPlaceOutputID: ObjectIdentifier?

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        // 入出力テクスチャの値は sRGB（ガンマ空間）として解釈し、フィルタ演算は
        // リニア空間で行う。deviceRGB を使うと CI がガンマ空間のまま演算し、
        // ブラー系で暗部が沈む等の色ズレが出るため使わない。extended にするのは
        // 中間値のクランプによる階調落ちを避けるため。
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.ciContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: [
                .workingColorSpace: workingSpace,
                .outputColorSpace: colorSpace,
                .outputPremultiplied: true,
                .cacheIntermediates: false
            ]
        )
    }

    // MARK: - MTLTexture に適用（PostProcess パイプライン用）

    /// Encodes a CIFilter operation from source to destination within a command buffer.
    ///
    /// On an invalid filter name, output generation failure, or similar, this does not
    /// crash — it copies the source straight to the destination and continues drawing (logging a warning once).
    /// Generator-style filters that take no input image are automatically routed to the generation path.
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - source: The source texture.
    ///   - destination: The destination texture.
    ///   - commandBuffer: The command buffer to encode into.
    public func apply(
        filterName: String,
        parameters: [String: Any],
        source: MTLTexture,
        destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let filter = CIFilter(name: filterName) else {
            warnOnce("unknown CIFilter '\(filterName)' — passing source through")
            blitCopy(from: source, to: destination, commandBuffer: commandBuffer)
            return
        }
        filter.setDefaults()

        // 入力画像を取らないフィルタ（ジェネレーター）へ kCIInputImageKey を
        // setValue すると NSException でプロセスごと落ちるため、inputKeys で振り分ける。
        guard filter.inputKeys.contains(kCIInputImageKey) else {
            generate(filterName: filterName, parameters: parameters,
                     destination: destination, commandBuffer: commandBuffer)
            return
        }

        guard let ciInput = CIImage(mtlTexture: source, options: [.colorSpace: colorSpace]) else {
            warnOnce("CIImage(mtlTexture:) failed for '\(filterName)' — passing source through")
            blitCopy(from: source, to: destination, commandBuffer: commandBuffer)
            return
        }

        // CoreImage は Y 軸を反転する
        let flipped = ciInput.transformed(
            by: CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -CGFloat(source.height))
        )
        filter.setValue(flipped, forKey: kCIInputImageKey)
        setParameters(parameters, on: filter, filterName: filterName)

        guard let output = filter.outputImage else {
            warnOnce("CIFilter '\(filterName)' produced no output — passing source through")
            blitCopy(from: source, to: destination, commandBuffer: commandBuffer)
            return
        }
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

    /// Applies a CIFilter to an MImage in place.
    ///
    /// - Important: This API **synchronously waits** for GPU completion (`waitUntilCompleted`).
    ///   Calling it every frame inside `draw()` will directly cause dropped frames. If you
    ///   need to use it within a frame, use the non-blocking
    ///   ``apply(filterName:parameters:source:destination:commandBuffer:)`` to encode
    ///   into an existing command buffer instead.
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - image: The image to apply the filter to.
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
        recycleInPlaceTextures(replacedSource: src, newOutput: outTex, poolKey: "\(w)_\(h)_ci_output")
    }

    /// Reclaims textures after in-place application (ping-pong, #251).
    ///
    /// Removes the output handed to MImage from the pool, and if the texture
    /// being replaced was this wrapper's previous output, returns it to the pool as the next output target.
    /// This keeps every frame's in-place application to a swap of two textures,
    /// avoiding a fresh full-size private texture allocation on every call. Textures
    /// from elsewhere (e.g. loadImage) may be shared with a different MImage or caller,
    /// so they are not taken in (the identity check against the previous output also guarantees a matching descriptor).
    private func recycleInPlaceTextures(
        replacedSource: MTLTexture, newOutput: MTLTexture, poolKey: String
    ) {
        if let last = lastInPlaceOutputID, ObjectIdentifier(replacedSource) == last {
            texturePool[poolKey] = replacedSource
        } else {
            texturePool.removeValue(forKey: poolKey)
        }
        // サイズ変更時に旧サイズの ping-pong 相手が残留しないよう掃除
        for staleKey in texturePool.keys where staleKey.hasSuffix("_ci_output") && staleKey != poolKey {
            texturePool.removeValue(forKey: staleKey)
        }
        lastInPlaceOutputID = ObjectIdentifier(newOutput)
    }

    // MARK: - ジェネレーター（入力画像不要）

    /// Generates an MTLTexture using a generator filter (no input image required).
    ///
    /// - Important: This API **synchronously waits** for GPU completion (`waitUntilCompleted`).
    ///   Calling it every frame inside `draw()` will directly cause dropped frames. If you
    ///   need to use it within a frame, use the non-blocking
    ///   ``generate(filterName:parameters:destination:commandBuffer:)`` to encode
    ///   into an existing command buffer instead.
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - width: The output texture width.
    ///   - height: The output texture height.
    /// - Returns: The generated texture, or nil on failure.
    public func generate(
        filterName: String,
        parameters: [String: Any],
        width: Int,
        height: Int
    ) -> MTLTexture? {
        guard let outTex = getOrCreateTexture(width: width, height: height, tag: "ci_gen"),
              let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

        generate(
            filterName: filterName,
            parameters: parameters,
            destination: outTex,
            commandBuffer: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        texturePool.removeValue(forKey: "\(width)_\(height)_ci_gen")
        return outTex
    }

    /// Encodes a generator filter into an existing command buffer.
    ///
    /// On an invalid filter name or output generation failure, this does not crash —
    /// it simply encodes nothing (logging a warning once).
    /// - Parameters:
    ///   - filterName: The CIFilter name string.
    ///   - parameters: The filter parameter dictionary.
    ///   - destination: The destination texture.
    ///   - commandBuffer: The command buffer to encode into.
    public func generate(
        filterName: String,
        parameters: [String: Any],
        destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let filter = CIFilter(name: filterName) else {
            warnOnce("unknown CIFilter '\(filterName)' — generate skipped")
            return
        }
        filter.setDefaults()
        setParameters(parameters, on: filter, filterName: filterName)
        guard let output = filter.outputImage else {
            warnOnce("CIFilter '\(filterName)' produced no output — generate skipped")
            return
        }

        let extent = CGRect(x: 0, y: 0, width: destination.width, height: destination.height)
        let cropped = output.cropped(to: extent)

        ciContext.render(cropped, to: destination, commandBuffer: commandBuffer,
                         bounds: extent, colorSpace: colorSpace)
    }

    // MARK: - テクスチャ管理

    /// Invalidates and releases all cached textures.
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

    // MARK: - 内部ヘルパー

    /// Sets parameters via KVC. Keys the filter does not have do not cause a crash —
    /// they are logged and ignored (this prevents an NSException from a typo in a key name).
    private func setParameters(_ parameters: [String: Any], on filter: CIFilter, filterName: String) {
        let inputKeys = filter.inputKeys
        for (key, value) in parameters {
            guard inputKeys.contains(key) else {
                warnOnce("CIFilter '\(filterName)' has no input key '\(key)' — ignored "
                    + "(available: \(inputKeys.joined(separator: ", ")))")
                continue
            }
            filter.setValue(value, forKey: key)
        }
    }

    /// Fallback for when filter application fails: copies the source straight through,
    /// preventing the previous frame's content or garbage from flowing to the next stage of the post-process chain.
    private func blitCopy(from source: MTLTexture, to destination: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard source !== destination else { return }
        guard source.pixelFormat == destination.pixelFormat,
              source.sampleCount == destination.sampleCount else {
            warnOnce("passthrough blit skipped: pixel format mismatch "
                + "(\(source.pixelFormat.rawValue) → \(destination.pixelFormat.rawValue))")
            return
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let w = min(source.width, destination.width)
        let h = min(source.height, destination.height)
        blit.copy(
            from: source, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
    }

    /// Logs a warning for the same message only once per process
    /// (post-processing runs every frame, so this prevents a log flood).
    private func warnOnce(_ message: String) {
        guard warnedMessages.insert(message).inserted else { return }
        print("[metaphor.CoreImage] Warning: \(message)")
    }
}
