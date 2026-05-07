@preconcurrency import Metal
import MetaphorCore
import simd

/// メッシュからレイトレーシングシーンを構築します（内部ヘルパー）。
///
/// Mesh および DynamicMesh インスタンスから頂点位置を抽出し、
/// レイ交差判定用の MTLAccelerationStructure を構築します。
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

    /// 追加されたすべてのメッシュエントリから MTLAccelerationStructure を構築します。
    /// - Parameter commandQueue: ビルドコマンドのエンコードに使用するコマンドキュー。
    /// - Throws: シーンが空または GPU バッファ作成に失敗した場合に ``MetaphorError`` をスローします。
    /// - Returns: アクセラレーション構造、法線バッファ、三角形数を含むタプル。
    func buildAccelerationStructure(commandQueue: MTLCommandQueue) throws -> (
        accelerationStructure: MTLAccelerationStructure,
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

        // 退化三角形を BVH 構築前に除外しつつ、有効な三角形だけのインデックスと
        // 法線バッファを構築する。インデックス範囲外の三角形は明示的にスローし、
        // 退化（面積≈0）はサイレントにスキップしてデバッグログのみ残す。
        // これにより無駄なレイ-三角形交差テストが消え、退化面に対する
        // 不定な交差結果も発生しなくなる。
        let inputTriangleCount = allIndices.count / 3
        let vertexCount = allPositions.count
        let degenerateEpsilon: Float = 1e-12  // cross product 長さ平方の閾値
        var validIndices = [UInt32]()
        validIndices.reserveCapacity(allIndices.count)
        allNormals.reserveCapacity(inputTriangleCount)
        var droppedTriangleCount = 0

        for t in 0..<inputTriangleCount {
            let raw0 = allIndices[t * 3]
            let raw1 = allIndices[t * 3 + 1]
            let raw2 = allIndices[t * 3 + 2]
            let i0 = Int(raw0)
            let i1 = Int(raw1)
            let i2 = Int(raw2)
            guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else {
                throw MetaphorError.mps(.invalidScene(
                    "Triangle \(t) references out-of-range vertex (max=\(vertexCount - 1))"
                ))
            }
            let v0 = allPositions[i0]
            let v1 = allPositions[i1]
            let v2 = allPositions[i2]
            let crossVec = cross(v1 - v0, v2 - v0)
            let lenSq = length_squared(crossVec)
            guard lenSq > degenerateEpsilon else {
                droppedTriangleCount += 1
                continue
            }
            validIndices.append(raw0)
            validIndices.append(raw1)
            validIndices.append(raw2)
            allNormals.append(crossVec / sqrt(lenSq))
        }

        guard !validIndices.isEmpty else {
            throw MetaphorError.mps(.invalidScene(
                "All \(inputTriangleCount) triangles are degenerate"
            ))
        }

        if droppedTriangleCount > 0 {
            print("[metaphor.MPSRayScene] Dropped \(droppedTriangleCount) degenerate triangle(s) of \(inputTriangleCount)")
        }

        // BVH 用にコンパクト化されたインデックス配列で置換
        allIndices = validIndices
        let triangleCount = allIndices.count / 3

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

        // Metal ネイティブアクセラレーション構造を構築
        let geometryDesc = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometryDesc.vertexBuffer = vertexBuffer
        geometryDesc.vertexStride = MemoryLayout<SIMD3<Float>>.stride  // 16バイト
        geometryDesc.vertexFormat = .float3
        geometryDesc.indexBuffer = indexBuffer
        geometryDesc.indexType = .uint32
        geometryDesc.triangleCount = triangleCount

        let accelDesc = MTLPrimitiveAccelerationStructureDescriptor()
        accelDesc.geometryDescriptors = [geometryDesc]

        let sizes = device.accelerationStructureSizes(descriptor: accelDesc)

        guard let accelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize) else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create acceleration structure"))
        }

        guard let scratchBuffer = device.makeBuffer(
            length: sizes.buildScratchBufferSize,
            options: .storageModePrivate
        ) else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create scratch buffer"))
        }

        guard let cb = commandQueue.makeCommandBuffer() else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create command buffer"))
        }

        guard let encoder = cb.makeAccelerationStructureCommandEncoder() else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to create acceleration structure command encoder"))
        }
        encoder.build(
            accelerationStructure: accelerationStructure,
            descriptor: accelDesc,
            scratchBuffer: scratchBuffer,
            scratchBufferOffset: 0
        )
        encoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        return (accelerationStructure, normalBuffer, triangleCount)
    }
}
