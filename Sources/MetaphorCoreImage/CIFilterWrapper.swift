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
    private var warnedMessages: Set<String> = []
    /// 直近の in-place `apply(filterName:parameters:to:)` が MImage へ渡した
    /// 出力テクスチャの識別子。次回呼び出しで置き換えられた旧テクスチャが
    /// 「この wrapper 自身の前回出力」だと確認して回収するために持つ（#251）。
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

    /// CIFilter 操作をコマンドバッファ内でソースからデスティネーションにエンコードします。
    ///
    /// フィルタ名不正・出力生成失敗などの場合はクラッシュせず、ソースをそのまま
    /// デスティネーションへコピーして描画を継続します（警告ログを 1 回出力）。
    /// 入力画像を取らないジェネレーター系フィルタは自動的に生成経路へ振り分けます。
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

    /// CIFilter を MImage にインプレースで適用します。
    ///
    /// - Important: この API は GPU 完了を **同期的に待ちます**（`waitUntilCompleted`）。
    ///   `draw()` 内で毎フレーム呼ぶとフレーム落ちの直接原因になります。フレーム内で
    ///   使う場合は非ブロッキングの
    ///   ``apply(filterName:parameters:source:destination:commandBuffer:)`` を使って
    ///   既存のコマンドバッファへエンコードしてください。
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
        recycleInPlaceTextures(replacedSource: src, newOutput: outTex, poolKey: "\(w)_\(h)_ci_output")
    }

    /// in-place 適用後のテクスチャ回収（ping-pong、#251）。
    ///
    /// MImage へ渡した出力はプールから外し、置き換えられた旧テクスチャが
    /// 「前回この wrapper が出力したもの」であれば次回の出力先としてプールへ戻す。
    /// これで毎フレームの in-place 適用が 2 枚のスワップに収まり、呼び出しごとの
    /// フルサイズ private テクスチャ新規確保を避ける。他所から来たテクスチャ
    /// （loadImage 等）は別 MImage・呼び出し側と共有されている可能性があるため
    /// 取り込まない（前回出力との同一性チェックが descriptor 一致の保証も兼ねる）。
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

    /// ジェネレーターフィルタ（入力画像不要）を使用して MTLTexture を生成します。
    ///
    /// - Important: この API は GPU 完了を **同期的に待ちます**（`waitUntilCompleted`）。
    ///   `draw()` 内で毎フレーム呼ぶとフレーム落ちの直接原因になります。フレーム内で
    ///   使う場合は非ブロッキングの
    ///   ``generate(filterName:parameters:destination:commandBuffer:)`` を使って
    ///   既存のコマンドバッファへエンコードしてください。
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

    /// ジェネレーターフィルタを既存のコマンドバッファへエンコードします。
    ///
    /// フィルタ名不正・出力生成失敗の場合はクラッシュせず何もエンコードしません
    /// （警告ログを 1 回出力）。
    /// - Parameters:
    ///   - filterName: CIFilter 名文字列。
    ///   - parameters: フィルタパラメータ辞書。
    ///   - destination: 出力先テクスチャ。
    ///   - commandBuffer: エンコード先のコマンドバッファ。
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

    // MARK: - 内部ヘルパー

    /// パラメータを KVC で設定します。フィルタが持たないキーはクラッシュさせず
    /// 警告を出して無視します（キー名 typo で NSException になるのを防ぐ）。
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

    /// フィルタ適用に失敗したときのフォールバック: ソースをそのままコピーし、
    /// ポストプロセスチェーンの次段へ前フレームの内容やゴミが流れるのを防ぐ。
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

    /// 同一メッセージの警告はプロセス内で 1 回だけ出力します
    /// （ポストプロセスは毎フレーム呼ばれるためログ洪水を防ぐ）。
    private func warnOnce(_ message: String) {
        guard warnedMessages.insert(message).inserted else { return }
        print("[metaphor.CoreImage] Warning: \(message)")
    }
}
