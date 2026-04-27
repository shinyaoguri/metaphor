import Metal

// MARK: - 頂点デスクリプタプリセット

/// Metal レンダーパイプライン用の定義済み頂点属性レイアウト
public enum VertexLayout {
    /// float3 位置のみ格納 (ストライド: 12 バイト)
    case position
    /// float3 位置と float4 カラーを格納 (ストライド: 28 バイト)
    case positionColor
    /// float3 位置、float3 法線、float4 カラーを格納 (ストライド: 40 バイト)
    case positionNormalColor
    /// float3 位置、float3 法線、float2 UV を格納 (ストライド: 48 バイト、アライメントパディング含む)
    case positionNormalUV
    /// float2 位置と float4 カラーを格納 (ストライド: 24 バイト、Canvas2D 用)
    case position2DColor
    /// float2 位置、float2 テクスチャ座標、float4 カラーを格納 (ストライド: 32 バイト、テクスチャ付き Canvas2D 用)
    case position2DTexCoordColor
    /// float2 位置のみ格納 (ストライド: 8 バイト、Canvas2D インスタンシングユニットメッシュ用)
    case position2DOnly

    /// このレイアウトに一致する Metal 頂点デスクリプタを作成します。
    ///
    /// - Returns: 適切な属性フォーマット、オフセット、ストライドで構成された `MTLVertexDescriptor`
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
            // ストライド = 48: SIMD3(16) + SIMD3(16) + SIMD2(8) + 8バイトのアライメントパディング
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
            descriptor.attributes[0].format = .float2   // 位置
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float2   // テクスチャ座標
            descriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float4   // カラー (ティント)
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

// MARK: - ブレンドモードプリセット

/// Metal カラーアタッチメント設定用の定義済みブレンドモード
public enum BlendMode: CaseIterable, Hashable, Sendable {
    /// ブレンド無効（不透明レンダリング）
    case opaque
    /// 標準アルファブレンド
    case alpha
    /// 加算ブレンド
    case additive
    /// 乗算ブレンド
    case multiply
    /// スクリーンブレンド（グロウエフェクト向き）
    case screen
    /// 減算ブレンド
    case subtract
    /// 明るい方の値を保持（max 演算）
    case lightest
    /// 暗い方の値を保持（min 演算）
    case darkest
    /// 差分ブレンド (|src - dst|)
    case difference
    /// 除外ブレンド (src + dst - 2*src*dst)
    case exclusion

    /// このブレンドモードがフレームバッファフェッチを必要とするかどうか
    public var requiresFramebufferFetch: Bool {
        switch self {
        case .difference, .exclusion: return true
        default: return false
        }
    }

    /// このブレンドモードの設定をカラーアタッチメントデスクリプタに適用します。
    ///
    /// - Parameter attachment: 設定するカラーアタッチメントデスクリプタ
    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.isBlendingEnabled = false

        case .alpha:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            // 標準的な straight-alpha over: final.a = src.a + dst.a * (1 - src.a)
            // 以前は sourceAlphaBlendFactor = .sourceAlpha だったが、
            // それだと src.a が二乗されて出力テクスチャの α が極端に減衰し、
            // Syphon 等でアルファ合成する用途で透明と区別がつかなくなる。
            attachment.sourceAlphaBlendFactor = .one
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
            // コンポジットはフレームバッファフェッチ経由でシェーダー側で処理
            attachment.isBlendingEnabled = false
        }
    }
}

// MARK: - デプスステンシルプリセット

/// Metal レンダーパイプライン用の定義済みデプスステンシル設定
public enum DepthMode {
    /// デプステストと書き込みを有効化（標準 3D レンダリング）
    case readWrite
    /// デプステストを有効化、書き込みは無効化
    case readOnly
    /// デプステストを無効化（2D レンダリング向き）
    case disabled

    /// このモード用のデプスステンシルステートを作成します。
    ///
    /// - Parameter device: ステートオブジェクト作成に使用する Metal デバイス
    /// - Returns: 設定済みの `MTLDepthStencilState`。作成に失敗した場合は `nil`
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

// MARK: - パイプラインファクトリ

/// フルーエントビルダーパターンで Metal レンダーパイプラインステートを構築します。
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

    // MARK: - 初期化

    /// 指定された Metal デバイスにバインドされた新しいパイプラインファクトリを作成します。
    ///
    /// - Parameter device: パイプラインステート作成に使用する Metal デバイス
    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - ビルダーメソッド

    /// 頂点シェーダー関数を設定します。
    ///
    /// - Parameter function: 使用する頂点関数。クリアする場合は `nil`
    /// - Returns: 頂点関数が適用されたこのファクトリのコピー
    public func vertex(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.vertexFunction = function
        return copy
    }

