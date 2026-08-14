import Metal
import simd

/// 頂点を動的に追加・変更できる3Dメッシュを提供します。
///
/// openFrameworks の ofMesh や p5.js の p5.Geometry に相当する機能を提供します。
/// 頂点データが変更されると isDirty フラグが設定され、描画時に GPU バッファが
/// 自動的に再構築されます。
///
/// ```swift
/// let mesh = createDynamicMesh()
/// mesh.addVertex(0, 0, 0)
/// mesh.addVertex(1, 0, 0)
/// mesh.addVertex(0.5, 1, 0)
/// mesh.addTriangle(0, 1, 2)
/// dynamicMesh(mesh)
/// ```
///
/// ``addTexCoord(_:_:)`` で UV を宣言したメッシュは、``Sketch/texture(_:)`` が
/// 設定されているときテクスチャを貼って描画されます。
@MainActor
public final class DynamicMesh {
    private let device: MTLDevice
    private var vertices: [Vertex3D] = []
    private var indices: [UInt32] = []
    // 頂点と同じ添字で並ぶ UV。UV を一度も宣言していないメッシュでは空のまま
    private var uvs: [SIMD2<Float>] = []
    private var isDirty = true
    private var cachedVertexBuffer: MTLBuffer?
    private var cachedIndexBuffer: MTLBuffer?
    private var cachedUVVertexBuffer: MTLBuffer?

    // 次に追加される頂点に適用するペンディング法線・カラー・UV
    private var pendingNormal: SIMD3<Float> = SIMD3(0, 1, 0)
    private var pendingColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var pendingUV: SIMD2<Float> = .zero

    // addTexCoord が一度でも呼ばれたか。UV を宣言していないメッシュを
    // 全頂点 uv=(0,0) でテクスチャ経路へ流さないための判定（#433 と同じ方針）
    private var hasExplicitUV = false

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Vertex Operations

    /// 指定位置に頂点を追加します。
    public func addVertex(_ position: SIMD3<Float>) {
        vertices.append(Vertex3D(
            position: position,
            normal: pendingNormal,
            color: pendingColor
        ))
        uvs.append(pendingUV)
        isDirty = true
    }

    /// 指定された x, y, z 座標に頂点を追加します。
    public func addVertex(_ x: Float, _ y: Float, _ z: Float) {
        addVertex(SIMD3(x, y, z))
    }

    /// 次に追加される頂点に適用する法線を設定します。
    public func addNormal(_ normal: SIMD3<Float>) {
        pendingNormal = normal
    }

    /// 次に追加される頂点に適用するカラーを設定します。
    public func addColor(_ color: Color) {
        pendingColor = color.simd
    }

    /// SIMD4 値を使用して、次に追加される頂点に適用するカラーを設定します。
    public func addColor(_ color: SIMD4<Float>) {
        pendingColor = color
    }

    /// 次に追加される頂点に適用するテクスチャ座標を設定します。
    ///
    /// UV を宣言したメッシュは、``Sketch/texture(_:)`` が設定されているとき
    /// テクスチャを貼って描画されます。一度も呼ばなければ従来どおり fill 色で塗られます。
    ///
    /// - Parameter uv: 正規化テクスチャ座標（0…1）。`textureMode()` は未実装です。
    public func addTexCoord(_ uv: SIMD2<Float>) {
        pendingUV = uv
        hasExplicitUV = true
    }

    /// 次に追加される頂点に適用するテクスチャ座標を設定します。
    ///
    /// - Parameters:
    ///   - u: 正規化した横方向のテクスチャ座標（0…1）。
    ///   - v: 正規化した縦方向のテクスチャ座標（0…1）。
    public func addTexCoord(_ u: Float, _ v: Float) {
        addTexCoord(SIMD2(u, v))
    }

    // MARK: - Index Operations

    /// インデックスを1つ追加します。
    public func addIndex(_ i: UInt32) {
        indices.append(i)
        isDirty = true
    }

    /// 三角形を構成する3つのインデックスを追加します。
    public func addTriangle(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) {
        indices.append(contentsOf: [i0, i1, i2])
        isDirty = true
    }

    // MARK: - Access & Modify

    /// 頂点数
    public var vertexCount: Int { vertices.count }

    /// インデックス数
    public var indexCount: Int { indices.count }

    /// 指定インデックスの頂点位置を返します。
    public func getVertex(_ index: Int) -> SIMD3<Float> {
        vertices[index].position
    }

    /// 指定インデックスの頂点位置を設定します。
    public func setVertex(_ index: Int, _ position: SIMD3<Float>) {
        vertices[index].position = position
        isDirty = true
    }

    /// 指定インデックスの頂点法線を設定します。
    public func setNormal(_ index: Int, _ normal: SIMD3<Float>) {
        vertices[index].normal = normal
        isDirty = true
    }

