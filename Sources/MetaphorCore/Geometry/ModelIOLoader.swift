import Metal
import ModelIO
import MetalKit
import simd

/// Model I/O フレームワークを使用して3Dモデルファイルを読み込みます。
///
/// MDLAsset を介して OBJ、USDZ、ABC などのフォーマットを読み込み、
/// metaphor の Mesh フォーマットに変換します。
@MainActor
enum ModelIOLoader {

    /// モデルファイルを読み込んで Mesh に変換します。
    /// - Parameters:
    ///   - device: GPU バッファを作成する Metal デバイス。
    ///   - url: モデルファイルのURL。
    ///   - normalize: true の場合、バウンディングボックスを [-1, 1] に正規化します。
    /// - Returns: 読み込まれたモデルデータを含む Mesh インスタンス。
    static func load(device: MTLDevice, url: URL, normalize: Bool) throws -> Mesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)

        guard let mdlMesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh else {
            throw MetaphorError.mesh(.parseError("No mesh found in \(url.lastPathComponent)"))
        }

        // 法線が存在しない場合は自動生成
        if !hasNormals(mdlMesh) {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }

        // 頂点属性データを読み取り
        let positionAttr = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition)
        let normalAttr = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal)
        let uvAttr = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate)

        guard let posData = positionAttr else {
            throw MetaphorError.mesh(.parseError("No position data in mesh"))
        }

        let vertexCount = mdlMesh.vertexCount
        let hasUVData = uvAttr != nil

        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        vertices.reserveCapacity(vertexCount)
        if hasUVData { uvVertices.reserveCapacity(vertexCount) }

        let white = SIMD4<Float>(1, 1, 1, 1)

        for i in 0..<vertexCount {
            let pos = readFloat3(from: posData, index: i)
            let norm = normalAttr.map { readFloat3(from: $0, index: i) } ?? SIMD3<Float>(0, 1, 0)
            let uv = uvAttr.map { readFloat2(from: $0, index: i) } ?? SIMD2<Float>(0, 0)

            vertices.append(Vertex3D(position: pos, normal: norm, color: white))
            if hasUVData {
                uvVertices.append(Vertex3DTextured(position: pos, normal: norm, uv: uv))
            }
        }

        // インデックスデータを読み取り
        var allIndices: [UInt32] = []
        for submesh in mdlMesh.submeshes as? [MDLSubmesh] ?? [] {
            let indexBuffer = submesh.indexBuffer
            let indexCount = submesh.indexCount
            let bytesPerIndex = submesh.indexType == .uint16 ? 2 : 4

            let ptr = indexBuffer.map().bytes
            for j in 0..<indexCount {
                let offset = j * bytesPerIndex
                if submesh.indexType == .uint16 {
                    let val = ptr.load(fromByteOffset: offset, as: UInt16.self)
                    allIndices.append(UInt32(val))
                } else {
                    let val = ptr.load(fromByteOffset: offset, as: UInt32.self)
                    allIndices.append(val)
                }
            }
        }

        guard !vertices.isEmpty else {
            throw MetaphorError.mesh(.parseError("Empty mesh"))
        }

        // バウンディングボックスを [-1, 1] に正規化
        if normalize {
            if hasUVData {
                normalizeVertices(&vertices, uvVertices: &uvVertices)
            } else {
                normalizeVerticesOnly(&vertices)
            }
        }

        // Mesh を作成
        if vertices.count <= 65535 && allIndices.allSatisfy({ $0 <= 65535 }) {
            let indices16 = allIndices.map { UInt16($0) }
            return try Mesh(
                device: device,
                vertices: vertices,
                indices: indices16.isEmpty ? nil : indices16,
                uvVertices: hasUVData ? uvVertices : nil
            )
        } else {
            return try Mesh(
                device: device,
                vertices: vertices,
                indices32: allIndices,
                uvVertices: hasUVData ? uvVertices : nil
            )
        }
    }

    // MARK: - Private Helpers

    private static func hasNormals(_ mesh: MDLMesh) -> Bool {
        let layout = mesh.vertexDescriptor
        for case let attr as MDLVertexAttribute in layout.attributes {
            if attr.name == MDLVertexAttributeNormal { return true }
        }
        return false
    }

    private static func halfToFloat(_ h: UInt16) -> Float {
        return Float(Float16(bitPattern: h))
    }

    private static func readFloat3(from data: MDLVertexAttributeData, index: Int) -> SIMD3<Float> {
        let stride = data.stride
        let offset = index * stride
        let ptr = data.dataStart.advanced(by: offset)

        switch data.format {
        case .float3:
            return ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        case .float4:
            let v4 = ptr.assumingMemoryBound(to: SIMD4<Float>.self).pointee
            return SIMD3(v4.x, v4.y, v4.z)
        case .half3:
            let halfs = ptr.assumingMemoryBound(to: UInt16.self)
            return SIMD3(halfToFloat(halfs[0]), halfToFloat(halfs[1]), halfToFloat(halfs[2]))
        case .half4:
            let halfs = ptr.assumingMemoryBound(to: UInt16.self)
            return SIMD3(halfToFloat(halfs[0]), halfToFloat(halfs[1]), halfToFloat(halfs[2]))
        default:
            metaphorWarning("Unsupported vertex format \(data.format.rawValue) for float3 attribute, using zero vector")
            return .zero
        }
    }

    private static func readFloat2(from data: MDLVertexAttributeData, index: Int) -> SIMD2<Float> {
        let stride = data.stride
        let offset = index * stride
        let ptr = data.dataStart.advanced(by: offset)

        switch data.format {
        case .float2:
            return ptr.assumingMemoryBound(to: SIMD2<Float>.self).pointee
        case .float3:
            let floats = ptr.assumingMemoryBound(to: Float.self)
            return SIMD2(floats[0], floats[1])
        case .half2:
            let halfs = ptr.assumingMemoryBound(to: UInt16.self)
            return SIMD2(halfToFloat(halfs[0]), halfToFloat(halfs[1]))
        case .half3:
            let halfs = ptr.assumingMemoryBound(to: UInt16.self)
            return SIMD2(halfToFloat(halfs[0]), halfToFloat(halfs[1]))
        default:
            metaphorWarning("Unsupported vertex format \(data.format.rawValue) for float2 attribute, using zero vector")
            return .zero
        }
    }

    private static func computeBoundsAndScale(
        _ vertices: [Vertex3D]
    ) -> (center: SIMD3<Float>, scale: Float) {
        guard !vertices.isEmpty else { return (.zero, 1) }
        var minPos = vertices[0].position
        var maxPos = vertices[0].position
        for v in vertices {
            minPos = min(minPos, v.position)
            maxPos = max(maxPos, v.position)
        }
        let center = (minPos + maxPos) * 0.5
        let extent = maxPos - minPos
        let maxExtent = max(extent.x, max(extent.y, extent.z))
        let scale: Float = maxExtent > 0 ? 2.0 / maxExtent : 1.0
        return (center, scale)
    }

    private static func normalizeVerticesOnly(_ vertices: inout [Vertex3D]) {
        let (center, scale) = computeBoundsAndScale(vertices)
        for i in 0..<vertices.count {
            vertices[i].position = (vertices[i].position - center) * scale
        }
    }

    private static func normalizeVertices(
        _ vertices: inout [Vertex3D],
        uvVertices: inout [Vertex3DTextured]
    ) {
        let (center, scale) = computeBoundsAndScale(vertices)
        for i in 0..<vertices.count {
            vertices[i].position = (vertices[i].position - center) * scale
        }
        for i in 0..<uvVertices.count {
            uvVertices[i].position = (uvVertices[i].position - center) * scale
        }
    }
}
