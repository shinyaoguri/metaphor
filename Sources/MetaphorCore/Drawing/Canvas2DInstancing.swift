import Metal
import simd

// MARK: - Shape Type

/// 2D インスタンス描画用のシェイプタイプ。
enum Shape2DType: UInt8, Hashable {
    /// 楕円 / 円シェイプ。
    case ellipse
    /// 矩形 / 正方形シェイプ。
    case rect
}

// MARK: - Per-Instance GPU Data

/// Canvas2D インスタンス描画用のインスタンスごとのデータ（80バイト、16バイトアライメント）。
///
/// 頂点シェーダーが `instance_id` でインデックスし、各インスタンスのトランスフォームと色を読み取ります。
/// `float3x3` の2Dアフィン変換は `float4x4` に埋め込まれます（3Dと同じパターン）。
struct InstanceData2D {
    /// float4x4 に埋め込まれた2Dアフィン変換（currentTransform * shapeLocal）。
    var transform: float4x4       // 64 bytes
    /// 塗りつぶし色（RGBA）。
    var color: SIMD4<Float>       // 16 bytes
}

// MARK: - Batch Key

/// 2D描画をバッチ化できるかどうかを決定するキー。
///
/// カラーはインスタンスごとのデータであり、キーには含まれません。
struct BatchKey2D: Equatable {
    /// このバッチのシェイプタイプ。
    let shapeType: Shape2DType
    /// このバッチのブレンドモード。
    let blendMode: BlendMode
}

// MARK: - 2D Instance Batcher (thin wrapper over generic InstanceBatcher)

/// Canvas2D の自動インスタンシングバッチャー。
///
/// `InstanceBatcher<InstanceData2D>` をバッチキートラッキング付きでラップします。
@MainActor
final class InstanceBatcher2D {
    private let batcher: InstanceBatcher<InstanceData2D>

    /// 進行中のバッチのバッチキー。バッチがアクティブでない場合は nil。
    private(set) var currentBatchKey: BatchKey2D?

    /// 現在のバッチに蓄積されたインスタンス数。
    var instanceCount: Int { batcher.instanceCount }

    init(device: MTLDevice) throws {
        self.batcher = try InstanceBatcher<InstanceData2D>(
            device: device, maxInstances: 65536, label: "metaphor.instance2D"
        )
    }

    func beginFrame(bufferIndex: Int) {
        batcher.beginFrame(bufferIndex: bufferIndex)
        currentBatchKey = nil
    }

    func tryAddInstance(
        key: BatchKey2D,
        transform: float4x4,
        color: SIMD4<Float>
    ) -> Bool {
        guard batcher.canAdd else { return false }

        if let currentKey = currentBatchKey {
            if currentKey != key { return false }
        } else {
            currentBatchKey = key
        }

        batcher.addInstance(InstanceData2D(transform: transform, color: color))
        return true
    }

    var currentBuffer: MTLBuffer { batcher.currentBuffer }
    var currentBufferOffset: Int { batcher.currentBufferOffset }

    func reset() {
        batcher.advanceBatch()
        currentBatchKey = nil
    }
}

// MARK: - Unit Mesh Creation

/// 初期化時に一度だけ作成される共有ユニットメッシュのファクトリ。
enum UnitMesh2D {

    /// ユニット円メッシュを作成: 32セグメントのトライアングルファン、半径0.5、原点中心。
    /// - Returns: (MTLBuffer, 頂点数) のタプル。バッファ作成に失敗した場合は nil。
    static func createCircle(device: MTLDevice, segments: Int = 32) -> (MTLBuffer, Int)? {
        var verts: [SIMD2<Float>] = []
        verts.reserveCapacity(segments * 3)
        let step = Float.pi * 2.0 / Float(segments)
        for i in 0..<segments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            verts.append(SIMD2(0, 0))
            verts.append(SIMD2(0.5 * cos(a0), 0.5 * sin(a0)))
            verts.append(SIMD2(0.5 * cos(a1), 0.5 * sin(a1)))
        }
        guard let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else { return nil }
        buf.label = "metaphor.unitCircle"
        return (buf, verts.count)
    }

    /// ユニット矩形メッシュを作成: 2三角形、[-0.5, -0.5] から [0.5, 0.5]。
    /// - Returns: (MTLBuffer, 頂点数) のタプル。バッファ作成に失敗した場合は nil。
    static func createRect(device: MTLDevice) -> (MTLBuffer, Int)? {
        let verts: [SIMD2<Float>] = [
            SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5), SIMD2(0.5, 0.5),
            SIMD2(-0.5, -0.5), SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5),
        ]
        guard let buf = device.makeBuffer(
            bytes: verts,
            length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else { return nil }
        buf.label = "metaphor.unitRect"
        return (buf, verts.count)
    }
}

// MARK: - Transform Helper

extension Canvas2D {

    /// 2Dアフィン変換（float3x3）を float4x4 に埋め込みます。
    ///
    /// ```
    /// | m00  m01  0  0 |
    /// | m10  m11  0  0 |
    /// |  0    0   1  0 |
    /// | m20  m21  0  1 |
    /// ```
    static func embed2DTransform(_ t: float3x3) -> float4x4 {
        float4x4(columns: (
            SIMD4<Float>(t.columns.0.x, t.columns.0.y, 0, 0),
            SIMD4<Float>(t.columns.1.x, t.columns.1.y, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.columns.2.x, t.columns.2.y, 0, 1)
        ))
    }
}
