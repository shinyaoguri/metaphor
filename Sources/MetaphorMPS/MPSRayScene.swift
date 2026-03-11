@preconcurrency import Metal
import MetalPerformanceShaders
import MetaphorCore
import simd

/// Build ray tracing scenes from meshes (internal helper).
///
/// Extract vertex positions from Mesh and DynamicMesh instances and
/// construct an MPSTriangleAccelerationStructure for ray intersection.
@available(macOS, deprecated: 14.0, message: "MPSTriangleAccelerationStructure is deprecated; migrate to Metal ray tracing APIs")
@MainActor
final class MPSRayScene {

    struct MeshEntry {
        var positions: [SIMD3<Float>]
        var indices: [UInt32]
        var transform: float4x4
    }

    private let device: MTLDevice
    private var entries: [MeshEntry] = []

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Add Mesh

    /// Add a Mesh by extracting positions from its vertex buffer.
    public func addMesh(_ mesh: Mesh, transform: float4x4 = matrix_identity_float4x4) {
        let stride = MemoryLayout<Vertex3D>.stride  // 48 bytes
        let ptr = mesh.vertexBuffer.contents()
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(mesh.vertexCount)

        for i in 0..<mesh.vertexCount {
            let vertex = ptr.advanced(by: i * stride).assumingMemoryBound(to: Vertex3D.self).pointee
            positions.append(vertex.position)
        }

        var indices = [UInt32]()
        if let ib = mesh.indexBuffer {
            let count = mesh.indexCount
            indices.reserveCapacity(count)
            switch mesh.indexType {
            case .uint16:
                let p = ib.contents().assumingMemoryBound(to: UInt16.self)
                for i in 0..<count { indices.append(UInt32(p[i])) }
            case .uint32:
                let p = ib.contents().assumingMemoryBound(to: UInt32.self)
                for i in 0..<count { indices.append(p[i]) }
            @unknown default:
                break
            }
        } else {
            // Non-indexed: generate sequential indices
            indices = (0..<UInt32(mesh.vertexCount)).map { $0 }
        }

        entries.append(MeshEntry(positions: positions, indices: indices, transform: transform))
    }

    /// Add a DynamicMesh to the scene.
    public func addDynamicMesh(_ mesh: DynamicMesh, transform: float4x4 = matrix_identity_float4x4) {
        var positions = [SIMD3<Float>]()
        let vCount = mesh.vertexCount
        positions.reserveCapacity(vCount)

        for i in 0..<vCount {
            positions.append(mesh.getVertex(i))
        }

        // DynamicMesh uses UInt32 indices
        var indices = [UInt32]()
        if let ib = mesh.indexBuffer {
            let count = mesh.indexCount
            indices.reserveCapacity(count)
            let p = ib.contents().assumingMemoryBound(to: UInt32.self)
            for i in 0..<count { indices.append(p[i]) }
        } else {
            indices = (0..<UInt32(vCount)).map { $0 }
        }

        entries.append(MeshEntry(positions: positions, indices: indices, transform: transform))
    }

    /// Clear all mesh entries from the scene.
    func clear() {
        entries.removeAll()
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Build Acceleration Structure

    /// Build an MPSTriangleAccelerationStructure from all added mesh entries.
    /// - Throws: ``MetaphorError`` if the scene is empty or GPU buffer creation fails.
    /// - Returns: A tuple containing the acceleration structure, vertex buffer, index buffer, normal buffer, and triangle count.
    func buildAccelerationStructure() throws -> (
        accelerationStructure: MPSTriangleAccelerationStructure,
        vertexBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        triangleCount: Int
    ) {
        guard !entries.isEmpty else {
            throw MetaphorError.mps(.invalidScene("No meshes added to scene"))
        }

        // Flatten all entries into unified vertex/index arrays
        var allPositions = [SIMD3<Float>]()
        var allIndices = [UInt32]()
        var allNormals = [SIMD3<Float>]()

        for entry in entries {
            let baseVertex = UInt32(allPositions.count)

            // Apply transform to positions
            for pos in entry.positions {
                let transformed = entry.transform * SIMD4<Float>(pos, 1.0)
                allPositions.append(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
            }

            // Offset indices
            for idx in entry.indices {
                allIndices.append(idx + baseVertex)
            }
        }

        // Compute per-triangle face normals
        let triangleCount = allIndices.count / 3
        allNormals.reserveCapacity(triangleCount)
        for t in 0..<triangleCount {
            let i0 = Int(allIndices[t * 3])
            let i1 = Int(allIndices[t * 3 + 1])
            let i2 = Int(allIndices[t * 3 + 2])
            let v0 = allPositions[i0]
            let v1 = allPositions[i1]
            let v2 = allPositions[i2]
            let n = normalize(cross(v1 - v0, v2 - v0))
            allNormals.append(n)
        }

        // Create GPU buffers
        guard let vertexBuffer = device.makeBuffer(
            bytes: allPositions,
            length: allPositions.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create vertex buffer"))
        }

        guard let indexBuffer = device.makeBuffer(
            bytes: allIndices,
            length: allIndices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create index buffer"))
        }

        guard let normalBuffer = device.makeBuffer(
            bytes: allNormals,
            length: allNormals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create normal buffer"))
        }

        // Build acceleration structure
        let accel = MPSTriangleAccelerationStructure(device: device)
        accel.vertexBuffer = vertexBuffer
        accel.vertexStride = MemoryLayout<SIMD3<Float>>.stride  // 16 bytes
        accel.indexBuffer = indexBuffer
        accel.indexType = .uInt32
        accel.triangleCount = triangleCount
        accel.rebuild()

        return (accel, vertexBuffer, indexBuffer, normalBuffer, triangleCount)
    }
}
