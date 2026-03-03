import CoreImage
import simd

/// Wrap a CoreImage filter parameter value in a Sendable-safe container.
public enum CIFilterValue: Sendable {
    case float(Float)
    case double(Double)
    case int(Int)
    case string(String)
    case vector(SIMD4<Float>)
    case bool(Bool)

    /// Convert to an `Any` value suitable for passing to a CIFilter.
    ///
    /// - Returns: The underlying value as `Any`, with SIMD4 converted to CIVector.
    public var anyValue: Any {
        switch self {
        case .float(let v): return v
        case .double(let v): return v
        case .int(let v): return v
        case .string(let v): return v
        case .vector(let v): return CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: CGFloat(v.w))
        case .bool(let v): return v
        }
    }
}

/// Represent a post-process effect type applied to the rendered frame.
public enum PostEffect: Sendable {
    /// Apply bloom (glow around high-luminance areas).
    case bloom(intensity: Float = 1.0, threshold: Float = 0.8)

    /// Apply color grading adjustments.
    case colorGrade(
        brightness: Float = 0.0,
        contrast: Float = 1.0,
        saturation: Float = 1.0,
        temperature: Float = 0.0
    )

    /// Apply chromatic aberration (color fringing).
    case chromaticAberration(intensity: Float = 0.005)

    /// Apply a vignette darkening at the edges.
    case vignette(intensity: Float = 0.5, smoothness: Float = 0.5)

    /// Invert all colors.
    case invert

    /// Convert to grayscale.
    case grayscale

    /// Apply a Gaussian blur.
    case blur(radius: Float = 5.0)

    /// Apply a custom post-process effect with a user-defined shader.
    case custom(CustomPostEffect)

    // MARK: - MPS Effects

    /// Apply an MPS hardware-optimized Gaussian blur with the given sigma value.
    case mpsBlur(sigma: Float)
    /// Apply MPS Sobel edge detection.
    case mpsSobel
    /// Apply MPS morphological erosion.
    case mpsErode(radius: Int = 1)
    /// Apply MPS morphological dilation.
    case mpsDilate(radius: Int = 1)

    // MARK: - CoreImage Effects

    /// Apply a CoreImage filter from a preset.
    case ciFilter(CIFilterPreset)
    /// Apply a CoreImage filter specified directly by name and parameter dictionary.
    case ciFilterRaw(name: String, parameters: [String: CIFilterValue])
}

/// Store uniform parameters for post-process shaders.
struct PostProcessParams {
    var texelSize: SIMD2<Float> = .zero
    var intensity: Float = 0
    var threshold: Float = 0
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var temperature: Float = 0
    var radius: Float = 0
    var smoothness: Float = 0
    var _pad0: Float = 0
    var _pad1: Float = 0
}
