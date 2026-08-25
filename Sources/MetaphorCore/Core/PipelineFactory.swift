import Metal

// MARK: - 頂点デスクリプタプリセット

/// Predefined vertex attribute layouts for Metal render pipelines.
///
/// Offsets and strides are written as byte literals rather than `MemoryLayout` arithmetic,
/// because a vertex descriptor declares the bytes handed to the GPU. That those literals agree
/// with the Swift vertex structs which actually write those bytes is checked by
/// `VertexLayoutParityTests`, which names each struct (issue #1158).
///
/// Arithmetic invites expressions that produce the right number only by coincidence. The color
/// of ``position2DColor`` starts at byte 8 because `Canvas2D.Vertex2D` begins with two `Float`
/// fields — not because `MemoryLayout<SIMD2<Float>>.stride` is 8. That struct contains no
/// `SIMD2` at all, so adding one more `Float` to it moves the color to byte 12.
public enum VertexLayout {
    /// Stores a float3 position (stride: 16 bytes).
    ///
    /// No Swift vertex struct writes this layout. The float3 sits in the 16-byte slot a
    /// `SIMD3<Float>` occupies, the same way ``positionNormalColor`` counts it; this is not a
    /// 12-byte packed layout.
    case position
    /// Stores a float3 position and a float4 color (stride: 32 bytes).
    ///
    /// No Swift vertex struct writes this layout. The color starts at byte 16, not byte 12.
    case positionColor
    /// Stores a float3 position, a float3 normal and a float4 color (stride: 48 bytes).
    ///
    /// Matches the bytes written by `Vertex3D`.
    case positionNormalColor
    /// Stores a float3 position, a float3 normal and a float2 UV (stride: 48 bytes).
    ///
    /// Matches the bytes written by `Vertex3DTextured`. The stride includes the 8 bytes of
    /// alignment padding that follow the UV.
    case positionNormalUV
    /// Stores a float2 position and a float4 color (stride: 24 bytes, for Canvas2D).
    ///
    /// Matches the bytes written by `Canvas2D.Vertex2D`.
    case position2DColor
    /// Stores a float2 position, texture coordinates and a float4 color (stride: 32 bytes).
    ///
    /// Matches the bytes written by `Canvas2D.TexturedVertex2D`, used for textured drawing.
    case position2DTexCoordColor
    /// Stores a float2 position (stride: 8 bytes, for the Canvas2D instancing unit meshes).
    ///
    /// Matches the `[SIMD2<Float>]` that `UnitMesh2D` uploads without an intermediate struct.
    case position2DOnly

