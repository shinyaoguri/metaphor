import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// トーンマッピングが「どの経路に、何回掛かるか」を画素で固定する（Issue #706）。
///
/// レンダーターゲットは `.bgra8Unorm`（LDR 8bit）なので、ライティング結果が 1.0 を
/// 超えるとハードクランプされ、ハイライトが白く潰れる。トーンマッピングは高輝度側を
/// 0…1 へ写像して階調を残すが、**掛かってよいのは 3D のライティング結果だけ**で、
/// 2D の描画・無照明パス・そして「二重適用」は起きてはならない。
///
/// テストの軸は理論値との一致に置く。シーンは正面を向いた面 1 枚だけなので、
/// 到達する輝度を手計算でき、式の間違いを画素 1 点で捕まえられる。
@Suite("Tone mapping", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ToneMappingTests {

    private static let size = 128

    /// 正面を向いた面の中心。ここだけを読む。
    private static let center = (x: 64, y: 64)

    // MARK: - 理論値

    /// テストシーンがトーンマップ前に到達する輝度。
    ///
    /// Blinn-Phong（既定）で `specular(0)` / `metallic` 既定 0 / `fill` 白なので、
    /// 正面（NdotL = 1）の画素は `ambient + direct` = `255/255 + 1.0` = 2.0 になる。
    private static let rawLuminance: Float = 2.0

    private static func reinhard(_ x: Float) -> Float { x / (1 + x) }

    private static func acesFilmic(_ x: Float) -> Float {
        let (a, b, c, d, e): (Float, Float, Float, Float, Float) = (2.51, 0.03, 2.43, 0.59, 0.14)
        return min(max((x * (a * x + b)) / (x * (c * x + d) + e), 0), 1)
    }

    private static func expected255(_ v: Float) -> Int { Int((v * 255).rounded()) }

    // MARK: - ハーネス

    /// `GoldenImageTests` と同じ結線でオフスクリーン 1 フレームを描き、全画素を読み戻す。
    ///
    /// - Parameters:
    ///   - shadows: `true` にすると影パスが有効になり、描画が**記録経路**を通る。
    ///     記録経路はマテリアルをスナップショットへ丸ごと保存して再生時に復元するので、
    ///     トーンマップ設定がそこで巻き戻らないことの確認に使う。
    ///   - instanceCapacity: 指定するとインスタンスバッチの容量を差し替え、2 個目以降の
    ///     3D 描画を非インスタンス（イミディエイト）経路へ落とす（#391 と同じ手）。
    ///   - inspect: 1 フレーム描画後に `Canvas3D` を検査するフック。
    private func render(
        shadows: Bool = false,
        instanceCapacity: Int? = nil,
        inspect: ((Canvas3D) -> Void)? = nil,
        draw: @escaping (SketchContext) -> Void
    ) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        if let instanceCapacity {
            try canvas3D.setInstanceCapacityForTesting(instanceCapacity)
        }
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
        renderer.onAfterDraw = { commandBuffer in
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
        renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
        renderer.onRecordFrame = { _ in
            context.beginRecordingFrame(time: 0, deltaTime: 0)
            draw(context)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, _ in
            context.replayDeferredMain(encoder: encoder, time: 0)
        }
        renderer.useExternalRenderLoop = true
        if shadows { context.enableShadows(resolution: 512) }
        renderer.renderFrame()
        inspect?(canvas3D)
        return try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture, commandQueue: renderer.commandQueue)
    }

    private func pixel(_ image: GoldenImage, _ p: (x: Int, y: Int)) -> SIMD3<Int> {
        let i = (p.y * image.width + p.x) * 4
        return SIMD3(Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
    }

    /// 正面から白色光を受ける白い面。トーンマップ前の輝度は ``rawLuminance`` = 2.0。
    ///
    /// `directionalLight(0, 0, -1)` はシェーダー内で `L = -direction` になるので
    /// カメラ側（+z）から差す光になり、手前の面の法線とちょうど揃う（NdotL = 1）。
    private func overexposedPlane(
        _ setup: @escaping (SketchContext) -> Void = { _ in }
    ) -> (SketchContext) -> Void {
        return { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.ambientLight(255)
            c.directionalLight(0, 0, -1)
            c.specular(0)
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            setup(c)
            c.pushMatrix()
            c.translate(64, 64, 0)
            c.box(80)
            c.popMatrix()
        }
    }

    // MARK: - 既定は従来どおり（オプトイン）

    @Test("既定ではトーンマップされず、1.0 超はクランプされる")
    func defaultIsNone() throws {
        let image = try render(draw: overexposedPlane())
        #expect(pixel(image, Self.center) == SIMD3(255, 255, 255))
    }

    @Test("exposure の既定 1.0 は恒等倍で、絵を変えない")
    func defaultExposureIsIdentity() throws {
        let plain = try render(draw: overexposedPlane())
        let explicit = try render(draw: overexposedPlane { $0.exposure(1.0) })
        #expect(pixel(plain, Self.center) == pixel(explicit, Self.center))
    }

    // MARK: - 白飛びが救われる

    @Test("acesFilmic は飽和させず、理論値と一致する")
    func acesFilmicMatchesFormula() throws {
        let image = try render(draw: overexposedPlane { $0.toneMapping(.acesFilmic) })
        let got = pixel(image, Self.center)
        let want = Self.expected255(Self.acesFilmic(Self.rawLuminance))  // = 233

        #expect(got.x < 255, "飽和しては階調が残らない")
        #expect(abs(got.x - want) <= 2, "got=\(got.x) want=\(want)")
        #expect(got.x == got.y && got.y == got.z, "白色光なのでチャンネル間に差は出ない")
    }

    @Test("reinhard は飽和させず、理論値と一致する")
    func reinhardMatchesFormula() throws {
        let image = try render(draw: overexposedPlane { $0.toneMapping(.reinhard) })
        let got = pixel(image, Self.center)
        let want = Self.expected255(Self.reinhard(Self.rawLuminance))  // = 170

        #expect(got.x < 255)
        #expect(abs(got.x - want) <= 2, "got=\(got.x) want=\(want)")
    }

    @Test("この輝度域では reinhard < acesFilmic < none の順に明るい")
    func modeOrdering() throws {
        let none = pixel(try render(draw: overexposedPlane()), Self.center).x
        let aces = pixel(
            try render(draw: overexposedPlane { $0.toneMapping(.acesFilmic) }), Self.center).x
        let reinhard = pixel(
            try render(draw: overexposedPlane { $0.toneMapping(.reinhard) }), Self.center).x

        #expect(reinhard < aces)
        #expect(aces < none)
    }

    @Test("toneMapping(.none) に戻すとクランプ挙動へ戻る")
    func canBeTurnedOff() throws {
        let turnedOff = try render(draw: overexposedPlane {
            $0.toneMapping(.acesFilmic)
            $0.toneMapping(.none)
        })
        let stillOn = try render(draw: overexposedPlane { $0.toneMapping(.acesFilmic) })

        #expect(pixel(turnedOff, Self.center) == SIMD3(255, 255, 255))
        // 対比を置かないと、トーンマップが一切効いていなくてもこのテストは緑になる。
        #expect(pixel(stillOn, Self.center).x < 255, "比較対象が飽和していてはテストが空回りする")
    }

    // MARK: - 二重適用が起きない

    @Test("トーンマップは 1 回だけ掛かる（PBR 経路でも二重にならない）")
    func appliedExactlyOnce() throws {
        // 統合エントリ `calculateLighting` は内部で `…Raw` を呼んでから 1 回だけ
        // トーンマップする。`calculatePBRLighting` を経由する実装に戻すと二重適用に
        // なるので、そのときの値（aces(aces(x))）とも、未適用の値（クランプ）とも
        // 明確に離れていることを見る。
        let image = try render(draw: overexposedPlane {
            $0.toneMapping(.acesFilmic)
            $0.roughness(0.5)  // PBR 分岐へ入れる
        })
        let got = pixel(image, Self.center).x
        let doubled = Self.expected255(Self.acesFilmic(Self.acesFilmic(Self.rawLuminance)))

        #expect(got > doubled + 10, "got=\(got) は二重適用値 \(doubled) と明確に離れているべき")
        #expect(got < 255, "got=\(got) — 未適用（クランプ）でもこのテストが緑にならないこと")
    }

    // MARK: - 掛からない経路

    @Test("2D の描画はトーンマップの影響を受けない")
    func twoDIsUnaffected() throws {
        let draw2D: (SketchContext) -> Void = { c in
            c.fill(Color(r: 1, g: 1, b: 1))
            c.noStroke()
            c.rect(4, 4, 24, 24)
        }
        let withoutTM = try render(draw: { c in
            self.overexposedPlane()(c)
            draw2D(c)
        })
        let withTM = try render(draw: { c in
            self.overexposedPlane { $0.toneMapping(.acesFilmic) }(c)
            draw2D(c)
        })

        let p = (x: 16, y: 16)  // 2D の矩形の内側
        #expect(pixel(withoutTM, p) == SIMD3(255, 255, 255))
        #expect(pixel(withTM, p) == pixel(withoutTM, p), "2D の色は 3D の設定で変わらない")
        // 同じフレームの 3D 側は変わっていること。これが無いと、トーンマップが
        // どこにも効いていない状態でもこのテストは緑になる。
        #expect(
            pixel(withTM, Self.center).x < pixel(withoutTM, Self.center).x,
            "3D 側は変わっているべき（テストが空回りしている）")
    }

    @Test("ライトが 1 つも無いときはトーンマップされない（無照明パス）")
    func unlitPassIsUnaffected() throws {
        let unlit: (SketchContext) -> Void = { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            c.toneMapping(.acesFilmic)
            c.pushMatrix()
            c.translate(64, 64, 0)
            c.box(80)
            c.popMatrix()
        }
        let image = try render(draw: unlit)
        #expect(pixel(image, Self.center) == SIMD3(255, 255, 255))

        // 同じ設定でライトを足すと絵は変わる = 「効かないのは無照明パスだから」であって
        // 「そもそも効いていない」わけではないことを対比で示す。
        let lit = try render(draw: overexposedPlane { $0.toneMapping(.acesFilmic) })
        #expect(pixel(lit, Self.center).x < 255)
    }

    // MARK: - 露出

    @Test("exposure はトーンマップ前に掛かり、輝度に対して単調")
    func exposureIsMonotonic() throws {
        let dim = pixel(
            try render(draw: overexposedPlane {
                $0.toneMapping(.acesFilmic)
                $0.exposure(0.5)
            }), Self.center).x
        let normal = pixel(
            try render(draw: overexposedPlane { $0.toneMapping(.acesFilmic) }), Self.center).x
        let bright = pixel(
            try render(draw: overexposedPlane {
                $0.toneMapping(.acesFilmic)
                $0.exposure(2.0)
            }), Self.center).x

        #expect(dim < normal)
        #expect(normal < bright)
    }

    @Test("exposure は .none でも掛かる")
    func exposureAppliesWithoutToneMapping() throws {
        // 露出を落とせばクランプを下回るので、値が 255 から動く。
        let image = try render(draw: overexposedPlane { $0.exposure(0.25) })
        let got = pixel(image, Self.center).x
        let want = Self.expected255(Self.rawLuminance * 0.25)  // = 128

        #expect(abs(got - want) <= 2, "got=\(got) want=\(want)")
    }

    // MARK: - 状態の寿命

    @Test("pushStyle / popStyle では巻き戻らない")
    func survivesStyleStack() throws {
        let image = try render(draw: overexposedPlane { c in
            c.pushStyle()
            c.toneMapping(.acesFilmic)
            c.popStyle()
        })
        let got = pixel(image, Self.center).x
        let want = Self.expected255(Self.acesFilmic(Self.rawLuminance))

        #expect(abs(got - want) <= 2, "popStyle で巻き戻ってはいけない: got=\(got) want=\(want)")
    }

    @Test("記録経路（影あり）でも巻き戻らない")
    func survivesRecordingPath() throws {
        let image = try render(shadows: true, draw: overexposedPlane { $0.toneMapping(.acesFilmic) })
        let got = pixel(image, Self.center).x

        #expect(got < 255, "記録経路のスナップショット復元で設定が失われてはいけない: got=\(got)")
    }

    // MARK: - カスタムマテリアル

    @Test("calculateLighting を呼ぶカスタムマテリアルにも効く")
    func appliesToCustomMaterial() throws {
        // カスタムマテリアルは組み込みシェーダーを通らないが、`calculateLighting` の
        // シグネチャを変えずに Material3D で運んでいるので、ユーザーのシェーダーでも
        // 何もしなくてもトーンマップが効く。この設計の核心なので画素で固定する。
        let source = """
            #include <metal_stdlib>
            using namespace metal;

            \(BuiltinShaders.canvas3DStructs)
            \(BuiltinShaders.canvas3DLightingFn)

            fragment float4 toneMapCustomFragment(
                Canvas3DVertexOut in [[stage_in]],
                constant Canvas3DUniforms &uniforms [[buffer(1)]],
                constant Light3D *lights [[buffer(2)]],
                constant Material3D &material [[buffer(3)]]
            ) {
                float3 lit = calculateLighting(
                    in.worldPosition, in.normal, uniforms.cameraPosition.xyz,
                    in.color.rgb, lights, uniforms.lightCount, material);
                return float4(lit, in.color.a);
            }
            """

        // draw クロージャは throws を投げられないので、生成できたかを外へ持ち出して
        // 「失敗を握りつぶしたまま緑になる」のを防ぐ。
        final class Applied: @unchecked Sendable { var value = false }
        let applied = Applied()
        var immediateDraws = 0

        // カスタムフラグメントが `Canvas3DUniforms` を読む形なので、非インスタンス
        // （イミディエイト）経路へ落とす。インスタンス経路の uniforms は
        // `InstancedSceneUniforms` で別レイアウトのため、混ぜると読み違える。
        let image = try render(
            instanceCapacity: 1,
            inspect: { immediateDraws = $0.immediateDrawCountForTesting },
            draw: overexposedPlane { c in
                c.toneMapping(.acesFilmic)
                if let custom = try? c.createMaterial(
                    source: source, fragmentFunction: "toneMapCustomFragment"
                ) {
                    c.material(custom)
                    applied.value = true
                }
                // 容量 1 のバッチをここで使い切り、続く本命を即時経路へ送る。
                c.pushMatrix()
                c.translate(-1000, 0, 0)
                c.box(1)
                c.popMatrix()
            })
        #expect(applied.value, "カスタムマテリアルを生成できていない（テストが空回りしている）")
        #expect(immediateDraws > 0, "本命が即時経路を通っていない（テストが空回りしている）")

        let got = pixel(image, Self.center).x
        let want = Self.expected255(Self.acesFilmic(Self.rawLuminance))

        #expect(abs(got - want) <= 2, "got=\(got) want=\(want)")
    }
}
