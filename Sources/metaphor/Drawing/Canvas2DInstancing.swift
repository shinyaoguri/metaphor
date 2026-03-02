import Metal
import simd

// MARK: - Shape Type

/// 2Dインスタンシング対象の形状種別
enum Shape2DType: UInt8, Hashable {
    case ellipse
    case rect
}

// MARK: - Per-Instance GPU Data

/// Canvas2D インスタンシング用 per-instance データ（80 bytes, 16-byte aligned）
///
/// vertex shader が instance_id でインデックスし、
/// 各インスタンスの transform と color を読み取る。
/// float3x3 の 2D affine 変換を float4x4 に埋め込む（3D側と同じパターン）。
struct InstanceData2D {
    var transform: float4x4       // 64 bytes — currentTransform * shapeLocal
    var color: SIMD4<Float>       // 16 bytes — fillColor
}

// MARK: - Instance Batcher

/// Canvas2D の自動インスタンシングバッチャー
///
/// 同一形状＋同一ブレンドモードの連続描画を検出し、
/// per-instance データをバッファに蓄積する。
/// flush 時に1回の instanced draw call で一括描画する。
@MainActor
final class InstanceBatcher2D {

    // MARK: - Constants

    static let maxInstancesPerBatch: Int = 16384
    static let bufferCount: Int = 3

    // MARK: - Batch Key

    /// バッチング可否を判定するキー
    ///
    /// 色は per-instance データなのでキーに含めない。
    struct BatchKey2D: Equatable {
        let shapeType: Shape2DType
        let blendMode: BlendMode
    }

    // MARK: - GPU Buffers

    private let device: MTLDevice
    private let instanceBuffers: [MTLBuffer]
    private let instancePointers: [UnsafeMutablePointer<InstanceData2D>]
    private var currentBufferIndex: Int = 0

    // MARK: - Current Batch State

    private(set) var currentBatchKey: BatchKey2D?
    private(set) var instanceCount: Int = 0

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device
        let stride = MemoryLayout<InstanceData2D>.stride
        let bufferSize = Self.maxInstancesPerBatch * stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<InstanceData2D>] = []
        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                fatalError("Failed to create 2D instance buffer \(i)")
            }
            buf.label = "metaphor.instance2D.\(i)"
            buffers.append(buf)
            pointers.append(buf.contents().bindMemory(to: InstanceData2D.self, capacity: Self.maxInstancesPerBatch))
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
        key: BatchKey2D,
        transform: float4x4,
        color: SIMD4<Float>
    ) -> Bool {
        if let currentKey = currentBatchKey {
            if currentKey != key || instanceCount >= Self.maxInstancesPerBatch {
                return false
            }
        } else {
            currentBatchKey = key
        }

        instancePointers[currentBufferIndex][instanceCount] = InstanceData2D(
            transform: transform,
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
    }
}

// MARK: - Unit Mesh Creation

/// init時に1回だけ生成する共有ユニットメッシュ
enum UnitMesh2D {

    /// ユニット円: 32セグメント triangle fan, radius 0.5, 中心原点
    /// 返り値: (MTLBuffer, 頂点数)
    static func createCircle(device: MTLDevice, segments: Int = 32) -> (MTLBuffer, Int) {
        var verts: [SIMD2<Float>] = []
        verts.reserveCapacity(segments * 3)
        let step = Float.pi * 2.0 / Float(segments)
        for i in 0..<segments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            verts.append(SIMD2(0, 0))
            verts.append(SIMD2(0.5 * cos(a0), 0.5 * sin(a0)))
            verts.append(SIMD2(0.5 * cos(a1), 0.5 * sin(a1)))
        }
        let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )!
        buf.label = "metaphor.unitCircle"
        return (buf, verts.count)
    }

    /// ユニット矩形: 2三角形, [-0.5, -0.5] to [0.5, 0.5]
    /// 返り値: (MTLBuffer, 頂点数)
    static func createRect(device: MTLDevice) -> (MTLBuffer, Int) {
        let verts: [SIMD2<Float>] = [
            SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5), SIMD2(0.5, 0.5),
            SIMD2(-0.5, -0.5), SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5),
        ]
        let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )!
        buf.label = "metaphor.unitRect"
        return (buf, verts.count)
    }
}

// MARK: - Transform Helper

extension Canvas2D {

    /// float3x3 の 2D affine 変換を float4x4 に埋め込む
    ///
    /// ```
    /// | m00  m01  0  0 |
    /// | m10  m11  0  0 |
    /// |  0    0   1  0 |
    /// | m20  m21  0  1 |
    /// ```
    static func embed2DTransform(_ t: float3x3) -> float4x4 {
        float4x4(columns: (
            SIMD4<Float>(t.columns.0.x, t.columns.0.y, 0, 0),
            SIMD4<Float>(t.columns.1.x, t.columns.1.y, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.columns.2.x, t.columns.2.y, 0, 1)
        ))
    }
}
