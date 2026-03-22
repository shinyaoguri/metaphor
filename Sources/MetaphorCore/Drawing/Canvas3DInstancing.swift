import Metal
import simd

// MARK: - Per-Instance GPU Data

/// Canvas3D インスタンス描画用のインスタンスごとのデータ（160バイト、16バイトアライメント）。
///
/// 頂点シェーダーが `instance_id` でインデックスし、各インスタンスのトランスフォームと色を読み取ります。
struct InstanceData3D {
    /// このインスタンスのモデル変換行列。
    var modelMatrix: float4x4       // 64 bytes
    /// このインスタンスの法線変換行列。
    var normalMatrix: float4x4      // 64 bytes
    /// このインスタンスのティント色（RGBA）。
    var color: SIMD4<Float>         // 16 bytes
    /// 16バイトアライメント用パディング。
    var _pad: SIMD4<Float> = .zero  // 16 bytes (alignment)
}

// MARK: - Scene Uniforms (per-batch, shared across instances)

/// バッチ内の全インスタンスで共有されるシーン全体のユニフォーム（96バイト）。
///
/// ビュー/プロジェクション行列、カメラ位置、ライト数を含みます。
struct InstancedSceneUniforms {
    /// 結合されたビュー・プロジェクション行列。
    var viewProjectionMatrix: float4x4  // 64 bytes
    /// ワールド空間でのカメラ位置。
    var cameraPosition: SIMD4<Float>    // 16 bytes
    /// 現在のフレーム時間。
    var time: Float                      // 4 bytes
    /// アクティブなライトの数。
    var lightCount: UInt32               // 4 bytes
    /// メッシュにテクスチャがバインドされているかどうか。
    var hasTexture: UInt32 = 0           // 4 bytes
    /// アライメント用パディング。
    var _pad2: UInt32 = 0                // 4 bytes
}

// MARK: - Batch Key

/// 3D描画をバッチ化できるかどうかを決定するキー。
///
/// 連続する描画がバッチ化されるには、すべてのフィールドが一致する必要があります。
struct BatchKey3D: Equatable {
    /// メッシュのオブジェクト識別子。
    let meshID: ObjectIdentifier
    /// メッシュがテクスチャ座標を使用するかどうか。
    let isTextured: Bool
    /// バインドされたテクスチャのオブジェクト識別子（存在する場合）。
    let textureID: ObjectIdentifier?
    /// このバッチのマテリアルプロパティ。
    let material: Material3D
    /// カスタムマテリアルのオブジェクト識別子（存在する場合）。
    let customMaterialID: ObjectIdentifier?
    /// 塗りつぶし描画が有効かどうか。
    let hasFill: Bool
    /// ストローク（ワイヤーフレーム）描画が有効かどうか。
    let hasStroke: Bool
    /// ワイヤーフレームレンダリングのストローク色。
    let strokeColor: SIMD4<Float>

    static func == (lhs: BatchKey3D, rhs: BatchKey3D) -> Bool {
        lhs.meshID == rhs.meshID
        && lhs.isTextured == rhs.isTextured
        && lhs.textureID == rhs.textureID
        && lhs.hasFill == rhs.hasFill
        && lhs.hasStroke == rhs.hasStroke
        && lhs.strokeColor == rhs.strokeColor
        && lhs.customMaterialID == rhs.customMaterialID
        && lhs.material.ambientColor == rhs.material.ambientColor
        && lhs.material.specularAndShininess == rhs.material.specularAndShininess
        && lhs.material.emissiveAndMetallic == rhs.material.emissiveAndMetallic
        && lhs.material.pbrParams == rhs.material.pbrParams
    }
}

// MARK: - 3D Instance Batcher (thin wrapper over generic InstanceBatcher)

/// Canvas3D の自動インスタンシングバッチャー。
///
/// `InstanceBatcher<InstanceData3D>` をバッチキーとバッチごとの状態トラッキング付きでラップします。
@MainActor
final class InstanceBatcher3D {
    private let batcher: InstanceBatcher<InstanceData3D>

    /// 進行中のバッチのバッチキー。バッチがアクティブでない場合は nil。
    private(set) var currentBatchKey: BatchKey3D?

    /// 現在のバッチに蓄積されたインスタンス数。
    var instanceCount: Int { batcher.instanceCount }

    /// 現在のバッチで使用されるメッシュ。
    private(set) var currentMesh: Mesh?
    /// 現在のバッチでバインドされたテクスチャ。
    private(set) var currentTexture: MTLTexture?
    /// 現在のバッチで使用されるマテリアル。
    private(set) var currentMaterial: Material3D = .default
    /// 現在のバッチで使用されるカスタムマテリアル（存在する場合）。
    private(set) var currentCustomMaterial: CustomMaterial?
    /// 現在のバッチで塗りつぶし描画が有効かどうか。
    private(set) var currentHasFill: Bool = true
    /// 現在のバッチでストローク描画が有効かどうか。
    private(set) var currentHasStroke: Bool = false
    /// 現在のバッチで使用されるストローク色。
    private(set) var currentStrokeColor: SIMD4<Float> = .one

    init(device: MTLDevice) throws {
        self.batcher = try InstanceBatcher<InstanceData3D>(
            device: device, maxInstances: 65536, label: "metaphor.instance3D"
        )
    }

    func beginFrame(bufferIndex: Int) {
        batcher.beginFrame(bufferIndex: bufferIndex)
        currentBatchKey = nil
        currentMesh = nil
        currentTexture = nil
        currentCustomMaterial = nil
    }

    func tryAddInstance(
        key: BatchKey3D,
        mesh: Mesh,
        texture: MTLTexture?,
        material: Material3D,
        customMaterial: CustomMaterial?,
        hasFill: Bool,
        hasStroke: Bool,
        strokeColor: SIMD4<Float>,
        transform: float4x4,
        normalMatrix: float4x4,
        color: SIMD4<Float>
    ) -> Bool {
        guard batcher.canAdd else { return false }

        if let currentKey = currentBatchKey {
            if currentKey != key { return false }
        } else {
            currentBatchKey = key
            currentMesh = mesh
            currentTexture = texture
            currentMaterial = material
            currentCustomMaterial = customMaterial
            currentHasFill = hasFill
            currentHasStroke = hasStroke
            currentStrokeColor = strokeColor
        }

        batcher.addInstance(InstanceData3D(
            modelMatrix: transform,
            normalMatrix: normalMatrix,
            color: color
        ))
        return true
    }

    var currentBuffer: MTLBuffer { batcher.currentBuffer }
    var currentBufferOffset: Int { batcher.currentBufferOffset }

    func reset() {
        batcher.advanceBatch()
        currentBatchKey = nil
        currentMesh = nil
        currentTexture = nil
        currentCustomMaterial = nil
    }
}
