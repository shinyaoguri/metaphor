import Metal
import simd

/// `environment()` で選べる環境プリセット。
///
/// いずれも手続き的に生成されるので、HDR 画像などのアセットを用意する必要はありません。
public enum EnvironmentPreset: Int, Sendable, CaseIterable {
    /// 天井の白いパネルと暗い床を持つ無彩色のスタジオ。素材の質感を見るのに向きます。
    case studio = 0
    /// 地平線のオレンジから上空の青へ抜けるグラデーションと、低い太陽。
    case sunset = 1
    /// 曇天の白いドーム。全方位から柔らかい光が来るので影の輪郭が出にくくなります。
    case overcast = 2
}

/// IBL（image-based lighting）と skybox に使う環境キューブマップ一式。
///
/// プリセットの解析式から環境キューブを焼き、そこから拡散用のイラディアンスと
/// 鏡面用のプリフィルタ済み mip 連鎖を作ります。ベイクは compute で 3 段、
/// **プリセットにつき 1 回だけ**走り、結果は ``shared(preset:device:shaderLibrary:)``
/// のキャッシュで使い回されます（毎フレームのコストはサンプリングのみ）。
///
/// サンプル数はすべて固定なので、同じプリセットからは常に同じテクスチャが焼けます。
@MainActor
final class IBLEnvironment {

    // MARK: - Properties

    /// このインスタンスが表す環境プリセット。
    let preset: EnvironmentPreset

    /// 環境そのもの（skybox の描画に使う）。mip 連鎖つき。
    let environmentTexture: MTLTexture

    /// コサイン畳み込み済みのイラディアンス（拡散 IBL）。
    let irradianceTexture: MTLTexture

    /// roughness ごとに GGX でプリフィルタした鏡面 IBL。mip 0 が鏡面、最上位が最も粗い。
    let prefilteredTexture: MTLTexture

    // MARK: - 焼き上げ設定

    /// 環境キューブの一辺。skybox の見た目とプリフィルタの入力を兼ねる。
    private static let environmentSize = 128
    /// イラディアンスの一辺。低周波なので小さくてよい。
    private static let irradianceSize = 32
    /// 鏡面プリフィルタの一辺（mip 0）。
    private static let prefilteredSize = 128
    /// 鏡面プリフィルタの mip 数（roughness 0…1 を等分する）。
    private static let prefilteredMipCount = 5
    /// 鏡面プリフィルタの 1 テクセルあたりのサンプル数。
    private static let prefilterSampleCount = 128

    /// `MetaphorIBL.metal` を登録するライブラリキー。
    private static let libraryKey = "metaphor.ibl"

    // MARK: - キャッシュ

    private struct CacheKey: Hashable {
        let device: ObjectIdentifier
        let preset: Int
    }

    private static var cache: [CacheKey: IBLEnvironment] = [:]

    /// プリセットに対応する環境を返します。初回だけベイクし、以降はキャッシュを返します。
    ///
    /// - Parameters:
    ///   - preset: 環境プリセット。
    ///   - device: Metal デバイス。
    ///   - shaderLibrary: ベイクカーネルのコンパイルに使うシェーダーライブラリ。
    /// - Returns: 焼き上がった環境。
    /// - Throws: テクスチャ作成・シェーダーコンパイル・パイプライン作成に失敗した場合。
    static func shared(
        preset: EnvironmentPreset,
        device: MTLDevice,
        shaderLibrary: ShaderLibrary
    ) throws -> IBLEnvironment {
        let key = CacheKey(device: ObjectIdentifier(device), preset: preset.rawValue)
        if let cached = cache[key] { return cached }

        let environment = try IBLEnvironment(preset: preset, device: device, shaderLibrary: shaderLibrary)
        cache[key] = environment
        return environment
    }

    /// テスト用: ベイク結果のキャッシュを捨てます。
    static func clearCacheForTesting() {
        cache.removeAll()
    }

    // MARK: - Initialization

    private init(preset: EnvironmentPreset, device: MTLDevice, shaderLibrary: ShaderLibrary) throws {
        self.preset = preset

        self.environmentTexture = try Self.makeCube(
            device: device, size: Self.environmentSize,
            mipmapLevelCount: nil, label: "IBL Environment")
        self.irradianceTexture = try Self.makeCube(
            device: device, size: Self.irradianceSize,
            mipmapLevelCount: 1, label: "IBL Irradiance")
        self.prefilteredTexture = try Self.makeCube(
            device: device, size: Self.prefilteredSize,
            mipmapLevelCount: Self.prefilteredMipCount, label: "IBL Prefiltered")

        // ベイクカーネルを用意する（`.metallib` が使えるビルドでも、遅延登録した
        // キーは ShaderLibrary に無いのでソースからコンパイルする。ShadowMap と同じ扱い）
        if !shaderLibrary.hasLibrary(for: Self.libraryKey) {
            guard let source = ShaderLibrary.loadShaderSource("ibl") else {
                throw MetaphorError.shaderNotFound("ibl")
            }
            try shaderLibrary.register(source: source, as: Self.libraryKey)
        }

        let bakePipeline = try Self.computePipeline(
            named: "metaphor_iblBakeEnvironment", device: device, shaderLibrary: shaderLibrary)
        let irradiancePipeline = try Self.computePipeline(
            named: "metaphor_iblIrradiance", device: device, shaderLibrary: shaderLibrary)
        let prefilterPipeline = try Self.computePipeline(
            named: "metaphor_iblPrefilter", device: device, shaderLibrary: shaderLibrary)

        // ベイクは 1 プリセットにつき 1 回きりなので、毎フレームの compute フェーズには
        // 相乗りせず専用のコマンドバッファで完了まで待つ（環境が揃う前に描き始めない）。
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        commandBuffer.label = "IBL Bake (\(preset))"

        try Self.encodeBakeEnvironment(
            commandBuffer: commandBuffer, pipeline: bakePipeline,
            target: environmentTexture, preset: preset)

        // プリフィルタが mip を引けるよう、環境キューブの mip 連鎖を作る
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "IBL Environment Mipmaps"
            blit.generateMipmaps(for: environmentTexture)
            blit.endEncoding()
        }

