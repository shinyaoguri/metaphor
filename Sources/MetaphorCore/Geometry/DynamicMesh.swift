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
@MainActor
public final class DynamicMesh {
    private let device: MTLDevice
    private var vertices: [Vertex3D] = []
    private var indices: [UInt32] = []
    private var isDirty = true
    private var cachedVertexBuffer: MTLBuffer?
    private var cachedIndexBuffer: MTLBuffer?

    // 次に追加される頂点に適用するペンディング法線とカラー
    private var pendingNormal: SIMD3<Float> = SIMD3(0, 1, 0)
    private var pendingColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

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

    /// すべての頂点とインデックスを削除します。
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        isDirty = true
    }

    // MARK: - Internal GPU Buffer Management

    /// データが変更された場合に GPU バッファを再構築します。
    internal func ensureBuffers() {
        guard isDirty else { return }
        guard !vertices.isEmpty else {
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            isDirty = false
            return
        }

        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex3D>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            metaphorWarning("DynamicMesh: Failed to allocate vertex buffer (\(vertices.count) vertices)")
            return
        }
        cachedVertexBuffer = vb

        if !indices.isEmpty {
            guard let ib = device.makeBuffer(
                bytes: indices,
                length: MemoryLayout<UInt32>.stride * indices.count,
                options: .storageModeShared
            ) else {
                metaphorWarning("DynamicMesh: Failed to allocate index buffer (\(indices.count) indices)")
                return
            }
            cachedIndexBuffer = ib
        } else {
            cachedIndexBuffer = nil
        }

        isDirty = false
    }

    /// 頂点バッファを返します（ensureBuffers 呼び出し後に有効）。
    internal var vertexBuffer: MTLBuffer? { cachedVertexBuffer }

    /// インデックスバッファを返します（ensureBuffers 呼び出し後に有効）。
    public var indexBuffer: MTLBuffer? { cachedIndexBuffer }
}
