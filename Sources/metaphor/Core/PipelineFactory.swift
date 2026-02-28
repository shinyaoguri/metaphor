import Metal

// MARK: - Vertex Descriptor Presets

/// 定義済み頂点レイアウト
public enum VertexLayout {
    /// float3 position のみ (stride: 12 bytes)
    case position
    /// float3 position + float4 color (stride: 28 bytes)
    case positionColor
    /// float3 position + float3 normal + float4 color (stride: 40 bytes)
    case positionNormalColor
    /// float3 position + float3 normal + float2 uv (stride: 48 bytes, alignment padding含む)
    case positionNormalUV
    /// float2 position + float4 color (stride: 24 bytes, Canvas2D用)
    case position2DColor
    /// float2 position + float2 texCoord + float4 color (stride: 32 bytes, テクスチャ付きCanvas2D用)
    case position2DTexCoordColor

    /// MTLVertexDescriptorを生成
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
        }

        return descriptor
    }
}

// MARK: - Blend Mode Presets

/// 定義済みブレンドモード
public enum BlendMode: CaseIterable, Hashable, Sendable {
    /// ブレンディングなし（不透明）
    case opaque
    /// 標準アルファブレンディング
    case alpha
    /// 加算ブレンディング
    case additive
    /// 乗算ブレンディング
    case multiply
    /// スクリーンブレンディング（グロー効果向き）
    case screen
    /// 減算ブレンディング
    case subtract
    /// 明るい方を残す（max）
    case lightest
    /// 暗い方を残す（min）
    case darkest

    /// MTLRenderPipelineColorAttachmentDescriptorにブレンド設定を適用
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
        }
    }
}

// MARK: - Depth Stencil Presets

/// 定義済み深度ステンシル設定
public enum DepthMode {
    /// 深度テスト・書き込み有効（標準3D）
    case readWrite
    /// 深度テスト有効・書き込み無効
    case readOnly
    /// 深度テスト無効（2D描画用）
    case disabled

    /// MTLDepthStencilStateを生成
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

/// ビルダーパターンでMetal PipelineStateを簡単に作成するファクトリ
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

    // MARK: - Initialization

    /// 初期化
    /// - Parameter device: MTLDevice
    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Builder Methods

    /// 頂点シェーダー関数を設定
    public func vertex(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.vertexFunction = function
        return copy
    }

    /// フラグメントシェーダー関数を設定
    public func fragment(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.fragmentFunction = function
        return copy
    }

    /// 頂点レイアウトプリセットを設定
    public func vertexLayout(_ layout: VertexLayout) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = layout.makeDescriptor()
        return copy
    }

    /// カスタム頂点ディスクリプタを設定
    public func vertexDescriptor(_ descriptor: MTLVertexDescriptor) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = descriptor
        return copy
    }

    /// カラーピクセルフォーマットを設定
    public func colorFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.colorFormat = format
        return copy
    }

    /// デプスピクセルフォーマットを設定
    public func depthFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.depthFormat = format
        return copy
    }

    /// デプスフォーマットをなしに設定
    public func noDepth() -> PipelineFactory {
        var copy = self
        copy.depthFormat = .invalid
        return copy
    }

    /// ブレンドモードを設定
    public func blending(_ mode: BlendMode) -> PipelineFactory {
        var copy = self
        copy.blendMode = mode
        return copy
    }

    // MARK: - Build

    /// RenderPipelineStateをビルド
    /// - Returns: MTLRenderPipelineState
    /// - Throws: パイプライン作成エラー
    public func build() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        blendMode.apply(to: descriptor.colorAttachments[0])

        if depthFormat != .invalid {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Compute Pipeline

    /// ComputePipelineStateをビルド
    /// - Parameter function: コンピュートシェーダー関数
    /// - Returns: MTLComputePipelineState
    /// - Throws: パイプライン作成エラー
    public static func buildCompute(
        device: MTLDevice,
        function: MTLFunction
    ) throws -> MTLComputePipelineState {
        try device.makeComputePipelineState(function: function)
    }
}

// MARK: - Depth State Cache

/// 深度ステンシルステートのキャッシュ
@MainActor
public final class DepthStencilCache {
    private let device: MTLDevice
    private var cache: [DepthMode: MTLDepthStencilState] = [:]

    public init(device: MTLDevice) {
        self.device = device
    }

    /// 指定したモードの深度ステンシルステートを取得（キャッシュ付き）
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
