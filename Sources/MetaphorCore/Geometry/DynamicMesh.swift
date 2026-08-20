import Metal
import simd

/// 頂点を動的に追加・変更できる3Dメッシュを提供します。
///
/// openFrameworks の ofMesh や p5.js の p5.Geometry に相当する機能を提供します。
/// 頂点データが変更されると dirty フラグが設定され、描画時に GPU バッファが
/// 自動的に更新されます（変更された種類だけを、可能なら確保し直さずに）。
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

    // dirty は種類ごとに分ける。頂点を動かすアニメーションで**一度も変わらない
    // インデックス**まで作り直していたため（128×128 のハイトフィールドで
    // 378KB/フレーム）、頂点・インデックス・UV を別々に見る（Issue #686）。
    private var verticesDirty = true
    private var indicesDirty = true
    private var uvDirty = true

    // 種類ごとのリングバッファ。容量が足りていれば `contents()` へ memcpy し、
    // 足りないときだけ確保し直す。リングの深さはレンダラーのトリプルバッファリングに
    // 合わせてあり、GPU がまだ読んでいるバッファを上書きしないための猶予になる。
    private var vertexRing = BufferRing()
    private var indexRing = BufferRing()
    private var uvRing = BufferRing()

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
        verticesDirty = true
        uvDirty = true
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
        indicesDirty = true
    }

    /// 三角形を構成する3つのインデックスを追加します。
    public func addTriangle(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) {
        indices.append(contentsOf: [i0, i1, i2])
        indicesDirty = true
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
        verticesDirty = true
        uvDirty = true  // UV 付き頂点列は position / normal を含むので作り直す
    }

    /// 指定インデックスの頂点法線を設定します。
    public func setNormal(_ index: Int, _ normal: SIMD3<Float>) {
        vertices[index].normal = normal
        verticesDirty = true
        uvDirty = true  // UV 付き頂点列は position / normal を含むので作り直す
    }

    /// 指定インデックスの頂点カラーを設定します。
    public func setColor(_ index: Int, _ color: SIMD4<Float>) {
        vertices[index].color = color
        // UV 付き頂点（``Vertex3DTextured``）は position / normal / uv だけを持ち
        // カラーを含まないため、色の変更で UV 側を作り直す必要はない
        verticesDirty = true
    }

    /// 指定インデックスの頂点のテクスチャ座標を設定します。
    ///
    /// - Parameters:
    ///   - index: 頂点インデックス。
    ///   - uv: 正規化テクスチャ座標（0…1）。
    public func setTexCoord(_ index: Int, _ uv: SIMD2<Float>) {
        uvs[index] = uv
        hasExplicitUV = true
        uvDirty = true
    }

    /// すべての頂点とインデックスを削除します。
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        uvs.removeAll(keepingCapacity: true)
        pendingUV = .zero
        hasExplicitUV = false
        verticesDirty = true
        indicesDirty = true
        uvDirty = true
    }

    // MARK: - Internal GPU Buffer Management

    /// データが変更された場合に GPU バッファを更新します。
    ///
    /// 変更された種類だけを触ります。頂点を動かすアニメーションでは、
    /// **インデックスバッファは一度も作り直されません**（`indicesDirty` が立たないため）。
    /// 更新は既存バッファへの memcpy が既定で、容量が足りないときだけ確保し直します。
    internal func ensureBuffers() {
        guard verticesDirty || indicesDirty || uvDirty else { return }
        guard !vertices.isEmpty else {
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            cachedUVVertexBuffer = nil
            vertexRing.reset()
            indexRing.reset()
            uvRing.reset()
            verticesDirty = false
            indicesDirty = false
            uvDirty = false
            return
        }

        // 更新した結果はすべて揃ってからアトミックに差し替える。
        // 一部だけ成功した状態でキャッシュを更新すると「新頂点 × 旧インデックス」の
        // 不整合が生じ、インデックスが新頂点数を超えて GPU が範囲外を読み得る。
        func dropCaches(_ message: String) {
            metaphorWarning(message)
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            cachedUVVertexBuffer = nil
        }

        var newVertexBuffer = cachedVertexBuffer
        if verticesDirty || newVertexBuffer == nil {
            guard let vb = vertices.withUnsafeBytes({ raw in
                vertexRing.update(device: device, bytes: raw)
            }) else {
                dropCaches("DynamicMesh: Failed to allocate vertex buffer (\(vertices.count) vertices)")
                return
            }
            newVertexBuffer = vb
        }

        var newIndexBuffer = cachedIndexBuffer
        if indicesDirty || (newIndexBuffer == nil && !indices.isEmpty) {
            if indices.isEmpty {
                newIndexBuffer = nil
            } else {
                guard let ib = indices.withUnsafeBytes({ raw in
                    indexRing.update(device: device, bytes: raw)
                }) else {
                    dropCaches("DynamicMesh: Failed to allocate index buffer (\(indices.count) indices)")
                    return
                }
                newIndexBuffer = ib
            }
        }

        var newUVVertexBuffer = cachedUVVertexBuffer
        if uvDirty || (newUVVertexBuffer == nil && hasExplicitUV) {
            if let uvVertices = makeUVVertices() {
                guard let uvb = uvVertices.withUnsafeBytes({ raw in
                    uvRing.update(device: device, bytes: raw)
                }) else {
                    dropCaches(
                        "DynamicMesh: Failed to allocate UV vertex buffer (\(uvVertices.count) vertices)")
                    return
                }
                newUVVertexBuffer = uvb
            } else {
                newUVVertexBuffer = nil
            }
        }

        cachedVertexBuffer = newVertexBuffer
        cachedIndexBuffer = newIndexBuffer
        cachedUVVertexBuffer = newUVVertexBuffer
        verticesDirty = false
        indicesDirty = false
        uvDirty = false
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

// MARK: - BufferRing

/// 毎フレーム内容が変わりうるデータ 1 種類ぶんの、多重化された GPU バッファ（Issue #686）。
///
/// 更新のたびにスロットを 1 つ進め、そのスロットのバッファに**容量が足りていれば
/// memcpy**、足りなければ確保し直します。以前は `makeBuffer(bytes:)` で毎回
/// 確保していたため、128×128 のハイトフィールドを動かすだけで 60MB/s の確保が
/// 走っていました。
///
/// スロット数はレンダラーのトリプルバッファリングと同じ 3 です。GPU は最大で
/// 2 フレーム前のコマンドを実行中であり得るので、3 枚を巡回していれば
/// 「まだ読まれているバッファを上書きする」ことがありません。
///
/// 縮んだときにバッファは小さくし直しません（`length` は「確保済み容量」であって
/// 描画に使う量ではないため、余りは無害）。churn を避けるための意図的な選択で、
/// 全部返したいときは ``reset()`` を呼びます。
private struct BufferRing {
    private static let slotCount = 3

    private var buffers = [MTLBuffer?](repeating: nil, count: slotCount)
    private var slot = 0

    /// 次のスロットへ内容を書き込み、そのバッファを返します。
    /// - Returns: 確保に失敗した場合は `nil`（呼び出し側はキャッシュを捨てる）。
    mutating func update(device: MTLDevice, bytes: UnsafeRawBufferPointer) -> MTLBuffer? {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return nil }
        slot = (slot + 1) % Self.slotCount

        if let existing = buffers[slot], existing.length >= bytes.count {
            existing.contents().copyMemory(from: base, byteCount: bytes.count)
            return existing
        }

        guard let buffer = device.makeBuffer(
            bytes: base, length: bytes.count, options: .storageModeShared
        ) else {
            return nil
        }
        buffers[slot] = buffer
        return buffer
    }

    /// 確保済みのバッファをすべて手放します。
    mutating func reset() {
        for index in buffers.indices { buffers[index] = nil }
        slot = 0
    }
}
