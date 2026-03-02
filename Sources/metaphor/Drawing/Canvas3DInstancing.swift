import Metal
import simd

// MARK: - Per-Instance GPU Data

/// Per-instance data for Canvas3D instanced drawing (160 bytes, 16-byte aligned).
///
/// The vertex shader indexes by `instance_id` to read each instance's transform and color.
struct InstanceData3D {
    /// The model transform matrix for this instance.
    var modelMatrix: float4x4       // 64 bytes
    /// The normal transform matrix for this instance.
    var normalMatrix: float4x4      // 64 bytes
    /// The tint color (RGBA) for this instance.
    var color: SIMD4<Float>         // 16 bytes
    /// Padding for 16-byte alignment.
    var _pad: SIMD4<Float> = .zero  // 16 bytes (alignment)
}

// MARK: - Scene Uniforms (per-batch, shared across instances)

/// Scene-wide uniforms shared across all instances in a batch (96 bytes).
///
/// Contains view/projection matrix, camera position, and light count.
struct InstancedSceneUniforms {
    /// The combined view-projection matrix.
    var viewProjectionMatrix: float4x4  // 64 bytes
    /// The camera position in world space.
    var cameraPosition: SIMD4<Float>    // 16 bytes
    /// The current frame time.
    var time: Float                      // 4 bytes
    /// The number of active lights.
    var lightCount: UInt32               // 4 bytes
    /// Whether the mesh has a texture bound.
    var hasTexture: UInt32 = 0           // 4 bytes
    /// Padding for alignment.
    var _pad2: UInt32 = 0                // 4 bytes
}

// MARK: - Instance Batcher

/// Automatic instancing batcher for Canvas3D.
///
/// Detects consecutive draws of the same mesh, material, and texture,
/// accumulates per-instance data into a buffer, and issues a single
/// instanced draw call on flush.
@MainActor
final class InstanceBatcher3D {

    // MARK: - Constants

    /// Maximum number of instances per batch.
    static let maxInstancesPerBatch: Int = 16384
    /// Number of triple-buffered GPU buffers.
    static let bufferCount: Int = 3

    // MARK: - Batch Key

    /// Key that determines whether draws can be batched together.
    ///
    /// All fields must match for consecutive draws to be batched.
    struct BatchKey: Equatable {
        /// Object identifier of the mesh.
        let meshID: ObjectIdentifier
        /// Whether the mesh uses texture coordinates.
        let isTextured: Bool
        /// Object identifier of the bound texture, if any.
        let textureID: ObjectIdentifier?
        /// The material properties for this batch.
        let material: Material3D
        /// Object identifier of a custom material, if any.
        let customMaterialID: ObjectIdentifier?
        /// Whether fill drawing is enabled.
        let hasFill: Bool
        /// Whether stroke (wireframe) drawing is enabled.
        let hasStroke: Bool
        /// The stroke color for wireframe rendering.
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

    /// The Metal device used to create buffers.
    private let device: MTLDevice
    /// Triple-buffered instance data buffers.
    private let instanceBuffers: [MTLBuffer]
    /// Raw pointers into each instance buffer for fast writes.
    private let instancePointers: [UnsafeMutablePointer<InstanceData3D>]
    /// Index of the currently active buffer in the triple-buffer ring.
    private var currentBufferIndex: Int = 0

    // MARK: - Current Batch State

    /// The batch key for the current in-progress batch, or nil if no batch is active.
    private(set) var currentBatchKey: BatchKey?
    /// The number of instances accumulated in the current batch.
    private(set) var instanceCount: Int = 0
    /// The mesh used in the current batch.
    private(set) var currentMesh: Mesh?
    /// The texture bound in the current batch.
    private(set) var currentTexture: MTLTexture?
    /// The material used in the current batch.
    private(set) var currentMaterial: Material3D = .default
    /// The custom material used in the current batch, if any.
    private(set) var currentCustomMaterial: CustomMaterial?
    /// Whether fill drawing is enabled in the current batch.
    private(set) var currentHasFill: Bool = true
    /// Whether stroke drawing is enabled in the current batch.
    private(set) var currentHasStroke: Bool = false
    /// The stroke color used in the current batch.
    private(set) var currentStrokeColor: SIMD4<Float> = .one

    // MARK: - Init

    /// Creates a new 3D instance batcher with triple-buffered GPU storage.
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
            // Start a new batch
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

    /// The currently active instance data buffer.
    var currentBuffer: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// Resets the batch state for a new batch.
    func reset() {
        instanceCount = 0
        currentBatchKey = nil
        currentMesh = nil
        currentTexture = nil
        currentCustomMaterial = nil
    }
}
