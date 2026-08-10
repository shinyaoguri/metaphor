import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// 下限（segments = 3 / rings = 2）に届かない分割数。
///
/// `@Test(arguments:)` は Suite の外（nonisolated）から評価されるため、`@MainActor` な
/// Suite の static プロパティには置けない。
private let degenerateDetails = [-24, -1, 0, 1, 2]

/// プリミティブ生成の分割数が下限へ丸められることを固定する（Issue #445）。
///
/// `detail` を `@Param` / OSC / MIDI から流すと 0 や負の値が入りうる。`Mesh` のファクトリは
/// 分割数を `0...segments` で回すため、負だと逆順 Range で fatalError（`throws` では拾えない）、
/// 0 でも `Float(i) / Float(segments)` が inf/NaN になって退化ジオメトリが出ていた。
/// クランプは `Mesh` 側 1 箇所にあり、描画側（`sphere()` 等）と生成側（`createSphereMesh()` 等）の
/// 両方に効く — この Suite もその 3 経路すべてを境界値で叩く。
@Suite("プリミティブの分割数クランプ", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MeshSegmentClampTests {

    // MARK: - Mesh ファクトリ直呼び

    @Test("Mesh ファクトリは 0 以下の分割数でも落ちず、有限な頂点を返す",
          arguments: degenerateDetails)
    func meshFactoriesSurviveDegenerateSegments(detail: Int) throws {
        let device = try #require(MetalTestHelper.device)

        let meshes: [(String, Mesh)] = [
            ("sphere", try Mesh.sphere(device: device, radius: 1, segments: detail, rings: detail)),
            ("cylinder", try Mesh.cylinder(device: device, radius: 1, height: 1, segments: detail)),
            ("cone", try Mesh.cone(device: device, radius: 1, height: 1, segments: detail)),
            ("torus", try Mesh.torus(
                device: device, ringRadius: 1, tubeRadius: 0.3,
                segments: detail, tubeSegments: detail)),
        ]

        for (label, mesh) in meshes {
            #expect(mesh.vertexCount > 0, "\(label)(detail: \(detail)): 頂点が 1 つも無い")
            #expect(mesh.indexCount > 0, "\(label)(detail: \(detail)): インデックスが 1 つも無い")
            let bad = nonFinitePositionCount(of: mesh)
            #expect(bad == 0, "\(label)(detail: \(detail)): 非有限な座標が \(bad) 頂点ある（inf/NaN）")
        }
    }

    @Test("下限未満の分割数は下限へ張り付き、下限より上は素通りする")
    func clampsToMinimumAndPassesThroughAbove() throws {
        let device = try #require(MetalTestHelper.device)

        // sphere: segments = 3 / rings = 2 が下限
        let clampedSphere = try Mesh.sphere(device: device, segments: -5, rings: -5)
        let atMinimum = try Mesh.sphere(device: device, segments: 3, rings: 2)
        #expect(clampedSphere.vertexCount == atMinimum.vertexCount,
                "sphere: 下限へ張り付いていない（\(clampedSphere.vertexCount) != \(atMinimum.vertexCount)）")

        let finer = try Mesh.sphere(device: device, segments: 8, rings: 5)
        #expect(finer.vertexCount > atMinimum.vertexCount, "sphere: 下限より上の値まで丸められている")

        // cylinder / cone / torus は segments = 3 が下限
        let clampedCylinder = try Mesh.cylinder(device: device, segments: 0)
        #expect(clampedCylinder.vertexCount == (try Mesh.cylinder(device: device, segments: 3)).vertexCount,
                "cylinder: 下限へ張り付いていない")
        let clampedCone = try Mesh.cone(device: device, segments: 0)
        #expect(clampedCone.vertexCount == (try Mesh.cone(device: device, segments: 3)).vertexCount,
                "cone: 下限へ張り付いていない")
        let clampedTorus = try Mesh.torus(device: device, segments: 0, tubeSegments: 0)
        #expect(clampedTorus.vertexCount == (try Mesh.torus(device: device, segments: 3, tubeSegments: 3)).vertexCount,
                "torus: 下限へ張り付いていない")
    }

    // MARK: - 生成 API（Canvas3D 経由）

    @Test("createXxxMesh は 0 以下の detail でも nil にならず落ちない",
          arguments: degenerateDetails)
    func createMeshAPIsSurviveDegenerateDetail(detail: Int) throws {
        let c = try makeContext()

        #expect(c.createSphereMesh(50, detail: detail) != nil, "createSphereMesh(detail: \(detail))")
        #expect(c.createCylinderMesh(radius: 20, height: 40, detail: detail) != nil,
                "createCylinderMesh(detail: \(detail))")
        #expect(c.createConeMesh(radius: 20, height: 40, detail: detail) != nil,
                "createConeMesh(detail: \(detail))")
        #expect(c.createTorusMesh(ringRadius: 30, tubeRadius: 10, detail: detail) != nil,
                "createTorusMesh(detail: \(detail))")
    }

    // MARK: - 描画経路

    @Test("負の detail のプリミティブを描いてもフレームが通る")
    func drawingWithNegativeDetailRendersAFrame() throws {
        let image = try render { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.ambientLight(120)
            c.fill(Color(r: 0.9, g: 0.9, b: 0.9))
            c.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            c.sphere(30, detail: -1)
            c.cylinder(radius: 20, height: 30, detail: 0)
            c.cone(radius: 20, height: 30, detail: -8)
            c.torus(ringRadius: 40, tubeRadius: 8, detail: -3)
        }

        // 下限に丸められた粗いジオメトリでも、何かしら描けていれば十分
        #expect(nonBlackCount(image) > 0, "負の detail で 1 画素も描かれなかった")
    }

    // MARK: - ハーネス

    private static let size = 128

    /// 描画せずに生成 API だけ叩くためのコンテキスト。
    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    /// オフスクリーン 1 フレームを描いて全画素を読み戻す（`Canvas3DMeshFactoryTests` と同じ結線）。
    private func render(draw: @escaping (SketchContext) -> Void) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.useExternalRenderLoop = true
        renderer.renderFrame()
        return try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture, commandQueue: renderer.commandQueue)
    }

    /// 非黒画素の個数を数えます。
    private func nonBlackCount(_ image: GoldenImage) -> Int {
        var count = 0
        for i in stride(from: 0, to: image.rgba.count, by: 4) {
            if image.rgba[i] > 8 || image.rgba[i + 1] > 8 || image.rgba[i + 2] > 8 { count += 1 }
        }
        return count
    }

    /// 位置に inf / NaN を含む頂点の個数を数えます。
    private func nonFinitePositionCount(of mesh: Mesh) -> Int {
        let vertices = mesh.vertexBuffer.contents()
            .bindMemory(to: Vertex3D.self, capacity: mesh.vertexCount)
        var count = 0
        for i in 0..<mesh.vertexCount {
            let p = vertices[i].position
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { count += 1 }
        }
        return count
    }
}