        try Self.encodeIrradiance(
            commandBuffer: commandBuffer, pipeline: irradiancePipeline,
            source: environmentTexture, target: irradianceTexture)

        try Self.encodePrefilter(
            commandBuffer: commandBuffer, pipeline: prefilterPipeline,
            source: environmentTexture, target: prefilteredTexture)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - ベイクの各段

    private static func encodeBakeEnvironment(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        target: MTLTexture,
        preset: EnvironmentPreset
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        encoder.label = "IBL Bake Environment"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(try arrayView(of: target, level: 0), index: 0)

        var params = IBLBakeParams(
            size: UInt32(target.width), preset: UInt32(preset.rawValue),
            sampleCount: 0, roughness: 0)
        encoder.setBytes(&params, length: MemoryLayout<IBLBakeParams>.stride, index: 0)
        dispatch(encoder, size: target.width)
        encoder.endEncoding()
    }

    private static func encodeIrradiance(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        source: MTLTexture,
        target: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        encoder.label = "IBL Irradiance"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(try arrayView(of: target, level: 0), index: 1)

        var params = IBLBakeParams(
            size: UInt32(target.width), preset: 0, sampleCount: 0, roughness: 0)
        encoder.setBytes(&params, length: MemoryLayout<IBLBakeParams>.stride, index: 0)
        dispatch(encoder, size: target.width)
        encoder.endEncoding()
    }

    private static func encodePrefilter(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        source: MTLTexture,
        target: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        encoder.label = "IBL Prefilter"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)

        let mipCount = target.mipmapLevelCount
        for level in 0..<mipCount {
            let size = max(target.width >> level, 1)
            let roughness = mipCount > 1 ? Float(level) / Float(mipCount - 1) : 0

            encoder.setTexture(try arrayView(of: target, level: level), index: 1)
            var params = IBLBakeParams(
                size: UInt32(size), preset: 0,
                sampleCount: UInt32(prefilterSampleCount), roughness: roughness)
            encoder.setBytes(&params, length: MemoryLayout<IBLBakeParams>.stride, index: 0)
            dispatch(encoder, size: size)
            // 同じエンコーダー内で mip を順に埋めるので、段の間で書き込みを確定させる
            encoder.memoryBarrier(scope: .textures)
        }
        encoder.endEncoding()
    }

    // MARK: - Private Helpers

    /// キューブテクスチャの 1 mip を「6 スライスの 2D 配列」として見るビュー。
    ///
    /// compute から `texturecube` へ直接書く代わりに、`texture2d_array<access::write>`
    /// として書き込むための入り口。
    private static func arrayView(of texture: MTLTexture, level: Int) throws -> MTLTexture {
        guard let view = texture.makeTextureView(
            pixelFormat: texture.pixelFormat,
            textureType: .type2DArray,
            levels: level..<(level + 1),
            slices: 0..<6
        ) else {
            let size = max(texture.width >> level, 1)
            throw MetaphorError.textureCreationFailed(
                width: size, height: size, format: "ibl_cube_array_view")
        }
        return view
    }

    private static func dispatch(_ encoder: MTLComputeCommandEncoder, size: Int) {
        encoder.dispatchThreads(
            MTLSize(width: size, height: size, depth: 6),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    private static func makeCube(
        device: MTLDevice,
        size: Int,
        mipmapLevelCount: Int?,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float, size: size, mipmapped: mipmapLevelCount != 1)
        if let levels = mipmapLevelCount {
            descriptor.mipmapLevelCount = levels
        }
        // `.pixelFormatView` はキューブを 2D 配列として見るビュー（書き込み先）に要る
        descriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetaphorError.textureCreationFailed(width: size, height: size, format: "rgba16Float_cube")
        }
        texture.label = label
        return texture
    }

    private static func computePipeline(
        named name: String,
        device: MTLDevice,
        shaderLibrary: ShaderLibrary
    ) throws -> MTLComputePipelineState {
        guard let function = shaderLibrary.function(named: name, from: libraryKey) else {
            throw MetaphorError.shaderNotFound(name)
        }
        return try PipelineFactory.buildCompute(device: device, function: function)
    }

    /// IBL 無効時にバインドする 1x1 のダミーキューブ。
    ///
    /// 組み込み 3D フラグメントシェーダーはキューブを非オプショナルな引数として取るため、
    /// 環境が無くても何かをバインドしないと Metal のバリデーションで落ちる
    /// （``Canvas3D/dummyShadowTexture`` と同じ理由）。
    static func makeDummyCube(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float, size: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetaphorError.textureCreationFailed(width: 1, height: 1, format: "rgba16Float_cube")
        }
        texture.label = "IBL Dummy Cube"
        return texture
    }
}

// MARK: - Shader Types

/// `MetaphorIBL.metal` の `IBLBakeParams` と 1 対 1 で対応します。
struct IBLBakeParams {
    var size: UInt32
    var preset: UInt32
    var sampleCount: UInt32
    var roughness: Float
}

/// `MetaphorSkybox.metal` の `SkyboxUniforms` と 1 対 1 で対応します。
struct SkyboxUniforms {
    var inverseViewProjection: float4x4
    var cameraPosition: SIMD4<Float>
    /// x = 強度, y = トーンマップモード, z = 露出, w = 予約
    var params: SIMD4<Float>
}
