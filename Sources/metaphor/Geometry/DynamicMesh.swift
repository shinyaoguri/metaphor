import Metal
import simd

/// 頂点を動的に追加・変更できる3Dメッシュ
///
/// Processing の ofMesh / p5.Geometry 相当の機能を提供する。
/// 頂点データが変更されるたびに isDirty フラグが立ち、
/// 描画時に自動で GPU バッファが再構築される。
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

    // 次に追加される頂点用の一時的な法線・カラー
    private var pendingNormal: SIMD3<Float> = SIMD3(0, 1, 0)
    private var pendingColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Vertex Operations

    /// 頂点を追加
    public func addVertex(_ position: SIMD3<Float>) {
        vertices.append(Vertex3D(
            position: position,
            normal: pendingNormal,
            color: pendingColor
        ))
        isDirty = true
    }

    /// 頂点を追加（座標指定）
    public func addVertex(_ x: Float, _ y: Float, _ z: Float) {
        addVertex(SIMD3(x, y, z))
    }

    /// 次に追加される頂点の法線を設定
    public func addNormal(_ normal: SIMD3<Float>) {
        pendingNormal = normal
    }

    /// 次に追加される頂点のカラーを設定
    public func addColor(_ color: Color) {
        pendingColor = color.simd
    }

    /// 次に追加される頂点のカラーを設定（SIMD4版）
    public func addColor(_ color: SIMD4<Float>) {
        pendingColor = color
    }

    // MARK: - Index Operations

    /// インデックスを追加
    public func addIndex(_ i: UInt32) {
        indices.append(i)
        isDirty = true
    }

    /// 三角形のインデックスを追加（3つ一組）
    public func addTriangle(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) {
        indices.append(contentsOf: [i0, i1, i2])
        isDirty = true
    }

    // MARK: - Access & Modify

    /// 頂点数
    public var vertexCount: Int { vertices.count }

    /// インデックス数
    public var indexCount: Int { indices.count }

    /// 頂点位置を取得
    public func getVertex(_ index: Int) -> SIMD3<Float> {
        vertices[index].position
    }

    /// 頂点位置を変更
    public func setVertex(_ index: Int, _ position: SIMD3<Float>) {
        vertices[index].position = position
        isDirty = true
    }

    /// 頂点法線を変更
    public func setNormal(_ index: Int, _ normal: SIMD3<Float>) {
        vertices[index].normal = normal
        isDirty = true
    }

    /// 頂点カラーを変更
    public func setColor(_ index: Int, _ color: SIMD4<Float>) {
        vertices[index].color = color
        isDirty = true
    }

    /// 全データをクリア
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        isDirty = true
    }

    // MARK: - Internal GPU Buffer Management

    /// GPU バッファを更新（isDirty の場合のみ）
    internal func ensureBuffers() {
        guard isDirty else { return }
        guard !vertices.isEmpty else {
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            isDirty = false
            return
        }

        cachedVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex3D>.stride * vertices.count,
            options: .storageModeShared
        )

        if !indices.isEmpty {
            cachedIndexBuffer = device.makeBuffer(
                bytes: indices,
                length: MemoryLayout<UInt32>.stride * indices.count,
                options: .storageModeShared
            )
        } else {
            cachedIndexBuffer = nil
        }

        isDirty = false
    }

    /// 頂点バッファ（ensureBuffers後に有効）
    internal var vertexBuffer: MTLBuffer? { cachedVertexBuffer }

    /// インデックスバッファ（ensureBuffers後に有効）
    internal var indexBuffer: MTLBuffer? { cachedIndexBuffer }
}
