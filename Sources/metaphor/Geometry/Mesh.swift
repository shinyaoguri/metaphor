import Metal
import simd

// MARK: - Vertex3D

/// 3D頂点データ（positionNormalColor レイアウト、48 bytes/vertex）
///
/// `VertexLayout.positionNormalColor` と一致するメモリレイアウトを持つ。
struct Vertex3D {
    var position: SIMD3<Float>  // 16 bytes (SIMD3 stride)
    var normal: SIMD3<Float>    // 16 bytes
    var color: SIMD4<Float>     // 16 bytes
}

// MARK: - Vertex3DTextured

/// 3Dテクスチャ付き頂点データ（positionNormalUV レイアウト、48 bytes/vertex）
///
/// `VertexLayout.positionNormalUV` と一致するメモリレイアウトを持つ。
/// SIMD3のアラインメント（16バイト）により、stride=48（uv後に8バイトのパディング）。
struct Vertex3DTextured {
    var position: SIMD3<Float>  // 16 bytes
    var normal: SIMD3<Float>    // 16 bytes
    var uv: SIMD2<Float>        // 8 bytes + 8 bytes alignment padding = 48 stride
}

// MARK: - Mesh

/// 3Dメッシュデータ
///
/// 頂点バッファとオプションのインデックスバッファを保持する。
/// 静的ファクトリメソッドで基本プリミティブを生成可能。
/// テクスチャマッピング用のUV頂点バッファもオプションで保持。
///
/// ```swift
/// let box = Mesh.box(device: device)
/// let sphere = Mesh.sphere(device: device, radius: 0.5)
/// ```
@MainActor
public final class Mesh {
    /// 頂点バッファ（Vertex3D）
    public let vertexBuffer: MTLBuffer

    /// インデックスバッファ（nilの場合は非インデックス描画）
    public let indexBuffer: MTLBuffer?

    /// 頂点数
    public let vertexCount: Int

    /// インデックス数
    public let indexCount: Int

    /// インデックス型
    public let indexType: MTLIndexType

    /// UV付き頂点バッファ（Vertex3DTextured、テクスチャマッピング用）
    public let uvVertexBuffer: MTLBuffer?

    /// UV付き頂点数
    public let uvVertexCount: Int

    /// UV座標を持つかどうか
    public let hasUVs: Bool

    // MARK: - Initialization

    init(device: MTLDevice, vertices: [Vertex3D], indices: [UInt16]? = nil,
         uvVertices: [Vertex3DTextured]? = nil) {
        self.vertexCount = vertices.count

        let vertexSize = vertices.count * MemoryLayout<Vertex3D>.stride
        self.vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertexSize,
            options: .storageModeShared
        )!

        if let indices = indices, !indices.isEmpty {
            self.indexCount = indices.count
            let indexSize = indices.count * MemoryLayout<UInt16>.stride
            self.indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indexSize,
                options: .storageModeShared
            )
            self.indexType = .uint16
        } else {
            self.indexCount = 0
            self.indexBuffer = nil
            self.indexType = .uint16
        }

        if let uvVerts = uvVertices, !uvVerts.isEmpty {
            self.uvVertexCount = uvVerts.count
            let uvSize = uvVerts.count * MemoryLayout<Vertex3DTextured>.stride
            self.uvVertexBuffer = device.makeBuffer(
                bytes: uvVerts,
                length: uvSize,
                options: .storageModeShared
            )
            self.hasUVs = true
        } else {
            self.uvVertexCount = 0
            self.uvVertexBuffer = nil
            self.hasUVs = false
        }
    }

    /// UInt32インデックス対応イニシャライザ（大規模メッシュ用）
    init(device: MTLDevice, vertices: [Vertex3D], indices32: [UInt32],
         uvVertices: [Vertex3DTextured]? = nil) {
        self.vertexCount = vertices.count

        let vertexSize = vertices.count * MemoryLayout<Vertex3D>.stride
        self.vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertexSize,
            options: .storageModeShared
        )!

        if !indices32.isEmpty {
            self.indexCount = indices32.count
            let indexSize = indices32.count * MemoryLayout<UInt32>.stride
            self.indexBuffer = device.makeBuffer(
                bytes: indices32,
                length: indexSize,
                options: .storageModeShared
            )
            self.indexType = .uint32
        } else {
            self.indexCount = 0
            self.indexBuffer = nil
            self.indexType = .uint32
        }

        if let uvVerts = uvVertices, !uvVerts.isEmpty {
            self.uvVertexCount = uvVerts.count
            let uvSize = uvVerts.count * MemoryLayout<Vertex3DTextured>.stride
            self.uvVertexBuffer = device.makeBuffer(
                bytes: uvVerts,
                length: uvSize,
                options: .storageModeShared
            )
            self.hasUVs = true
        } else {
            self.uvVertexCount = 0
            self.uvVertexBuffer = nil
            self.hasUVs = false
        }
    }
}