    /// Creates a Metal vertex descriptor matching this layout.
    ///
    /// - Returns: An `MTLVertexDescriptor` configured with the attribute formats, offsets and
    ///   stride for this layout.
    public func makeDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        switch self {
        case .position:
            // 相手の構造体は無し。float3 は 16 バイト枠（12 バイトのパックではない）。
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.layouts[0].stride = 16

        case .positionColor:
            // 相手の構造体は無し。
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float4
            descriptor.attributes[1].offset = 16
            descriptor.attributes[1].bufferIndex = 0
            descriptor.layouts[0].stride = 32

        case .positionNormalColor:
            // Vertex3D: position @0 / normal @16 / color @32、stride 48。
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float3
            descriptor.attributes[1].offset = 16
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float4
            descriptor.attributes[2].offset = 32
            descriptor.attributes[2].bufferIndex = 0
            descriptor.layouts[0].stride = 48

        case .positionNormalUV:
            // Vertex3DTextured: position @0 / normal @16 / uv @32、stride 48
            //（uv は 8 バイトで、後ろに 8 バイトのアライメントパディングが付く）。
            descriptor.attributes[0].format = .float3
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float3
            descriptor.attributes[1].offset = 16
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float2
            descriptor.attributes[2].offset = 32
            descriptor.attributes[2].bufferIndex = 0
            descriptor.layouts[0].stride = 48

        case .position2DColor:
            // Canvas2D.Vertex2D: posX/posY @0 / r,g,b,a @8、stride 24（Float が 6 本）。
            descriptor.attributes[0].format = .float2
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float4
            descriptor.attributes[1].offset = 8
            descriptor.attributes[1].bufferIndex = 0
            descriptor.layouts[0].stride = 24

        case .position2DTexCoordColor:
            // Canvas2D.TexturedVertex2D: posX/posY @0 / u,v @8 / r,g,b,a @16、
            // stride 32（Float が 8 本）。
            descriptor.attributes[0].format = .float2  // 位置
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.attributes[1].format = .float2  // テクスチャ座標
            descriptor.attributes[1].offset = 8
            descriptor.attributes[1].bufferIndex = 0
            descriptor.attributes[2].format = .float4  // カラー (ティント)
            descriptor.attributes[2].offset = 16
            descriptor.attributes[2].bufferIndex = 0
            descriptor.layouts[0].stride = 32

        case .position2DOnly:
            // UnitMesh2D が流す [SIMD2<Float>]。
            descriptor.attributes[0].format = .float2
            descriptor.attributes[0].offset = 0
            descriptor.attributes[0].bufferIndex = 0
            descriptor.layouts[0].stride = 8
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
    ///
    /// 分離可能ブレンドモードは `mix(dst, blend(src, dst), src.a)` という形をとる
    /// （src の α は「混ぜ方をどれだけ効かせるか」。ADR-0012）。これは固定関数の
    /// ブレンド係数の積和に乗らないので、キャンバスの値をフラグメントで読んで合成する。
    /// 実装は `Shaders/Metal/MetaphorCanvas2DBlend.h`。
    public var requiresFramebufferFetch: Bool {
        switch self {
        case .multiply, .screen, .subtract, .lightest, .darkest, .difference, .exclusion:
            return true
        case .opaque, .alpha, .additive:
            return false
        }
    }

    /// フェッチ経路のフラグメント関数名に使う接尾辞。固定関数で足りるモードでは `nil`。
    ///
    /// 関数名は `metaphor_canvas2D<系統><接尾辞>Fragment` の形に揃えてあり、
    /// `Canvas2DPipelineStore` がここから組み立てます（`.metal` 側は
    /// `METAPHOR_CANVAS2D_BLEND_FRAGMENT` マクロが同じ名前で定義する）。
    var fragmentFunctionSuffix: String? {
        switch self {
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .subtract: return "Subtract"
        case .lightest: return "Lightest"
        case .darkest: return "Darkest"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .opaque, .alpha, .additive: return nil
        }
    }

    /// このブレンドモードの設定をカラーアタッチメントデスクリプタに適用します。
    ///
    /// **組み込みフラグメントは premultiplied alpha を返す**（ADR-0012）。ここの係数は
    /// その前提で書かれているので、`src.a` を掛け直してはいけない。
    ///
    /// - Parameter attachment: 設定するカラーアタッチメントデスクリプタ
    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.isBlendingEnabled = false

        case .alpha:
            // premultiplied over: final.rgb = src.rgb + dst.rgb * (1 - src.a)
            //                     final.a   = src.a   + dst.a   * (1 - src.a)
            // src.rgb には既に α が掛かっている（フラグメントが premultiplied を返す）。
            // 以前はここで `.sourceAlpha` を掛けていたが、それだと premultiplied な
            // テクスチャ（グリフアトラス・読み込んだ画像・オフスクリーン）を貼るたびに
            // α が二重に掛かっていた（#846 / #847）。
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        case .additive:
            // final.rgb = dst.rgb + src.a * src_straight.rgb（= premultiplied な src.rgb）
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one

        case .multiply, .screen, .subtract, .lightest, .darkest, .difference, .exclusion:
            // 分離可能ブレンドモードは固定関数では書けない（`requiresFramebufferFetch`）。
            // 合成はフレームバッファフェッチでシェーダー側が行うので、ここでは無効にする。
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
    /// - Throws: ``MetaphorError/pipelineCreationFailed(name:underlying:)``
    ///   パイプラインステートの作成に失敗した場合。`name` は設定済みの
    ///   頂点関数名・フラグメント関数名から組み立てられます。
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

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // Metal の生 NSError を素通りさせず MetaphorError へ包む
            // (エラー契約: MetaphorError.swift の「エラー契約」節を参照)
            throw MetaphorError.pipelineCreationFailed(name: pipelineName, underlying: error)
        }
    }

    /// 診断用のパイプライン名。設定済みの頂点・フラグメント関数名から組み立てます。
    private var pipelineName: String {
        let parts = [vertexFunction?.name, fragmentFunction?.name].compactMap { $0 }
        return parts.isEmpty ? "unnamed" : parts.joined(separator: "+")
    }

    // MARK: - コンピュートパイプライン

    /// 指定された関数からコンピュートパイプラインステートをビルドします。
    ///
    /// - Parameters:
    ///   - device: パイプラインステート作成に使用する Metal デバイス
    ///   - function: コンピュートシェーダー関数
    /// - Returns: 使用可能なコンパイル済み `MTLComputePipelineState`
    /// - Throws: ``MetaphorError/pipelineCreationFailed(name:underlying:)``
    ///   パイプラインステートの作成に失敗した場合
    public static func buildCompute(
        device: MTLDevice,
        function: MTLFunction
    ) throws -> MTLComputePipelineState {
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            throw MetaphorError.pipelineCreationFailed(name: function.name, underlying: error)
        }
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

    /// キャッシュ済みデプスステンシルステートをすべて破棄します。
    public func clear() {
        cache.removeAll()
    }
}

// MARK: - DepthMode: Hashable

extension DepthMode: Hashable {}
