import Metal
import simd

// MARK: - Per-Instance GPU Data

/// Canvas3D インスタンシング用 per-instance データ（160 bytes, 16-byte aligned）
///
/// vertex shader が instance_id でインデックスし、
/// 各インスタンスの transform と color を読み取る。
struct InstanceData3D {
    var modelMatrix: float4x4       // 64 bytes
    var normalMatrix: float4x4      // 64 bytes
    var color: SIMD4<Float>         // 16 bytes
    var _pad: SIMD4<Float> = .zero  // 16 bytes (alignment)
}

// MARK: - Scene Uniforms (per-batch, shared across instances)

/// インスタンシング描画のシーン共通ユニフォーム（96 bytes）
///
/// 全インスタンスで共有される view/projection、カメラ、ライト数を保持する。
struct InstancedSceneUniforms {
    var viewProjectionMatrix: float4x4  // 64 bytes
    var cameraPosition: SIMD4<Float>    // 16 bytes
    var time: Float                      // 4 bytes
    var lightCount: UInt32               // 4 bytes
    var hasTexture: UInt32 = 0           // 4 bytes
    var _pad2: UInt32 = 0                // 4 bytes
}

// MARK: - Instance Batcher

/// Canvas3D の自動インスタンシングバッチャー
///
/// 同一メッシュ＋同一マテリアル＋同一テクスチャの連続描画を検出し、
/// per-instance データをバッファに蓄積する。
/// flush 時に1回の instanced draw call で一括描画する。
@MainActor
final class InstanceBatcher3D {

    // MARK: - Constants

    static let maxInstancesPerBatch: Int = 16384
    static let bufferCount: Int = 3

    // MARK: - Batch Key

    /// バッチング可否を判定するキー
    ///
    /// 全フィールドが一致する連続描画のみバッチされる。
    struct BatchKey: Equatable {
        let meshID: ObjectIdentifier
        let isTextured: Bool
        let textureID: ObjectIdentifier?
        let material: Material3D
        let customMaterialID: ObjectIdentifier?
        let hasFill: Bool
        let hasStroke: Bool
        let strokeColor: SIMD4<Float>

        static func == (lhs: BatchKey, rhs: BatchKey) -> Bool {
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

    // MARK: - GPU Buffers

    private let device: MTLDevice
    private let instanceBuffers: [MTLBuffer]
    private let instancePointers: [UnsafeMutablePointer<InstanceData3D>]
    private var currentBufferIndex: Int = 0

    // MARK: - Current Batch State

    private(set) var currentBatchKey: BatchKey?
    private(set) var instanceCount: Int = 0
    private(set) var currentMesh: Mesh?
    private(set) var currentTexture: MTLTexture?
    private(set) var currentMaterial: Material3D = .default
    private(set) var currentCustomMaterial: CustomMaterial?
    private(set) var currentHasFill: Bool = true
    private(set) var currentHasStroke: Bool = false
    private(set) var currentStrokeColor: SIMD4<Float> = .one

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device
        let stride = MemoryLayout<InstanceData3D>.stride
        let bufferSize = Self.maxInstancesPerBatch * stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<InstanceData3D>] = []
        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                fatalError("Failed to create instance buffer \(i)")
            }
            buf.label = "metaphor.instance3D.\(i)"
            buffers.append(buf)
            pointers.append(buf.contents().bindMemory(to: InstanceData3D.self, capacity: Self.maxInstancesPerBatch))
        }
        self.instanceBuffers = buffers
        self.instancePointers = pointers
    }

    // MARK: - Frame Lifecycle

    func beginFrame(bufferIndex: Int) {
        currentBufferIndex = bufferIndex % Self.bufferCount
        reset()
    }

    // MARK: - Instance Accumulation

    /// インスタンスをバッチに追加する。
    ///
    /// key が現在のバッチと一致し、バッファに空きがあれば追加して true を返す。
    /// key 不一致またはバッファ満杯の場合は false を返す（呼び出し側で flush が必要）。
    func tryAddInstance(
        key: BatchKey,
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
        if let currentKey = currentBatchKey {
            if currentKey != key || instanceCount >= Self.maxInstancesPerBatch {
                return false
            }
        } else {
            // 新しいバッチを開始
            currentBatchKey = key
            currentMesh = mesh
            currentTexture = texture
            currentMaterial = material
            currentCustomMaterial = customMaterial
            currentHasFill = hasFill
            currentHasStroke = hasStroke
            currentStrokeColor = strokeColor
        }

        instancePointers[currentBufferIndex][instanceCount] = InstanceData3D(
            modelMatrix: transform,
            normalMatrix: normalMatrix,
            color: color
        )
        instanceCount += 1
        return true
    }

    /// 現在のインスタンスバッファ
    var currentBuffer: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// バッチをリセット
    func reset() {
        instanceCount = 0
        currentBatchKey = nil
        currentMesh = nil
        currentTexture = nil
        currentCustomMaterial = nil
    }
}
