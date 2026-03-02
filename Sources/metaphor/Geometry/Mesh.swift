import Metal
import simd

// MARK: - Vertex3D

/// Represent a 3D vertex with position, normal, and color (positionNormalColor layout, 48 bytes/vertex).
///
/// Has a memory layout matching `VertexLayout.positionNormalColor`.
struct Vertex3D {
    var position: SIMD3<Float>  // 16 bytes (SIMD3 stride)
    var normal: SIMD3<Float>    // 16 bytes
    var color: SIMD4<Float>     // 16 bytes
}

// MARK: - Vertex3DTextured

/// Represent a 3D textured vertex with position, normal, and UV (positionNormalUV layout, 48 bytes/vertex).
///
/// Has a memory layout matching `VertexLayout.positionNormalUV`.
/// Due to SIMD3 alignment (16 bytes), the stride is 48 (8 bytes of padding after uv).
struct Vertex3DTextured {
    var position: SIMD3<Float>  // 16 bytes
    var normal: SIMD3<Float>    // 16 bytes
    var uv: SIMD2<Float>        // 8 bytes + 8 bytes alignment padding = 48 stride
}

// MARK: - Mesh

/// Store 3D mesh data including vertex and optional index buffers.
///
/// Holds a vertex buffer and an optional index buffer.
/// Provides static factory methods for generating basic primitives.
/// Optionally holds a UV vertex buffer for texture mapping.
///
/// ```swift
/// let box = Mesh.box(device: device)
/// let sphere = Mesh.sphere(device: device, radius: 0.5)
/// ```
@MainActor
public final class Mesh {
    /// Vertex buffer containing Vertex3D data.
    public let vertexBuffer: MTLBuffer

    /// Index buffer, or nil for non-indexed drawing.
    public let indexBuffer: MTLBuffer?

    /// Number of vertices.
    public let vertexCount: Int

    /// Number of indices.
    public let indexCount: Int

    /// Index element type.
    public let indexType: MTLIndexType

    /// UV vertex buffer containing Vertex3DTextured data for texture mapping.
    public let uvVertexBuffer: MTLBuffer?

    /// Number of UV vertices.
    public let uvVertexCount: Int

    /// Whether this mesh has UV coordinates.
    public let hasUVs: Bool

    // MARK: - Initialization

    init(device: MTLDevice, vertices: [Vertex3D], indices: [UInt16]? = nil,
         uvVertices: [Vertex3DTextured]? = nil) {
        self.vertexCount = vertices.count

        let vertexSize = vertices.count * MemoryLayout<Vertex3D>.stride
        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: vertexSize,
            options: .storageModeShared
        ) else {
            fatalError("[metaphor] Failed to create vertex buffer (size: \(vertexSize) bytes, \(vertices.count) vertices). GPU memory may be exhausted.")
        }
        self.vertexBuffer = vb

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

    /// Initialize a mesh with UInt32 indices for large meshes.
    init(device: MTLDevice, vertices: [Vertex3D], indices32: [UInt32],
         uvVertices: [Vertex3DTextured]? = nil) {
        self.vertexCount = vertices.count

        let vertexSize = vertices.count * MemoryLayout<Vertex3D>.stride
        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: vertexSize,
            options: .storageModeShared
        ) else {
            fatalError("[metaphor] Failed to create vertex buffer (size: \(vertexSize) bytes, \(vertices.count) vertices). GPU memory may be exhausted.")
        }
        self.vertexBuffer = vb

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
    /// Create a box mesh with 24 vertices, 36 indices, flat normals, and UV coordinates.
    public static func box(
        device: MTLDevice,
        width: Float = 1,
        height: Float = 1,
        depth: Float = 1
    ) -> Mesh {
        let hw = width / 2, hh = height / 2, hd = depth / 2
        let white = SIMD4<Float>(1, 1, 1, 1)

        // UV coordinates for each face (bottom-left, bottom-right, top-right, top-left)
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
    /// Create a UV sphere mesh with smooth normals and UV coordinates.
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
    /// Create a plane mesh on the XY plane with +Z normals and UV coordinates.
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
    /// Create a cylinder mesh with side surface, top and bottom caps, and UV coordinates.
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

        // --- Side surface ---
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let normal = SIMD3<Float>(c, 0, s)
            let u = Float(i) / Float(segments)

            // Top ring
            let topPos = SIMD3(c * radius, hh, s * radius)
            vertices.append(Vertex3D(position: topPos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: topPos, normal: normal, uv: SIMD2(u, 0)))
            // Bottom ring
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

        // --- Top cap ---
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

        // --- Bottom cap (reversed winding) ---
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
    /// Create a cone mesh with side surface, bottom cap, and UV coordinates.
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

        // --- Side surface ---
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let c = cos(angle), s = sin(angle)
            let normal = normalize(SIMD3<Float>(c * height, radius, s * height))
            let u = Float(i) / Float(segments)

            // Tip
            let tipPos = SIMD3<Float>(0, hh, 0)
            vertices.append(Vertex3D(position: tipPos, normal: normal, color: white))
            uvVertices.append(Vertex3DTextured(position: tipPos, normal: normal, uv: SIMD2(u, 0)))
            // Base
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

        // --- Bottom cap ---
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
    /// Create a torus mesh using a parametric surface with UV coordinates.
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
    /// Load a mesh from an OBJ file at the given URL.
    public static func loadOBJ(device: MTLDevice, url: URL) throws -> Mesh {
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let mesh = loadOBJ(device: device, source: source) else {
            throw MeshError.parseError("Failed to parse OBJ data")
        }
        return mesh
    }

    /// Load a model file using Model I/O (supports OBJ, USDZ, ABC formats).
    /// - Parameters:
    ///   - device: The Metal device to create GPU buffers on.
    ///   - url: The URL of the model file.
    ///   - normalize: If true, normalizes the bounding box to [-1, 1].
    /// - Returns: A Mesh instance containing the loaded model data.
    public static func load(device: MTLDevice, url: URL, normalize: Bool = true) throws -> Mesh {
        return try ModelIOLoader.load(device: device, url: url, normalize: normalize)
    }

    /// Parse an OBJ format string and generate a mesh.
    public static func loadOBJ(device: MTLDevice, source: String) -> Mesh? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texCoords: [SIMD2<Float>] = []

        struct FaceIndex: Hashable {
            let v: Int
            let vt: Int  // -1 = none
            let vn: Int  // -1 = none
        }

        var indexMap: [FaceIndex: Int] = [:]
        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        var indices: [UInt32] = []
        var hasUVs = false
        var hasNormals = false

        let white = SIMD4<Float>(1, 1, 1, 1)

        /// Parse a face vertex token and return the vertex index along with UV/normal presence flags.
        func resolveIndex(_ token: String) -> (index: Int, hasUV: Bool, hasNormal: Bool) {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let viRaw = Int(parts[0]) else { return (0, false, false) }
            let vi = viRaw - 1
            let vti: Int
            let vni: Int
            var foundUV = false
            var foundNormal = false

            if parts.count > 1 && !parts[1].isEmpty, let vtiRaw = Int(parts[1]) {
                vti = vtiRaw - 1
                foundUV = true
            } else {
                vti = -1
            }

            if parts.count > 2 && !parts[2].isEmpty, let vniRaw = Int(parts[2]) {
                vni = vniRaw - 1
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

        // Auto-compute face normals when none are provided
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