// MARK: - Box

extension Mesh {
    /// ボックスメッシュ（24頂点、36インデックス、フラット法線、UV付き）
    public static func box(
        device: MTLDevice,
        width: Float = 1,
        height: Float = 1,
        depth: Float = 1
    ) -> Mesh {
        let hw = width / 2, hh = height / 2, hd = depth / 2
        let white = SIMD4<Float>(1, 1, 1, 1)

        // 各面のUV座標（bottom-left, bottom-right, top-right, top-left）
        let faceUVs: [SIMD2<Float>] = [
            SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0),
        ]

        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            // +Z (front)
            (SIMD3(0, 0, 1), [
                SIMD3(-hw, -hh, hd), SIMD3(hw, -hh, hd),
                SIMD3(hw, hh, hd), SIMD3(-hw, hh, hd),
            ]),
            // -Z (back)
            (SIMD3(0, 0, -1), [
                SIMD3(hw, -hh, -hd), SIMD3(-hw, -hh, -hd),
                SIMD3(-hw, hh, -hd), SIMD3(hw, hh, -hd),
            ]),
            // +Y (top)
            (SIMD3(0, 1, 0), [
                SIMD3(-hw, hh, hd), SIMD3(hw, hh, hd),
                SIMD3(hw, hh, -hd), SIMD3(-hw, hh, -hd),
            ]),
            // -Y (bottom)
            (SIMD3(0, -1, 0), [
                SIMD3(-hw, -hh, -hd), SIMD3(hw, -hh, -hd),
                SIMD3(hw, -hh, hd), SIMD3(-hw, -hh, hd),
            ]),
            // +X (right)
            (SIMD3(1, 0, 0), [
                SIMD3(hw, -hh, hd), SIMD3(hw, -hh, -hd),
                SIMD3(hw, hh, -hd), SIMD3(hw, hh, hd),
            ]),
            // -X (left)
            (SIMD3(-1, 0, 0), [
                SIMD3(-hw, -hh, -hd), SIMD3(-hw, -hh, hd),
                SIMD3(-hw, hh, hd), SIMD3(-hw, hh, -hd),
            ]),
        ]

        var vertices: [Vertex3D] = []
        vertices.reserveCapacity(24)
        var uvVertices: [Vertex3DTextured] = []
        uvVertices.reserveCapacity(24)
        var indices: [UInt16] = []
        indices.reserveCapacity(36)

        for (normal, corners) in faces {
            let base = UInt16(vertices.count)
            for (idx, corner) in corners.enumerated() {
                vertices.append(Vertex3D(position: corner, normal: normal, color: white))
                uvVertices.append(Vertex3DTextured(position: corner, normal: normal, uv: faceUVs[idx]))
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - Sphere

extension Mesh {
    /// UV球メッシュ（スムース法線、UV付き）
    public static func sphere(
        device: MTLDevice,
        radius: Float = 0.5,
        segments: Int = 24,
        rings: Int = 16
    ) -> Mesh {
        let white = SIMD4<Float>(1, 1, 1, 1)
        var vertices: [Vertex3D] = []
        vertices.reserveCapacity((rings + 1) * (segments + 1))
        var uvVertices: [Vertex3DTextured] = []
        uvVertices.reserveCapacity((rings + 1) * (segments + 1))
        var indices: [UInt16] = []
        indices.reserveCapacity(rings * segments * 6)

        for lat in 0...rings {
            let theta = Float(lat) / Float(rings) * Float.pi
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            let v = Float(lat) / Float(rings)

            for lon in 0...segments {
                let phi = Float(lon) / Float(segments) * Float.pi * 2
                let u = Float(lon) / Float(segments)
                let normal = SIMD3<Float>(
                    sinTheta * cos(phi),
                    cosTheta,
                    sinTheta * sin(phi)
                )
                let position = normal * radius
                vertices.append(Vertex3D(position: position, normal: normal, color: white))
                uvVertices.append(Vertex3DTextured(position: position, normal: normal, uv: SIMD2(u, v)))
            }
        }

        let cols = segments + 1
        for lat in 0..<rings {
            for lon in 0..<segments {
                let a = UInt16(lat * cols + lon)
                let b = a + UInt16(cols)
                indices.append(contentsOf: [a, b, a + 1, b, b + 1, a + 1])
            }
        }

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - Plane

extension Mesh {
    /// 平面メッシュ（XY平面、+Z法線、UV付き）
    public static func plane(
        device: MTLDevice,
        width: Float = 1,
        height: Float = 1
    ) -> Mesh {
        let hw = width / 2, hh = height / 2
        let normal = SIMD3<Float>(0, 0, 1)
        let white = SIMD4<Float>(1, 1, 1, 1)

        let vertices = [
            Vertex3D(position: SIMD3(-hw, -hh, 0), normal: normal, color: white),
            Vertex3D(position: SIMD3(hw, -hh, 0), normal: normal, color: white),
            Vertex3D(position: SIMD3(hw, hh, 0), normal: normal, color: white),
            Vertex3D(position: SIMD3(-hw, hh, 0), normal: normal, color: white),
        ]
        let uvVertices = [
            Vertex3DTextured(position: SIMD3(-hw, -hh, 0), normal: normal, uv: SIMD2(0, 1)),
            Vertex3DTextured(position: SIMD3(hw, -hh, 0), normal: normal, uv: SIMD2(1, 1)),
            Vertex3DTextured(position: SIMD3(hw, hh, 0), normal: normal, uv: SIMD2(1, 0)),
            Vertex3DTextured(position: SIMD3(-hw, hh, 0), normal: normal, uv: SIMD2(0, 0)),
        ]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - Cylinder

extension Mesh {
    /// シリンダーメッシュ（側面 + 上下キャップ、UV付き）
    public static func cylinder(
        device: MTLDevice,
        radius: Float = 0.5,
        height: Float = 1,
        segments: Int = 24
    ) -> Mesh {
        let hh = height / 2
        let white = SIMD4<Float>(1, 1, 1, 1)
        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        var indices: [UInt16] = []

        // --- 側面 ---
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let normal = SIMD3<Float>(c, 0, s)
            let u = Float(i) / Float(segments)

            // 上リング
            let topPos = SIMD3(c * radius, hh, s * radius)
            vertices.append(Vertex3D(position: topPos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: topPos, normal: normal, uv: SIMD2(u, 0)))
            // 下リング
            let botPos = SIMD3(c * radius, -hh, s * radius)
            vertices.append(Vertex3D(position: botPos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: botPos, normal: normal, uv: SIMD2(u, 1)))
        }

        for i in 0..<segments {
            let topA = UInt16(i * 2)
            let botA = topA + 1
            let topB = topA + 2
            let botB = topA + 3
            indices.append(contentsOf: [topA, botA, topB, botA, botB, topB])
        }

        // --- 上キャップ ---
        let topCenter = UInt16(vertices.count)
        let topCenterPos = SIMD3<Float>(0, hh, 0)
        let topNormal = SIMD3<Float>(0, 1, 0)
        vertices.append(Vertex3D(position: topCenterPos, normal: topNormal, color: white))
        uvVertices.append(Vertex3DTextured(position: topCenterPos, normal: topNormal, uv: SIMD2(0.5, 0.5)))
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let pos = SIMD3(c * radius, hh, s * radius)
            vertices.append(Vertex3D(position: pos, normal: topNormal, color: white))
            uvVertices.append(Vertex3DTextured(
                position: pos, normal: topNormal,
                uv: SIMD2(0.5 + c * 0.5, 0.5 + s * 0.5)
            ))
        }
        for i in 0..<segments {
            let a = topCenter + 1 + UInt16(i)
            indices.append(contentsOf: [topCenter, a, a + 1])
        }

        // --- 下キャップ（反転ワインディング） ---
        let botCenter = UInt16(vertices.count)
        let botCenterPos = SIMD3<Float>(0, -hh, 0)
        let botNormal = SIMD3<Float>(0, -1, 0)
        vertices.append(Vertex3D(position: botCenterPos, normal: botNormal, color: white))
        uvVertices.append(Vertex3DTextured(position: botCenterPos, normal: botNormal, uv: SIMD2(0.5, 0.5)))
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let pos = SIMD3(c * radius, -hh, s * radius)
            vertices.append(Vertex3D(position: pos, normal: botNormal, color: white))
            uvVertices.append(Vertex3DTextured(
                position: pos, normal: botNormal,
                uv: SIMD2(0.5 + c * 0.5, 0.5 + s * 0.5)
            ))
        }
        for i in 0..<segments {
            let a = botCenter + 1 + UInt16(i)
            indices.append(contentsOf: [botCenter, a + 1, a])
        }

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - Cone

extension Mesh {
    /// コーンメッシュ（側面 + 底キャップ、UV付き）
    public static func cone(
        device: MTLDevice,
        radius: Float = 0.5,
        height: Float = 1,
        segments: Int = 24
    ) -> Mesh {
        let hh = height / 2
        let white = SIMD4<Float>(1, 1, 1, 1)
        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        var indices: [UInt16] = []

        // --- 側面 ---
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let normal = normalize(SIMD3<Float>(c * height, radius, s * height))
            let u = Float(i) / Float(segments)

            // 先端
            let tipPos = SIMD3<Float>(0, hh, 0)
            vertices.append(Vertex3D(position: tipPos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: tipPos, normal: normal, uv: SIMD2(u, 0)))
            // 底面
            let basePos = SIMD3(c * radius, -hh, s * radius)
            vertices.append(Vertex3D(position: basePos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: basePos, normal: normal, uv: SIMD2(u, 1)))
        }

        for i in 0..<segments {
            let tipI = UInt16(i * 2)
            let baseI = tipI + 1
            let baseNext = tipI + 3
            indices.append(contentsOf: [tipI, baseI, baseNext])
        }

        // --- 底キャップ ---
        let botCenter = UInt16(vertices.count)
        let botCenterPos = SIMD3<Float>(0, -hh, 0)
        let botNormal = SIMD3<Float>(0, -1, 0)
        vertices.append(Vertex3D(position: botCenterPos, normal: botNormal, color: white))
        uvVertices.append(Vertex3DTextured(position: botCenterPos, normal: botNormal, uv: SIMD2(0.5, 0.5)))
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let pos = SIMD3(c * radius, -hh, s * radius)
            vertices.append(Vertex3D(position: pos, normal: botNormal, color: white))
            uvVertices.append(Vertex3DTextured(
                position: pos, normal: botNormal,
                uv: SIMD2(0.5 + c * 0.5, 0.5 + s * 0.5)
            ))
        }
        for i in 0..<segments {
            let a = botCenter + 1 + UInt16(i)
            indices.append(contentsOf: [botCenter, a + 1, a])
        }

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - Torus

extension Mesh {
    /// トーラスメッシュ（パラメトリック面、UV付き）
    public static func torus(
        device: MTLDevice,
        ringRadius: Float = 0.5,
        tubeRadius: Float = 0.2,
        segments: Int = 24,
        tubeSegments: Int = 16
    ) -> Mesh {
        let white = SIMD4<Float>(1, 1, 1, 1)
        var vertices: [Vertex3D] = []
        vertices.reserveCapacity((segments + 1) * (tubeSegments + 1))
        var uvVertices: [Vertex3DTextured] = []
        uvVertices.reserveCapacity((segments + 1) * (tubeSegments + 1))
        var indices: [UInt16] = []
        indices.reserveCapacity(segments * tubeSegments * 6)

        for i in 0...segments {
            let uAngle = Float(i) / Float(segments) * Float.pi * 2
            let cu = cos(uAngle), su = sin(uAngle)
            let uCoord = Float(i) / Float(segments)

            for j in 0...tubeSegments {
                let vAngle = Float(j) / Float(tubeSegments) * Float.pi * 2
                let cv = cos(vAngle), sv = sin(vAngle)
                let vCoord = Float(j) / Float(tubeSegments)

                let r = ringRadius + tubeRadius * cv
                let position = SIMD3<Float>(r * cu, tubeRadius * sv, r * su)
                let center = SIMD3<Float>(ringRadius * cu, 0, ringRadius * su)
                let normal = normalize(position - center)

                vertices.append(Vertex3D(position: position, normal: normal, color: white))
                uvVertices.append(Vertex3DTextured(position: position, normal: normal, uv: SIMD2(uCoord, vCoord)))
            }
        }

        let cols = tubeSegments + 1
        for i in 0..<segments {
            for j in 0..<tubeSegments {
                let a = UInt16(i * cols + j)
                let b = a + UInt16(cols)
                indices.append(contentsOf: [a, b, a + 1, b, b + 1, a + 1])
            }
        }

        return Mesh(device: device, vertices: vertices, indices: indices, uvVertices: uvVertices)
    }
}

// MARK: - OBJ Loader

public enum MeshError: Error {
    case fileNotFound
    case parseError(String)
}

extension Mesh {
    /// OBJファイルをURLから読み込み
    public static func loadOBJ(device: MTLDevice, url: URL) throws -> Mesh {
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let mesh = loadOBJ(device: device, source: source) else {
            throw MeshError.parseError("Failed to parse OBJ data")
        }
        return mesh
    }

    /// OBJ文字列からメッシュを生成
    public static func loadOBJ(device: MTLDevice, source: String) -> Mesh? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texCoords: [SIMD2<Float>] = []

        struct FaceIndex: Hashable {
            let v: Int
            let vt: Int  // -1 = なし
            let vn: Int  // -1 = なし
        }

        var indexMap: [FaceIndex: Int] = [:]
        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        var indices: [UInt32] = []
        var hasUVs = false
        var hasNormals = false

        let white = SIMD4<Float>(1, 1, 1, 1)

        /// face頂点トークンをパースし、頂点インデックスとUV/法線の有無を返す
        func resolveIndex(_ token: String) -> (index: Int, hasUV: Bool, hasNormal: Bool) {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            let vi = Int(parts[0])! - 1
            let vti: Int
            let vni: Int
            var foundUV = false
            var foundNormal = false

            if parts.count > 1 && !parts[1].isEmpty {
                vti = Int(parts[1])! - 1
                foundUV = true
            } else {
                vti = -1
            }

            if parts.count > 2 && !parts[2].isEmpty {
                vni = Int(parts[2])! - 1
                foundNormal = true
            } else {
                vni = -1
            }

            let faceIdx = FaceIndex(v: vi, vt: vti, vn: vni)
            if let existing = indexMap[faceIdx] {
                return (existing, foundUV, foundNormal)
            }

            let pos = positions[vi]
            let norm = vni >= 0 ? normals[vni] : SIMD3<Float>(0, 0, 0)
            let uv = vti >= 0 ? texCoords[vti] : SIMD2<Float>(0, 0)

            let newIndex = vertices.count
            vertices.append(Vertex3D(position: pos, normal: norm, color: white))
            uvVertices.append(Vertex3DTextured(position: pos, normal: norm, uv: uv))
            indexMap[faceIdx] = newIndex
            return (newIndex, foundUV, foundNormal)
        }

        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard !parts.isEmpty else { continue }

            switch parts[0] {
            case "v":
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]) else { continue }
                positions.append(SIMD3(x, y, z))

            case "vn":
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]) else { continue }
                normals.append(SIMD3(x, y, z))

            case "vt":
                guard parts.count >= 3,
                      let u = Float(parts[1]),
                      let v = Float(parts[2]) else { continue }
                texCoords.append(SIMD2(u, v))

            case "f":
                let faceCount = parts.count - 1
                guard faceCount >= 3 else { continue }

                var faceVertexIndices: [Int] = []
                for i in 1..<parts.count {
                    let result = resolveIndex(String(parts[i]))
                    faceVertexIndices.append(result.index)
                    if result.hasUV { hasUVs = true }
                    if result.hasNormal { hasNormals = true }
                }

                // fan tessellation
                for i in 1..<(faceCount - 1) {
                    indices.append(contentsOf: [
                        UInt32(faceVertexIndices[0]),
                        UInt32(faceVertexIndices[i]),
                        UInt32(faceVertexIndices[i + 1]),
                    ])
                }

            default:
                continue
            }
        }

        guard !vertices.isEmpty, !indices.isEmpty else { return nil }

        // 法線が無い場合は面法線を自動計算
        if !hasNormals {
            for i in 0..<vertices.count {
                vertices[i].normal = .zero
                uvVertices[i].normal = .zero
            }

            var tri = 0
            while tri < indices.count {
                let i0 = Int(indices[tri])
                let i1 = Int(indices[tri + 1])
                let i2 = Int(indices[tri + 2])
                let p0 = vertices[i0].position
                let p1 = vertices[i1].position
                let p2 = vertices[i2].position
                let edge1 = p1 - p0
                let edge2 = p2 - p0
                let faceNormal = simd_cross(edge1, edge2)

                for idx in [i0, i1, i2] {
                    vertices[idx].normal += faceNormal
                    uvVertices[idx].normal += faceNormal
                }
                tri += 3
            }

            for i in 0..<vertices.count {
                let len = simd_length(vertices[i].normal)
                let normalized = len > 0 ? vertices[i].normal / len : SIMD3<Float>(0, 1, 0)
                vertices[i].normal = normalized
                uvVertices[i].normal = normalized
            }
        }

        if vertices.count <= 65535 {
            let indices16 = indices.map { UInt16($0) }
            return Mesh(
                device: device,
                vertices: vertices,
                indices: indices16,
                uvVertices: hasUVs ? uvVertices : nil
            )
        } else {
            return Mesh(
                device: device,
                vertices: vertices,
                indices32: indices,
                uvVertices: hasUVs ? uvVertices : nil
            )
        }
    }
}
