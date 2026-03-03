import Metal

// MARK: - Vertex Descriptor Presets

/// Represent predefined vertex attribute layouts for Metal render pipelines.
public enum VertexLayout {
    /// Store only a float3 position (stride: 12 bytes).
    case position
    /// Store a float3 position and a float4 color (stride: 28 bytes).
    case positionColor
    /// Store a float3 position, float3 normal, and float4 color (stride: 40 bytes).
    case positionNormalColor
    /// Store a float3 position, float3 normal, and float2 UV (stride: 48 bytes, including alignment padding).
    case positionNormalUV
    /// Store a float2 position and a float4 color (stride: 24 bytes, designed for Canvas2D).
    case position2DColor
    /// Store a float2 position, float2 texture coordinate, and float4 color (stride: 32 bytes, designed for textured Canvas2D).
    case position2DTexCoordColor
    /// Store only a float2 position (stride: 8 bytes, designed for Canvas2D instancing unit meshes).
    case position2DOnly

    /// Create a Metal vertex descriptor matching this layout.
    ///
    /// - Returns: A configured `MTLVertexDescriptor` with the appropriate attribute formats, offsets, and strides.
    public func makeDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        switch self {
        case .position:
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride

        case .positionColor:
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float4
            descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride

        case .positionNormalColor:
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float3
            descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float4
            descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
            descriptor.attributes[2].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride

        case .positionNormalUV:
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float3
            descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float2
            descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
            descriptor.attributes[2].bufferIndex = 0
            // stride = 48: SIMD3(16) + SIMD3(16) + SIMD2(8) + 8bytes alignment padding
            descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 3

        case .position2DColor:
            descriptor.attributes[0].format = .float2
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float4
            descriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride

        case .position2DTexCoordColor:
            descriptor.attributes[0].format = .float2   // position
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float2   // texCoord
            descriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float4   // color (tint)
            descriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride * 2
            descriptor.attributes[2].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride

        case .position2DOnly:
            descriptor.attributes[0].format = .float2
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
        }

        return descriptor
    }
}

// MARK: - Blend Mode Presets

/// Define predefined blend modes for Metal color attachment configuration.
public enum BlendMode: CaseIterable, Hashable, Sendable {
    /// Disable blending (opaque rendering).
    case opaque
    /// Perform standard alpha blending.
    case alpha
    /// Perform additive blending.
    case additive
    /// Perform multiplicative blending.
    case multiply
    /// Perform screen blending (suitable for glow effects).
    case screen
    /// Perform subtractive blending.
    case subtract
    /// Keep the lighter value (max operation).
    case lightest
    /// Keep the darker value (min operation).
    case darkest
    /// Perform difference blending (|src - dst|).
    case difference
    /// Perform exclusion blending (src + dst - 2*src*dst).
    case exclusion

    /// Indicate whether this blend mode requires framebuffer fetch.
    public var requiresFramebufferFetch: Bool {
        switch self {
        case .difference, .exclusion: return true
        default: return false
        }
    }

    /// Apply this blend mode's configuration to a color attachment descriptor.
    ///
    /// - Parameter attachment: The color attachment descriptor to configure.
    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.isBlendingEnabled = false

        case .alpha:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        case .additive:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one

        case .multiply:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .destinationColor
            attachment.destinationRGBBlendFactor = .zero
            attachment.sourceAlphaBlendFactor = .destinationAlpha
            attachment.destinationAlphaBlendFactor = .zero

        case .screen:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceColor
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        case .subtract:
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .reverseSubtract
            attachment.alphaBlendOperation = .reverseSubtract
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one

        case .lightest:
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .max
            attachment.alphaBlendOperation = .max
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one

        case .darkest:
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .min
            attachment.alphaBlendOperation = .min
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one

        case .difference, .exclusion:
            // Compositing is handled on the shader side via framebuffer fetch.
            attachment.isBlendingEnabled = false
        }
    }
}

// MARK: - Depth Stencil Presets

/// Define predefined depth-stencil configurations for Metal render pipelines.
public enum DepthMode {
    /// Enable depth testing and writing (standard 3D rendering).
    case readWrite
    /// Enable depth testing but disable writing.
    case readOnly
    /// Disable depth testing (suitable for 2D rendering).
    case disabled

    /// Create a depth-stencil state for this mode.
    ///
    /// - Parameter device: The Metal device used to create the state object.
    /// - Returns: A configured `MTLDepthStencilState`, or `nil` if creation fails.
    public func makeState(device: MTLDevice) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()

        switch self {
        case .readWrite:
            descriptor.depthCompareFunction = .less
            descriptor.isDepthWriteEnabled = true
        case .readOnly:
            descriptor.depthCompareFunction = .less
            descriptor.isDepthWriteEnabled = false
        case .disabled:
            descriptor.depthCompareFunction = .always
            descriptor.isDepthWriteEnabled = false
        }

        return device.makeDepthStencilState(descriptor: descriptor)
    }
}

// MARK: - Pipeline Factory

