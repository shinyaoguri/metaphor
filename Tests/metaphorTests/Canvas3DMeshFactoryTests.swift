import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `createBoxMesh` などプリミティブメッシュ生成 API の契約を固定する（Issue #443）。
///
/// この API は「描画側のプリミティブ（`box` / `sphere` / …）と同じ引数で、同じジオメトリを
/// **値として**取り出す」ためのもの。したがってテストの軸は一貫して
/// 「`createXxxMesh` + `mesh()` が対応する描画プリミティブと同じ絵になるか」に置く。
/// あわせてキャッシュの同一性（同じ引数 → 同一インスタンス）も固定する。
@Suite("Canvas3D プリミティブメッシュ生成", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DMeshFactoryTests {

    private static let size = 128

    // MARK: - ハーネス

    /// `Canvas3DInstancedTests` と同じ結線でオフスクリーン 1 フレームを描き、全画素を読み戻す。
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

    /// 生成 API だけを使いたいテスト用に、描画せずコンテキストを組む。
    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    /// 白 fill・ライトありの共通シーン設定（画面中央へ移動した状態で戻る）。
    private func setupScene(_ c: SketchContext) {
        c.background(Color(r: 0, g: 0, b: 0))
        c.noStroke()
        c.ambientLight(60)
        c.directionalLight(-0.3, 0.8, -0.5)
        c.fill(Color(r: 0.9, g: 0.9, b: 0.9))
        c.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        c.rotateX(0.5)
        c.rotateY(0.7)
    }

    /// 非黒画素の個数を数えます。
    private func nonBlackCount(_ image: GoldenImage) -> Int {
        var count = 0
        for i in stride(from: 0, to: image.rgba.count, by: 4) {
            if image.rgba[i] > 8 || image.rgba[i + 1] > 8 || image.rgba[i + 2] > 8 { count += 1 }
        }
        return count
    }

    /// 「生成 → `mesh()`」と「描画プリミティブ直呼び」を同じシーンで描き比べます。
    private func expectSameAsPrimitive(
        _ label: String,
        create: @escaping (SketchContext) -> Mesh?,
        primitive: @escaping (SketchContext) -> Void
    ) throws {
        let direct = try render { c in
            setupScene(c)
            primitive(c)
        }
        let viaMesh = try render { c in
            setupScene(c)
            guard let mesh = create(c) else {
                Issue.record("\(label): メッシュを生成できなかった")
                return
            }
            c.mesh(mesh)
        }

        #expect(nonBlackCount(direct) > 100,
                "\(label): 基準側が何も描けていない（nonBlack=\(nonBlackCount(direct))）")
        let comparison = viaMesh.compare(to: direct)
        #expect(comparison.isIdentical, "\(label): 描画プリミティブと不一致: \(comparison.summary)")
    }

    // MARK: - 描画プリミティブとの同値性

    @Test("createBoxMesh + mesh() は box() と同一画素")
    func boxMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "box",
            create: { $0.createBoxMesh(40, 24, 32) },
            primitive: { $0.box(40, 24, 32) }
        )
    }

    @Test("createSphereMesh + mesh() は sphere() と同一画素")
    func sphereMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "sphere",
            create: { $0.createSphereMesh(34, detail: 20) },
            primitive: { $0.sphere(34, detail: 20) }
        )
    }

    @Test("createPlaneMesh + mesh() は plane() と同一画素")
    func planeMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "plane",
            create: { $0.createPlaneMesh(56, 40) },
            primitive: { $0.plane(56, 40) }
        )
    }

    @Test("createCylinderMesh + mesh() は cylinder() と同一画素")
    func cylinderMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "cylinder",
            create: { $0.createCylinderMesh(radius: 26, height: 50, detail: 18) },
            primitive: { $0.cylinder(radius: 26, height: 50, detail: 18) }
        )
    }

    @Test("createConeMesh + mesh() は cone() と同一画素")
    func coneMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "cone",
            create: { $0.createConeMesh(radius: 28, height: 48, detail: 18) },
            primitive: { $0.cone(radius: 28, height: 48, detail: 18) }
        )
    }

    @Test("createTorusMesh + mesh() は torus() と同一画素")
    func torusMatchesPrimitive() throws {
        try expectSameAsPrimitive(
            "torus",
            create: { $0.createTorusMesh(ringRadius: 34, tubeRadius: 12, detail: 20) },
            primitive: { $0.torus(ringRadius: 34, tubeRadius: 12, detail: 20) }
        )
    }

    // MARK: - キャッシュの同一性

    @Test("同じ引数の再呼び出しは同一インスタンスを返す")
    func sameArgumentsReturnSameInstance() throws {
        let c = try makeContext()

        let box1 = try #require(c.createBoxMesh(10, 20, 30))
        let box2 = try #require(c.createBoxMesh(10, 20, 30))
        #expect(box1 === box2, "box: 同じ引数で別インスタンスが返った")

        let sphere1 = try #require(c.createSphereMesh(12, detail: 16))
        let sphere2 = try #require(c.createSphereMesh(12, detail: 16))
        #expect(sphere1 === sphere2, "sphere: 同じ引数で別インスタンスが返った")

        let torus1 = try #require(c.createTorusMesh(ringRadius: 8, tubeRadius: 3))
        let torus2 = try #require(c.createTorusMesh(ringRadius: 8, tubeRadius: 3))
        #expect(torus1 === torus2, "torus: 同じ引数で別インスタンスが返った")
    }

    @Test("引数が違えば別インスタンスになる（寸法も detail も鍵に入る）")
    func differentArgumentsReturnDifferentInstances() throws {
        let c = try makeContext()

        let a = try #require(c.createBoxMesh(10, 20, 30))
        let b = try #require(c.createBoxMesh(10, 20, 31))
        #expect(a !== b, "寸法違いが同一インスタンスになった")

        let coarse = try #require(c.createSphereMesh(12, detail: 8))
        let fine = try #require(c.createSphereMesh(12, detail: 32))
        #expect(coarse !== fine, "detail 違いが同一インスタンスになった")
        #expect(coarse.vertexCount < fine.vertexCount, "detail を上げても頂点が増えていない")
    }

    @Test("createBoxMesh(size) は createBoxMesh(size, size, size) と同じメッシュ")
    func cubeOverloadSharesCache() throws {
        let c = try makeContext()
        let cube = try #require(c.createBoxMesh(16))
        let explicit = try #require(c.createBoxMesh(16, 16, 16))
        #expect(cube === explicit)
    }

    @Test("生成したメッシュには寸法が焼き込まれている（描画側の単位メッシュとは別物）")
    func bakesDimensionsIntoGeometry() throws {
        // 描画側 box() は "box_unit"（±0.5 の単位メッシュ）をキャッシュし、寸法は変換へ畳み込む。
        // 生成側が鍵を共有していると単位メッシュがそのまま返り、mesh() は 1×1×1 を描いてしまう。
        // 返ってきた頂点そのものを見て、寸法が入っていることを確かめる
        let c = try makeContext()
        let mesh = try #require(c.createBoxMesh(40, 24, 32))
        let (minP, maxP) = boundingBox(of: mesh)

        #expect(abs(maxP.x - 20) < 1e-5 && abs(minP.x + 20) < 1e-5, "x 幅が 40 でない: \(minP.x)…\(maxP.x)")
        #expect(abs(maxP.y - 12) < 1e-5 && abs(minP.y + 12) < 1e-5, "y 高さが 24 でない: \(minP.y)…\(maxP.y)")
        #expect(abs(maxP.z - 16) < 1e-5 && abs(minP.z + 16) < 1e-5, "z 奥行きが 32 でない: \(minP.z)…\(maxP.z)")
    }

    /// メッシュの頂点バッファを読み、AABB を返します。
    private func boundingBox(of mesh: Mesh) -> (SIMD3<Float>, SIMD3<Float>) {
        let vertices = mesh.vertexBuffer.contents()
            .bindMemory(to: Vertex3D.self, capacity: mesh.vertexCount)
        var minP = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<mesh.vertexCount {
            minP = simd_min(minP, vertices[i].position)
            maxP = simd_max(maxP, vertices[i].position)
        }
        return (minP, maxP)
    }

    // MARK: - 生成されたメッシュの素性

    @Test("生成したメッシュは UV を持つ（texture() が効く）")
    func generatedMeshesHaveUVs() throws {
        let c = try makeContext()
        #expect(try #require(c.createBoxMesh(10)).hasUVs)
        #expect(try #require(c.createSphereMesh(10)).hasUVs)
        #expect(try #require(c.createPlaneMesh(10, 10)).hasUVs)
        #expect(try #require(c.createCylinderMesh(radius: 5, height: 10)).hasUVs)
        #expect(try #require(c.createConeMesh(radius: 5, height: 10)).hasUVs)
        #expect(try #require(c.createTorusMesh(ringRadius: 8, tubeRadius: 3)).hasUVs)
    }

    @Test("生成したメッシュを drawInstanced に渡せる（手書きループと同一画素）")
    func feedsDrawInstanced() throws {
        let transforms: [float4x4] = [
            float4x4(translation: SIMD3(-24, 0, 0)),
            float4x4(translation: SIMD3(24, 0, 0)) * float4x4(rotationY: 0.7),
        ]

        let loop = try render { c in
            setupScene(c)
            guard let mesh = c.createBoxMesh(20) else {
                Issue.record("メッシュを生成できなかった")
                return
            }
            for t in transforms {
                c.pushMatrix()
                c.applyMatrix(t)
                c.mesh(mesh)
                c.popMatrix()
            }
        }
        let instanced = try render { c in
            setupScene(c)
            guard let mesh = c.createBoxMesh(20) else {
                Issue.record("メッシュを生成できなかった")
                return
            }
            c.drawInstanced(mesh, transforms: transforms)
        }

        #expect(nonBlackCount(loop) > 100, "基準側が何も描けていない")
        #expect(instanced.compare(to: loop).isIdentical,
                "drawInstanced と手書きループが不一致: \(instanced.compare(to: loop).summary)")
    }
}
