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

// MARK: - Batch Key

/// Key that determines whether 3D draws can be batched together.
///
/// All fields must match for consecutive draws to be batched.
struct BatchKey3D: Equatable {
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

/// Automatic instancing batcher for Canvas3D.
///
/// Wraps `InstanceBatcher<InstanceData3D>` with batch key and per-batch state tracking.
@MainActor
final class InstanceBatcher3D {
    private let batcher: InstanceBatcher<InstanceData3D>

    /// The batch key for the current in-progress batch, or nil if no batch is active.
    private(set) var currentBatchKey: BatchKey3D?

    /// The number of instances accumulated in the current batch.
    var instanceCount: Int { batcher.instanceCount }

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
