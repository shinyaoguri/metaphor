import Testing
import CoreML
import CoreVideo
import Metal
import simd
@testable import MetaphorML

// MARK: - MLTextureConverter Tests

@Suite("MLTextureConverter", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLTextureConverterTests {

    @Test("pixelBuffer from shared texture")
    func pixelBufferFromShared() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        // Fill with solid red (BGRA: 0, 0, 255, 255)
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 0  // B
            pixels[i + 1] = 0  // G
            pixels[i + 2] = 255  // R
            pixels[i + 3] = 255  // A
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: 4 * 4
        )

        let pb = converter.pixelBuffer(from: texture)
        #expect(pb != nil)
        if let pb = pb {
            #expect(CVPixelBufferGetWidth(pb) == 4)
            #expect(CVPixelBufferGetHeight(pb) == 4)
        }
    }

    @Test("texture from CVPixelBuffer round-trip")
    func textureFromPixelBuffer() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferCreate(
            nil, 8, 8, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        #expect(pixelBuffer != nil)

        if let pb = pixelBuffer {
            let tex = converter.texture(from: pb)
            #expect(tex != nil)
            #expect(tex?.width == 8)
            #expect(tex?.height == 8)
        }
    }

    @Test("cgImage round-trip")
    func cgImageRoundTrip() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a simple CGImage
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            Issue.record("Failed to create CGContext")
            return
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create CGImage")
            return
        }

        let tex = converter.texture(from: cgImage)
        #expect(tex != nil)
        #expect(tex?.width == 4)
        #expect(tex?.height == 4)

        if let tex = tex {
            let roundTrip = converter.cgImage(from: tex)
            #expect(roundTrip != nil)
            #expect(roundTrip?.width == 4)
            #expect(roundTrip?.height == 4)
        }
    }

    @Test("texture(from:) がバッファプールを枯渇させない（Issue #248）")
    func textureFromPixelBufferDoesNotStarveBufferPool() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // カメラ入力と同等の条件（IOSurface 裏付き・Metal 互換）のプール
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var poolOut: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &poolOut)
        let pool = try #require(poolOut)

        // threshold はプール外へ retain され得るバッファ数の上限。解放済みの
        // はずのバッファがテクスチャキャッシュ経由で retain され続けると
        // kCVReturnWouldExceedAllocationThreshold で取得に失敗する
        let threshold = 4
        let aux = [kCVPixelBufferPoolAllocationThresholdKey as String: threshold]

        for i in 0..<(threshold * 4) {
            let status = autoreleasepool { () -> CVReturn in
                var bufferOut: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                    nil, pool, aux as CFDictionary, &bufferOut)
                guard status == kCVReturnSuccess, let buffer = bufferOut else { return status }
                _ = converter.texture(from: buffer)
                // MTLTexture と CVMetalTexture ラッパーはこのスコープ終端で解放
                // され、バッファはプールへ戻って次のイテレーションで再利用できる。
                // テクスチャ⇄ラッパーの循環参照があると両者が不死化してバッファを
                // retain し続け、プールが枯渇する（Issue #248 の実態）
                return status
            }
            #expect(
                status == kCVReturnSuccess,
                "iteration \(i): pool exhausted — texture cache is retaining released buffers")
            if status != kCVReturnSuccess { break }
        }
    }

    @Test("キャッシュ flush 後も保持中のテクスチャは元のフレーム内容を保つ")
    func liveTextureSurvivesCacheFlush() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 4,
            kCVPixelBufferHeightKey as String: 4,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var poolOut: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &poolOut)
        let pool = try #require(poolOut)

        func makeBuffer(filledWith value: UInt8) throws -> CVPixelBuffer {
            var bufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferOut)
            let buffer = try #require(bufferOut)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(value), CVPixelBufferGetBytesPerRow(buffer) * 4)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return buffer
        }

        // 0xAB で塗ったフレームのゼロコピーテクスチャを保持し続ける
        let heldTexture = try #require(converter.texture(from: makeBuffer(filledWith: 0xAB)))

        // 別フレームの変換を繰り返す（この中で flush が走り、プールが
        // 元のバッファを再利用しようとする機会を与える）
        for _ in 0..<8 {
            autoreleasepool {
                guard let other = try? makeBuffer(filledWith: 0x00) else { return }
                _ = converter.texture(from: other)
            }
        }

        // 保持中のテクスチャが flush・バッファ再利用で破壊されていないこと
        var pixels = [UInt8](repeating: 0, count: heldTexture.width * heldTexture.height * 4)
        heldTexture.getBytes(
            &pixels,
            bytesPerRow: heldTexture.width * 4,
            from: MTLRegionMake2D(0, 0, heldTexture.width, heldTexture.height),
            mipmapLevel: 0)
        #expect(pixels.allSatisfy { $0 == 0xAB })
    }

    @Test("texture from strided MLMultiArray respects strides")
    func textureFromStridedMultiArray() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let values: [Float] = [0.0, 1.0, 0.9, 0.5, 0.25, 0.8]
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: values.count)
        pointer.initialize(from: values, count: values.count)
        let multiArray = try MLMultiArray(
            dataPointer: pointer,
            shape: [2, 2],
            dataType: .float32,
            strides: [3, 1],
            deallocator: { _ in
                pointer.deinitialize(count: values.count)
                pointer.deallocate()
            }
        )

        guard let texture = converter.texture(from: multiArray, normalize: false) else {
            Issue.record("Expected texture")
            return
        }

        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: 2 * 4,
            from: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0
        )

        #expect(pixels[0] == 0)
        #expect(pixels[4] == 255)
        #expect(pixels[8] == 127)
        #expect(pixels[12] == 63)
    }

    // MARK: - dataType ごとの読み出し経路（#1102）
    //
    // 元は 1 本のジェネリックなローカル関数がクロージャ経由で 5 つの型を捌いており、
    // テストは .float32 しか通っていなかった。その形が Xcode 26.4.1 の SIL 最適化を
    // 落とすため 2 本のジェネリック関数へ分けたので、**どの経路も同じ絵を出すこと**を
    // ここで押さえる。上の strided テストと同じ配置・同じ期待値に揃えてある
    // （(0,0)=最小 / (0,1)=最大 / (1,0)=中間 / (1,1)=1/4）。

    @Test("texture from Double MLMultiArray matches the Float path")
    func textureFromDoubleMultiArray() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let values: [Double] = [0.0, 1.0, 0.9, 0.5, 0.25, 0.8]
        let pointer = UnsafeMutablePointer<Double>.allocate(capacity: values.count)
        pointer.initialize(from: values, count: values.count)
        let multiArray = try MLMultiArray(
            dataPointer: pointer,
            shape: [2, 2],
            dataType: .double,
            strides: [3, 1],
            deallocator: { _ in
                pointer.deinitialize(count: values.count)
                pointer.deallocate()
            }
        )

        guard let texture = converter.texture(from: multiArray, normalize: false) else {
            Issue.record("Expected texture")
            return
        }

        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        texture.getBytes(
            &pixels, bytesPerRow: 2 * 4, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)

        #expect(pixels[0] == 0)
        #expect(pixels[4] == 255)
        #expect(pixels[8] == 127)
        #expect(pixels[12] == 63)
    }

    @Test("texture from Float16 MLMultiArray matches the Float path")
    func textureFromFloat16MultiArray() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // 0.25 / 0.5 / 1.0 は Float16 でも正確に表せる（誤差の出る 0.9 / 0.8 は
        // strides の都合で読まれない位置に置いてある）。
        let values: [Float16] = [0.0, 1.0, 0.9, 0.5, 0.25, 0.8]
        let pointer = UnsafeMutablePointer<Float16>.allocate(capacity: values.count)
        pointer.initialize(from: values, count: values.count)
        let multiArray = try MLMultiArray(
            dataPointer: pointer,
            shape: [2, 2],
            dataType: .float16,
            strides: [3, 1],
            deallocator: { _ in
                pointer.deinitialize(count: values.count)
                pointer.deallocate()
            }
        )

        guard let texture = converter.texture(from: multiArray, normalize: false) else {
            Issue.record("Expected texture")
            return
        }

        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        texture.getBytes(
            &pixels, bytesPerRow: 2 * 4, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)

        #expect(pixels[0] == 0)
        #expect(pixels[4] == 255)
        #expect(pixels[8] == 127)
        #expect(pixels[12] == 63)
    }

    @Test("texture from Int32 MLMultiArray normalizes like the Float path")
    func textureFromInt32MultiArray() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // 整数なので 0..1 の生値では中間調が作れない。min-max 正規化に通して
        // 0 / 4 / 2 / 1 を 0 / 1.0 / 0.5 / 0.25 に写し、上と同じ期待値に揃える。
        let values: [Int32] = [0, 4, 99, 2, 1, 99]
        let pointer = UnsafeMutablePointer<Int32>.allocate(capacity: values.count)
        pointer.initialize(from: values, count: values.count)
        let multiArray = try MLMultiArray(
            dataPointer: pointer,
            shape: [2, 2],
            dataType: .int32,
            strides: [3, 1],
            deallocator: { _ in
                pointer.deinitialize(count: values.count)
                pointer.deallocate()
            }
        )

        guard let texture = converter.texture(from: multiArray, normalize: true) else {
            Issue.record("Expected texture")
            return
        }

        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        texture.getBytes(
            &pixels, bytesPerRow: 2 * 4, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)

        #expect(pixels[0] == 0)
        #expect(pixels[4] == 255)
        #expect(pixels[8] == 127)
        #expect(pixels[12] == 63)
    }
}
