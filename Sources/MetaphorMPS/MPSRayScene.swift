@preconcurrency import Metal
import MetalPerformanceShaders
import MetaphorCore
import simd

/// メッシュからレイトレーシングシーンを構築します（内部ヘルパー）。
///
/// Mesh および DynamicMesh インスタンスから頂点位置を抽出し、
/// レイ交差判定用の MPSTriangleAccelerationStructure を構築します。
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

    // MARK: - メッシュ追加

    /// 頂点バッファから位置を抽出して Mesh を追加します。
    public func addMesh(_ mesh: Mesh, transform: float4x4 = matrix_identity_float4x4) {
        let stride = MemoryLayout<Vertex3D>.stride  // 48バイト
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
            // インデックスなし: 連番インデックスを生成
            indices = (0..<UInt32(mesh.vertexCount)).map { $0 }
        }

        entries.append(MeshEntry(positions: positions, indices: indices, transform: transform))
    }

    /// DynamicMesh をシーンに追加します。
    public func addDynamicMesh(_ mesh: DynamicMesh, transform: float4x4 = matrix_identity_float4x4) {
        var positions = [SIMD3<Float>]()
        let vCount = mesh.vertexCount
        positions.reserveCapacity(vCount)

        for i in 0..<vCount {
            positions.append(mesh.getVertex(i))
        }

        // DynamicMesh は UInt32 インデックスを使用
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

    /// シーンからすべてのメッシュエントリをクリアします。
    func clear() {
        entries.removeAll()
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - アクセラレーション構造の構築

    /// 追加されたすべてのメッシュエントリから MPSTriangleAccelerationStructure を構築します。
    /// - Throws: シーンが空または GPU バッファ作成に失敗した場合に ``MetaphorError`` をスローします。
    /// - Returns: アクセラレーション構造、頂点バッファ、インデックスバッファ、法線バッファ、三角形数を含むタプル。
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

        // すべてのエントリを統一された頂点・インデックス配列にフラット化
        var allPositions = [SIMD3<Float>]()
        var allIndices = [UInt32]()
        var allNormals = [SIMD3<Float>]()

        for entry in entries {
            let baseVertex = UInt32(allPositions.count)

            // 位置にトランスフォームを適用
            for pos in entry.positions {
                let transformed = entry.transform * SIMD4<Float>(pos, 1.0)
                allPositions.append(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
            }

            // インデックスをオフセット
            for idx in entry.indices {
                allIndices.append(idx + baseVertex)
            }
        }

        // 三角形ごとの面法線を計算
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

        // GPU バッファを作成
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

        // アクセラレーション構造を構築
        let accel = MPSTriangleAccelerationStructure(device: device)
        accel.vertexBuffer = vertexBuffer
        accel.vertexStride = MemoryLayout<SIMD3<Float>>.stride  // 16バイト
        accel.indexBuffer = indexBuffer
        accel.indexType = .uInt32
        accel.triangleCount = triangleCount
        accel.rebuild()

        return (accel, vertexBuffer, indexBuffer, normalBuffer, triangleCount)
    }
}
