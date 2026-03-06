import Metal
import simd

// MARK: - Shape Type

/// Shape type for 2D instanced drawing.
enum Shape2DType: UInt8, Hashable {
    /// Ellipse / circle shape.
    case ellipse
    /// Rectangle / square shape.
    case rect
}

// MARK: - Per-Instance GPU Data

/// Per-instance data for Canvas2D instanced drawing (80 bytes, 16-byte aligned).
///
/// The vertex shader indexes by `instance_id` to read each instance's transform and color.
/// The 2D affine transform from `float3x3` is embedded in a `float4x4` (same pattern as 3D).
struct InstanceData2D {
    /// 2D affine transform embedded in a 4x4 matrix (currentTransform * shapeLocal).
    var transform: float4x4       // 64 bytes
    /// Fill color (RGBA).
    var color: SIMD4<Float>       // 16 bytes
}

// MARK: - Batch Key

/// Key that determines whether 2D draws can be batched together.
///
/// Color is per-instance data and not included in the key.
struct BatchKey2D: Equatable {
    /// The shape type for this batch.
    let shapeType: Shape2DType
    /// The blend mode for this batch.
    let blendMode: BlendMode
}

// MARK: - 2D Instance Batcher (thin wrapper over generic InstanceBatcher)

/// Automatic instancing batcher for Canvas2D.
///
/// Wraps `InstanceBatcher<InstanceData2D>` with batch key tracking.
@MainActor
final class InstanceBatcher2D {
    private let batcher: InstanceBatcher<InstanceData2D>

    /// The batch key for the current in-progress batch, or nil if no batch is active.
    private(set) var currentBatchKey: BatchKey2D?

    /// The number of instances accumulated in the current batch.
    var instanceCount: Int { batcher.instanceCount }

    init(device: MTLDevice) throws {
        self.batcher = try InstanceBatcher<InstanceData2D>(
            device: device, maxInstances: 65536, label: "metaphor.instance2D"
        )
    }

    func beginFrame(bufferIndex: Int) {
        batcher.beginFrame(bufferIndex: bufferIndex)
        currentBatchKey = nil
    }

    func tryAddInstance(
        key: BatchKey2D,
        transform: float4x4,
        color: SIMD4<Float>
    ) -> Bool {
        guard batcher.canAdd else { return false }

        if let currentKey = currentBatchKey {
            if currentKey != key { return false }
        } else {
            currentBatchKey = key
        }

        batcher.addInstance(InstanceData2D(transform: transform, color: color))
        return true
    }

    var currentBuffer: MTLBuffer { batcher.currentBuffer }
    var currentBufferOffset: Int { batcher.currentBufferOffset }

    func reset() {
        batcher.advanceBatch()
        currentBatchKey = nil
    }
}

// MARK: - Unit Mesh Creation

/// Factory for shared unit meshes created once at initialization.
enum UnitMesh2D {

    /// Creates a unit circle mesh: 32-segment triangle fan, radius 0.5, centered at origin.
    /// - Returns: A tuple of (MTLBuffer, vertex count), or nil if buffer creation fails.
    static func createCircle(device: MTLDevice, segments: Int = 32) -> (MTLBuffer, Int)? {
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
        guard let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else { return nil }
        buf.label = "metaphor.unitCircle"
        return (buf, verts.count)
    }

    /// Creates a unit rectangle mesh: 2 triangles, from [-0.5, -0.5] to [0.5, 0.5].
    /// - Returns: A tuple of (MTLBuffer, vertex count), or nil if buffer creation fails.
    static func createRect(device: MTLDevice) -> (MTLBuffer, Int)? {
        let verts: [SIMD2<Float>] = [
            SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5), SIMD2(0.5, 0.5),
            SIMD2(-0.5, -0.5), SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5),
        ]
        guard let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else { return nil }
        buf.label = "metaphor.unitRect"
        return (buf, verts.count)
    }
}

// MARK: - Transform Helper

extension Canvas2D {

    /// Embeds a 2D affine transform (float3x3) into a float4x4.
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
