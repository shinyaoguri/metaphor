@preconcurrency import Metal
import CoreImage
import MetaphorCore

// MARK: - CIFilterValue

/// Wrap a CoreImage filter parameter value in a Sendable-safe container.
public enum CIFilterValue: Sendable {
    case float(Float)
    case double(Double)
    case int(Int)
    case string(String)
    case vector(SIMD4<Float>)
    case bool(Bool)

    /// Convert to an `Any` value suitable for passing to a CIFilter.
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

// MARK: - CoreImage PostEffect Classes

/// Apply a CoreImage filter from a preset.
@MainActor
public final class CIFilterEffect: PostEffect {
    public let name = "ciFilter"
    public let preset: CIFilterPreset
    private var wrapper: CIFilterWrapper?

    public init(_ preset: CIFilterPreset) {
        self.preset = preset
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let w = wrapper ?? {
            let f = CIFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            wrapper = f
            return f
        }()
        let texSize = CGSize(width: input.width, height: input.height)
        w.apply(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: texSize),
            source: input, destination: output,
            commandBuffer: commandBuffer
        )
    }
}

/// Apply a CoreImage filter specified directly by name and parameter dictionary.
@MainActor
public final class CIFilterRawEffect: PostEffect {
    public let name = "ciFilterRaw"
    public let filterName: String
    public let parameters: [String: CIFilterValue]
    private var wrapper: CIFilterWrapper?

    public init(name: String, parameters: [String: CIFilterValue]) {
        self.filterName = name
        self.parameters = parameters
    }

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let w = wrapper ?? {
            let f = CIFilterWrapper(device: context.device, commandQueue: context.commandQueue)
            wrapper = f
            return f
        }()
        let anyParams = self.parameters.mapValues { $0.anyValue }
        w.apply(
            filterName: filterName,
            parameters: anyParams,
            source: input, destination: output,
            commandBuffer: commandBuffer
        )
    }
}