    /// 指定インデックスの頂点カラーを設定します。
    public func setColor(_ index: Int, _ color: SIMD4<Float>) {
        vertices[index].color = color
        isDirty = true
    }

    /// 指定インデックスの頂点のテクスチャ座標を設定します。
    ///
    /// - Parameters:
    ///   - index: 頂点インデックス。
    ///   - uv: 正規化テクスチャ座標（0…1）。
    public func setTexCoord(_ index: Int, _ uv: SIMD2<Float>) {
        uvs[index] = uv
        hasExplicitUV = true
        isDirty = true
    }

    /// すべての頂点とインデックスを削除します。
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        uvs.removeAll(keepingCapacity: true)
        pendingUV = .zero
        hasExplicitUV = false
        isDirty = true
    }

    // MARK: - Internal GPU Buffer Management

    /// データが変更された場合に GPU バッファを再構築します。
    internal func ensureBuffers() {
        guard isDirty else { return }
        guard !vertices.isEmpty else {
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            cachedUVVertexBuffer = nil
            isDirty = false
            return
        }

        // 頂点・インデックス・UV をすべて確保してからアトミックに差し替える。
        // 一部だけ成功した状態でキャッシュを更新すると「新頂点 × 旧インデックス」の
        // 不整合が生じ、インデックスが新頂点数を超えて GPU が範囲外を読み得る。
        func dropCaches(_ message: String) {
            metaphorWarning(message)
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            cachedUVVertexBuffer = nil
        }

        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex3D>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            dropCaches("DynamicMesh: Failed to allocate vertex buffer (\(vertices.count) vertices)")
            return
        }

        var newIndexBuffer: MTLBuffer?
        if !indices.isEmpty {
            guard let ib = device.makeBuffer(
                bytes: indices,
                length: MemoryLayout<UInt32>.stride * indices.count,
                options: .storageModeShared
            ) else {
                dropCaches("DynamicMesh: Failed to allocate index buffer (\(indices.count) indices)")
                return
            }
            newIndexBuffer = ib
        }

        var newUVVertexBuffer: MTLBuffer?
        if let uvVertices = makeUVVertices() {
            guard let uvb = device.makeBuffer(
                bytes: uvVertices,
                length: MemoryLayout<Vertex3DTextured>.stride * uvVertices.count,
                options: .storageModeShared
            ) else {
                dropCaches("DynamicMesh: Failed to allocate UV vertex buffer (\(uvVertices.count) vertices)")
                return
            }
            newUVVertexBuffer = uvb
        }

        cachedVertexBuffer = vb
        cachedIndexBuffer = newIndexBuffer
        cachedUVVertexBuffer = newUVVertexBuffer
        isDirty = false
    }

    /// UV を宣言済みのときだけ、位置・法線と同じ添字で並ぶ ``Vertex3DTextured`` 列を組み立てます。
    /// - Returns: UV 未宣言または頂点が空の場合は nil。
    private func makeUVVertices() -> [Vertex3DTextured]? {
        guard hasExplicitUV, !vertices.isEmpty else { return nil }
        return vertices.enumerated().map { index, vertex in
            Vertex3DTextured(position: vertex.position, normal: vertex.normal, uv: uvs[index])
        }
    }

    /// 記録経路（影オン / コマンド記録）用: 現在の内容を不変の ``Mesh`` として複製します。
    ///
    /// UV を宣言済みなら `uvVertices` も載せるため、記録経路でもテクスチャ判定と
    /// シャドウは `drawMesh` の既存経路に相乗りします。
    /// - Returns: 頂点が空の場合は nil。
    func makeSnapshotMesh() -> Mesh? {
        guard !vertices.isEmpty else { return nil }
        let uvVertices = makeUVVertices()
        if indices.isEmpty {
            return try? Mesh(device: device, vertices: vertices, indices: nil, uvVertices: uvVertices)
        }
        return try? Mesh(device: device, vertices: vertices, indices32: indices, uvVertices: uvVertices)
    }

    /// このメッシュが UV 座標を持つかどうか。
    public var hasUVs: Bool { hasExplicitUV }

    /// 頂点バッファを返します（ensureBuffers 呼び出し後に有効）。
    internal var vertexBuffer: MTLBuffer? { cachedVertexBuffer }

    /// UV 付き頂点バッファを返します（ensureBuffers 呼び出し後、UV 宣言時のみ有効）。
    internal var uvVertexBuffer: MTLBuffer? { cachedUVVertexBuffer }

    /// インデックスバッファを返します（ensureBuffers 呼び出し後に有効）。
    public var indexBuffer: MTLBuffer? { cachedIndexBuffer }
}
