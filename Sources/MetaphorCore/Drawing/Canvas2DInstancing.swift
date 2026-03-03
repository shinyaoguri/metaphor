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

// MARK: - Instance Batcher

/// Automatic instancing batcher for Canvas2D.
///
/// Detects consecutive draws of the same shape type and blend mode,
/// accumulates per-instance data into a buffer, and issues a single
/// instanced draw call on flush.
@MainActor
final class InstanceBatcher2D {

    // MARK: - Constants

    /// Maximum number of instances per batch.
    static let maxInstancesPerBatch: Int = 16384
    /// Number of triple-buffered GPU buffers.
    static let bufferCount: Int = 3

    // MARK: - Batch Key

    /// Key that determines whether draws can be batched together.
    ///
    /// Color is per-instance data and not included in the key.
    struct BatchKey2D: Equatable {
        /// The shape type for this batch.
        let shapeType: Shape2DType
        /// The blend mode for this batch.
        let blendMode: BlendMode
    }

    // MARK: - GPU Buffers

    /// The Metal device used to create buffers.
    private let device: MTLDevice
    /// Triple-buffered instance data buffers.
    private let instanceBuffers: [MTLBuffer]
    /// Raw pointers into each instance buffer for fast writes.
    private let instancePointers: [UnsafeMutablePointer<InstanceData2D>]
    /// Index of the currently active buffer in the triple-buffer ring.
    private var currentBufferIndex: Int = 0

    // MARK: - Current Batch State

    /// The batch key for the current in-progress batch, or nil if no batch is active.
    private(set) var currentBatchKey: BatchKey2D?
    /// The number of instances accumulated in the current batch.
    private(set) var instanceCount: Int = 0

    // MARK: - Init

    /// Creates a new 2D instance batcher with triple-buffered GPU storage.
    init(device: MTLDevice) throws {
        self.device = device
        let stride = MemoryLayout<InstanceData2D>.stride
        let bufferSize = Self.maxInstancesPerBatch * stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<InstanceData2D>] = []
        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw MetaphorError.bufferCreationFailed(size: bufferSize)
            }
            buf.label = "metaphor.instance2D.\(i)"
            buffers.append(buf)
            pointers.append(buf.contents().bindMemory(to: InstanceData2D.self, capacity: Self.maxInstancesPerBatch))
        }
        self.instanceBuffers = buffers
        self.instancePointers = pointers
    }

    // MARK: - Frame Lifecycle

    /// Prepares the batcher for a new frame by selecting the buffer and resetting state.
    func beginFrame(bufferIndex: Int) {
        currentBufferIndex = bufferIndex % Self.bufferCount
        reset()
    }

    // MARK: - Instance Accumulation

    /// Tries to add an instance to the current batch.
    ///
    /// Returns `true` if the key matches the current batch and there is buffer space.
    /// Returns `false` if the key differs or the buffer is full (caller must flush first).
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

    /// The currently active instance data buffer.
    var currentBuffer: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// Resets the batch state for a new batch.
    func reset() {
        instanceCount = 0
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
