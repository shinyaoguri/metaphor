import Metal

/// Builds a Metal texture from an array of noise values.
enum NoiseTextureBuilder {
    /// Creates a grayscale BGRA8 texture from a float array (0.0-1.0).
    /// - Parameters:
    ///   - device: The Metal device to create the texture on.
    ///   - values: A flat, row-major array of noise values.
    ///   - width: The texture width, in pixels.
    ///   - height: The texture height, in pixels.
    /// - Returns: A Metal texture containing the grayscale noise, or nil on failure.
    static func buildTexture(
        device: MTLDevice,
        values: [Float],
        width: Int,
        height: Int
    ) -> MTLTexture? {
        guard values.count == width * height else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<values.count {
            // NaN/∞ を明示的に弾く（UInt8 変換に非有限値を渡さない）
            let scaled = values[i] * 255
            let v = scaled.isFinite ? UInt8(max(0, min(255, scaled))) : 0
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
        // Apple Silicon 専用のため UMA の .shared を使う
        desc.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return tex
    }

    /// Creates a color-mapped texture from a float array using gradient stops.
    /// - Parameters:
    ///   - device: The Metal device to create the texture on.
    ///   - values: A flat, row-major array of noise values.
    ///   - width: The texture width, in pixels.
    ///   - height: The texture height, in pixels.
    ///   - colorStops: An array of (position, BGRA color) pairs defining the
    ///     gradient. At least 2 stops are required.
    /// - Returns: A Metal texture containing the color-mapped noise, or nil
    ///   if `values.count != width * height`, fewer than 2 color stops are
    ///   given, or texture allocation fails.
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
        // Apple Silicon 専用のため UMA の .shared を使う
        desc.storageMode = .shared

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
        guard !stops.isEmpty else { return SIMD4<UInt8>(0, 0, 0, 255) }
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