/// Build Metal render pipeline states using a fluent builder pattern.
///
/// ```swift
/// let pipeline = try PipelineFactory(device: device)
///     .vertex(vertexFunction)
///     .fragment(fragmentFunction)
///     .vertexLayout(.positionNormalColor)
///     .blending(.alpha)
///     .build()
/// ```
public struct PipelineFactory {
    private let device: MTLDevice
    private var vertexFunction: MTLFunction?
    private var fragmentFunction: MTLFunction?
    private var vertexDescriptor: MTLVertexDescriptor?
    private var colorFormat: MTLPixelFormat = .bgra8Unorm
    private var depthFormat: MTLPixelFormat = .depth32Float
    private var blendMode: BlendMode = .opaque
    private var rasterSampleCount: Int = 4

    // MARK: - Initialization

    /// Create a new pipeline factory bound to the given Metal device.
    ///
    /// - Parameter device: The Metal device used to create pipeline states.
    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Builder Methods

    /// Set the vertex shader function.
    ///
    /// - Parameter function: The vertex function to use, or `nil` to clear.
    /// - Returns: A copy of this factory with the vertex function applied.
    public func vertex(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.vertexFunction = function
        return copy
    }

    /// Set the fragment shader function.
    ///
    /// - Parameter function: The fragment function to use, or `nil` to clear.
    /// - Returns: A copy of this factory with the fragment function applied.
    public func fragment(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.fragmentFunction = function
        return copy
    }

    /// Set the vertex layout using a predefined preset.
    ///
    /// - Parameter layout: The vertex layout preset to apply.
    /// - Returns: A copy of this factory with the vertex descriptor configured.
    public func vertexLayout(_ layout: VertexLayout) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = layout.makeDescriptor()
        return copy
    }

    /// Set a custom vertex descriptor.
    ///
    /// - Parameter descriptor: The Metal vertex descriptor to use.
    /// - Returns: A copy of this factory with the custom vertex descriptor applied.
    public func vertexDescriptor(_ descriptor: MTLVertexDescriptor) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = descriptor
        return copy
    }

    /// Set the color attachment pixel format.
    ///
    /// - Parameter format: The pixel format for the color attachment.
    /// - Returns: A copy of this factory with the color format applied.
    public func colorFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.colorFormat = format
        return copy
    }

    /// Set the depth attachment pixel format.
    ///
    /// - Parameter format: The pixel format for the depth attachment.
    /// - Returns: A copy of this factory with the depth format applied.
    public func depthFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.depthFormat = format
        return copy
    }

    /// Disable the depth attachment by setting its format to invalid.
    ///
    /// - Returns: A copy of this factory with depth disabled.
    public func noDepth() -> PipelineFactory {
        var copy = self
        copy.depthFormat = .invalid
        return copy
    }

    /// Set the blend mode for the color attachment.
    ///
    /// - Parameter mode: The blend mode to apply.
    /// - Returns: A copy of this factory with the blend mode applied.
    public func blending(_ mode: BlendMode) -> PipelineFactory {
        var copy = self
        copy.blendMode = mode
        return copy
    }

    /// Set the MSAA rasterization sample count.
    ///
    /// - Parameter count: The number of samples per pixel.
    /// - Returns: A copy of this factory with the sample count applied.
    public func sampleCount(_ count: Int) -> PipelineFactory {
        var copy = self
        copy.rasterSampleCount = count
        return copy
    }

    // MARK: - Build

    /// Build and return a configured render pipeline state.
    ///
    /// - Returns: A compiled `MTLRenderPipelineState` ready for use.
    /// - Throws: An error if pipeline creation fails.
    public func build() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        descriptor.rasterSampleCount = rasterSampleCount
        blendMode.apply(to: descriptor.colorAttachments[0])

        if depthFormat != .invalid {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Compute Pipeline

    /// Build a compute pipeline state from the given function.
    ///
    /// - Parameters:
    ///   - device: The Metal device used to create the pipeline state.
    ///   - function: The compute shader function.
    /// - Returns: A compiled `MTLComputePipelineState` ready for use.
    /// - Throws: An error if pipeline creation fails.
    public static func buildCompute(
        device: MTLDevice,
        function: MTLFunction
    ) throws -> MTLComputePipelineState {
        try device.makeComputePipelineState(function: function)
    }
}

// MARK: - Depth State Cache

/// Cache depth-stencil states to avoid redundant creation for the same depth mode.
@MainActor
public final class DepthStencilCache {
    private let device: MTLDevice
    private var cache: [DepthMode: MTLDepthStencilState] = [:]

    /// Create a new depth-stencil cache bound to the given Metal device.
    ///
    /// - Parameter device: The Metal device used to create depth-stencil states.
    public init(device: MTLDevice) {
        self.device = device
    }

    /// Retrieve the depth-stencil state for the specified mode, using a cached instance if available.
    ///
    /// - Parameter mode: The depth mode to look up.
    /// - Returns: The corresponding `MTLDepthStencilState`, or `nil` if creation fails.
    public func state(for mode: DepthMode) -> MTLDepthStencilState? {
        if let cached = cache[mode] {
            return cached
        }
        let state = mode.makeState(device: device)
        if let state = state {
            cache[mode] = state
        }
        return state
    }
}

// MARK: - DepthMode: Hashable

extension DepthMode: Hashable {}
