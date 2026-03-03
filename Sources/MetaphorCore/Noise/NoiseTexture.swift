import Metal

/// Build Metal textures from noise value arrays.
enum NoiseTextureBuilder {
    /// Create a grayscale BGRA8 texture from a float array (0.0 to 1.0).
    /// - Parameters:
    ///   - device: Metal device to create the texture on.
    ///   - values: Flat array of noise values in row-major order.
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    /// - Returns: Metal texture containing the grayscale noise, or nil on failure.
    static func buildTexture(
        device: MTLDevice,
        values: [Float],
        width: Int,
        height: Int
    ) -> MTLTexture? {
        guard values.count == width * height else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<values.count {
            let v = UInt8(max(0, min(255, values[i] * 255)))
            let j = i * 4
            pixels[j]     = v   // B
            pixels[j + 1] = v   // G
            pixels[j + 2] = v   // R
            pixels[j + 3] = 255 // A
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return tex
    }

    /// Create a color-mapped texture from a float array using gradient stops.
    /// - Parameters:
    ///   - device: Metal device to create the texture on.
    ///   - values: Flat array of noise values in row-major order.
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    ///   - colorStops: Array of (position, BGRA color) pairs defining the gradient.
    /// - Returns: Metal texture with the color-mapped noise, or nil on failure.
    static func buildColorMappedTexture(
        device: MTLDevice,
        values: [Float],
        width: Int,
        height: Int,
        colorStops: [(Float, SIMD4<UInt8>)]
    ) -> MTLTexture? {
        guard values.count == width * height, colorStops.count >= 2 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let sortedStops = colorStops.sorted { $0.0 < $1.0 }

        for i in 0..<values.count {
            let t = max(0, min(1, values[i]))
            let color = interpolateColor(t: t, stops: sortedStops)
            let j = i * 4
            pixels[j]     = color.x // B
            pixels[j + 1] = color.y // G
            pixels[j + 2] = color.z // R
            pixels[j + 3] = color.w // A
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return tex
    }

    private static func interpolateColor(
        t: Float, stops: [(Float, SIMD4<UInt8>)]
    ) -> SIMD4<UInt8> {
        if t <= stops.first!.0 { return stops.first!.1 }
        if t >= stops.last!.0 { return stops.last!.1 }
        for i in 0..<(stops.count - 1) {
            if t >= stops[i].0 && t <= stops[i + 1].0 {
                let range = stops[i + 1].0 - stops[i].0
                let localT = range > 0 ? (t - stops[i].0) / range : 0
                let a = SIMD4<Float>(Float(stops[i].1.x), Float(stops[i].1.y), Float(stops[i].1.z), Float(stops[i].1.w))
                let b = SIMD4<Float>(Float(stops[i + 1].1.x), Float(stops[i + 1].1.y), Float(stops[i + 1].1.z), Float(stops[i + 1].1.w))
                let mixed = a + (b - a) * localT
                return SIMD4<UInt8>(
                    UInt8(max(0, min(255, mixed.x))),
                    UInt8(max(0, min(255, mixed.y))),
                    UInt8(max(0, min(255, mixed.z))),
                    UInt8(max(0, min(255, mixed.w)))
                )
            }
        }
        return stops.last!.1
    }
}