    /// フラグメントシェーダー関数を設定します。
    ///
    /// - Parameter function: 使用するフラグメント関数。クリアする場合は `nil`
    /// - Returns: フラグメント関数が適用されたこのファクトリのコピー
    public func fragment(_ function: MTLFunction?) -> PipelineFactory {
        var copy = self
        copy.fragmentFunction = function
        return copy
    }

    /// 定義済みプリセットを使用して頂点レイアウトを設定します。
    ///
    /// - Parameter layout: 適用する頂点レイアウトプリセット
    /// - Returns: 頂点デスクリプタが設定されたこのファクトリのコピー
    public func vertexLayout(_ layout: VertexLayout) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = layout.makeDescriptor()
        return copy
    }

    /// カスタム頂点デスクリプタを設定します。
    ///
    /// - Parameter descriptor: 使用する Metal 頂点デスクリプタ
    /// - Returns: カスタム頂点デスクリプタが適用されたこのファクトリのコピー
    public func vertexDescriptor(_ descriptor: MTLVertexDescriptor) -> PipelineFactory {
        var copy = self
        copy.vertexDescriptor = descriptor
        return copy
    }

    /// カラーアタッチメントのピクセルフォーマットを設定します。
    ///
    /// - Parameter format: カラーアタッチメントのピクセルフォーマット
    /// - Returns: カラーフォーマットが適用されたこのファクトリのコピー
    public func colorFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.colorFormat = format
        return copy
    }

    /// デプスアタッチメントのピクセルフォーマットを設定します。
    ///
    /// - Parameter format: デプスアタッチメントのピクセルフォーマット
    /// - Returns: デプスフォーマットが適用されたこのファクトリのコピー
    public func depthFormat(_ format: MTLPixelFormat) -> PipelineFactory {
        var copy = self
        copy.depthFormat = format
        return copy
    }

    /// フォーマットを invalid に設定してデプスアタッチメントを無効化します。
    ///
    /// - Returns: デプスが無効化されたこのファクトリのコピー
    public func noDepth() -> PipelineFactory {
        var copy = self
        copy.depthFormat = .invalid
        return copy
    }

    /// カラーアタッチメントのブレンドモードを設定します。
    ///
    /// - Parameter mode: 適用するブレンドモード
    /// - Returns: ブレンドモードが適用されたこのファクトリのコピー
    public func blending(_ mode: BlendMode) -> PipelineFactory {
        var copy = self
        copy.blendMode = mode
        return copy
    }

    /// MSAA ラスタライゼーションサンプル数を設定します。
    ///
    /// - Parameter count: ピクセルあたりのサンプル数
    /// - Returns: サンプル数が適用されたこのファクトリのコピー
    public func sampleCount(_ count: Int) -> PipelineFactory {
        var copy = self
        copy.rasterSampleCount = count
        return copy
    }

    // MARK: - ビルド

    /// 設定済みのレンダーパイプラインステートをビルドして返します。
    ///
    /// - Returns: 使用可能なコンパイル済み `MTLRenderPipelineState`
    /// - Throws: パイプライン作成に失敗した場合のエラー
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

    // MARK: - コンピュートパイプライン

    /// 指定された関数からコンピュートパイプラインステートをビルドします。
    ///
    /// - Parameters:
    ///   - device: パイプラインステート作成に使用する Metal デバイス
    ///   - function: コンピュートシェーダー関数
    /// - Returns: 使用可能なコンパイル済み `MTLComputePipelineState`
    /// - Throws: パイプライン作成に失敗した場合のエラー
    public static func buildCompute(
        device: MTLDevice,
        function: MTLFunction
    ) throws -> MTLComputePipelineState {
        try device.makeComputePipelineState(function: function)
    }
}

// MARK: - デプスステートキャッシュ

/// 同一デプスモードの冗長な作成を回避するためにデプスステンシルステートをキャッシュします。
@MainActor
public final class DepthStencilCache {
    private let device: MTLDevice
    private var cache: [DepthMode: MTLDepthStencilState] = [:]

    /// 指定された Metal デバイスにバインドされた新しいデプスステンシルキャッシュを作成します。
    ///
    /// - Parameter device: デプスステンシルステート作成に使用する Metal デバイス
    public init(device: MTLDevice) {
        self.device = device
    }

    /// 指定されたモードのデプスステンシルステートを取得します。キャッシュ済みインスタンスがあればそれを使用します。
    ///
    /// - Parameter mode: ルックアップするデプスモード
    /// - Returns: 対応する `MTLDepthStencilState`。作成に失敗した場合は `nil`
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
