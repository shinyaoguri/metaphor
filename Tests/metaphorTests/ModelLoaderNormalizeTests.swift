import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `loadModel(_:normalize:)` の正規化が座標へ何をするかを固定する（Issue #604）。
///
/// 既定の `normalize: true` はモデルを **原点中心・最大辺 2 単位（[-1, 1]）** へ収める。
/// これは Sketch 層の doc コメントが利用者へ約束している契約で、破ると
/// `Examples/Basics/Shape/LoadDisplayOBJ` のように「読み込みは成功しているのに小さすぎて
/// 見えない」絵が黙って生まれる（`loadModel()` が nil を返さないためフォールバックも走らない）。
@Suite("モデル読み込みの正規化", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ModelLoaderNormalizeTests {

    /// x span 70 / y span 20 / z span 10 の直方体。最大辺は x なので、正規化後は x が ±1 になる。
    private static let boxOBJ = """
        v -35 -10 -5
        v 35 -10 -5
        v 35 10 -5
        v -35 10 -5
        v -35 -10 5
        v 35 -10 5
        v 35 10 5
        v -35 10 5
        f 1 2 3
        f 1 3 4
        f 5 6 7
        f 5 7 8
        f 1 2 6
        f 1 6 5
        f 2 3 7
        f 2 7 6
        f 3 4 8
        f 3 8 7
        f 4 1 5
        f 4 5 8
        """

    private static let sourceSpan = SIMD3<Float>(70, 20, 10)

    // MARK: - ハーネス

    /// 上の OBJ を一時ファイルへ書いて読み込み、頂点位置の bounding box を返す。
    private func loadBounds(normalize: Bool) throws -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let device = try #require(MetalTestHelper.device)
        return try TempFileHelper.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("box.obj")
            try Self.boxOBJ.write(to: url, atomically: true, encoding: .utf8)

            let mesh = try ModelIOLoader.load(device: device, url: url, normalize: normalize)
            let ptr = mesh.vertexBuffer.contents()
                .bindMemory(to: Vertex3D.self, capacity: mesh.vertexCount)
            let vertices = UnsafeBufferPointer(start: ptr, count: mesh.vertexCount)

            var lo = vertices[0].position
            var hi = vertices[0].position
            for v in vertices {
                lo = min(lo, v.position)
                hi = max(hi, v.position)
            }
            return (lo, hi)
        }
    }

    // MARK: - テスト

    @Test("既定の正規化はモデルを原点中心・最大辺 2 単位へ収める")
    func normalizeFitsIntoUnitCube() throws {
        let (lo, hi) = try loadBounds(normalize: true)

        // 最大辺（x）がちょうど 2 単位 = [-1, 1]。
        #expect(abs((hi.x - lo.x) - 2) < 1e-4)
        // どの軸も [-1, 1] からはみ出さない。
        #expect(lo.min() >= -1 - 1e-4)
        #expect(hi.max() <= 1 + 1e-4)
        // 中心が原点にある。
        for axis in 0..<3 {
            #expect(abs((lo[axis] + hi[axis]) / 2) < 1e-4)
        }
    }

    @Test("正規化は等方スケールなので軸の比が変わらない")
    func normalizeKeepsAspectRatio() throws {
        let (lo, hi) = try loadBounds(normalize: true)
        let span = hi - lo
        // 最大辺が 2 になるスケール（2/70）が全軸へ等しく掛かる。
        let scale = 2 / Self.sourceSpan.x
        for axis in 0..<3 {
            #expect(abs(span[axis] - Self.sourceSpan[axis] * scale) < 1e-4)
        }
    }

    @Test("normalize: false はモデルの座標をそのまま保つ")
    func withoutNormalizeKeepsSourceCoordinates() throws {
        let (lo, hi) = try loadBounds(normalize: false)
        let span = hi - lo
        for axis in 0..<3 {
            #expect(abs(span[axis] - Self.sourceSpan[axis]) < 1e-4)
        }
        #expect(abs(lo.x - -35) < 1e-4)
        #expect(abs(hi.x - 35) < 1e-4)
    }
}
