import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `begin()` を挟んで「フレーム開始で既定に戻る状態」と「フレームを跨ぐ状態」の
/// 線引きを実測で固定する（Issue #1149）。
///
/// ## なぜこのテストがあるか
///
/// 線引きの正典は ``Canvas3D/begin(encoder:time:bufferIndex:)``（`Canvas3D+Frame.swift`）と
/// ``Canvas2D/begin(encoder:bufferIndex:)``（`Canvas2D.swift`）の**実装だけ**で、
/// `Sketch+3D.swift` の doc コメント（→ `llms.txt` の `Resets every frame.` /
/// `Survives across frames.`）と `llms-sketch.txt` の一覧表はその写しにすぎない。
///
/// `begin()` にリセットを 1 行足す／消すのは軽い変更に見えるので doc を直し忘れるほうが
/// 自然で、しかもそのずれは**エラーにも警告にもならず絵だけが黙って変わる**。
/// #1098（`setup()` の `perspective()` が効かない）はまさにその形で、
/// このテストを入れる前は `self.fov = Canvas3D.defaultFov` を消しても
/// 既存の 2159 件が 1 件も落ちなかった。
///
/// ## 赤くなったら
///
/// `begin()` のリセットを意図して変えたのなら、**同じ PR で**
/// `Sketch+3D.swift` の callout と `llms-sketch.txt` の一覧表も更新すること
/// （`llms.txt` は `make llms-txt` で再生成する生成物）。
///
/// ## 網羅の方針
///
/// 「1 行消しても鳴らない」を塞ぐのが目的なので、`begin()` が触る項目は原則すべて
/// 個別に assert する。テストごとに **消えると落ちるリセット行**を対応づけてあるので、
/// 落ちたテスト名から `begin()` の該当行へ直接辿れる。
@Suite("Frame state reset (begin())", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct FrameStateResetTests {

    // MARK: - 3D: フレーム開始で既定に戻る側

    /// 守る行: `cameraEye` / `cameraCenter` / `cameraUp` / `viewProjectionDirty`
    @Test("camera() は begin() で既定のピクセル空間ビューへ戻る")
    func cameraResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.camera(eye: SIMD3(10, 20, 30), center: SIMD3(1, 2, 3), up: SIMD3(1, 0, 0))

        canvas.begin(encoder: nil, time: 0)

        let z = canvas.defaultCameraZ
        #expect(canvas.cameraEye == SIMD3(canvas.width / 2, canvas.height / 2, z))
        #expect(canvas.cameraCenter == SIMD3(canvas.width / 2, canvas.height / 2, 0))
        #expect(canvas.cameraUp == SIMD3<Float>(0, 1, 0))
        #expect(canvas.viewProjectionDirty)
    }

    /// 守る行: `fov` / `nearPlane` / `farPlane`（#1098 を再発させないための本丸）
    @Test("perspective() は begin() で既定の投影へ戻る（#1098）")
    func perspectiveResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.perspective(fov: 0.5, near: 5, far: 50)

        canvas.begin(encoder: nil, time: 0)

        let z = canvas.defaultCameraZ
        #expect(canvas.fov == Canvas3D.defaultFov)
        #expect(canvas.nearPlane == z / 10)
        #expect(canvas.farPlane == z * 10)
    }

    /// 守る行: `useOrthographic = false`（+ near/far の戻り）
    @Test("ortho() は begin() で透視投影へ戻る")
    func orthoResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.ortho()
        #expect(canvas.useOrthographic, "前提: ortho() が平行投影へ切り替えている")

        canvas.begin(encoder: nil, time: 0)

        #expect(!canvas.useOrthographic)
        let z = canvas.defaultCameraZ
        #expect(canvas.nearPlane == z / 10)
        #expect(canvas.farPlane == z * 10)
    }

    /// 守る行: `lightArray.removeAll(keepingCapacity:)`
    @Test("ライトは begin() で空になる")
    func lightsReset() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.directionalLight(0, -1, 0)
        canvas.pointLight(1, 2, 3)
        #expect(!canvas.lightArray.isEmpty, "前提: ライトが積まれている")

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.lightArray.isEmpty)
    }

    /// 守る行: `ambientColor = SIMD3(0.2, 0.2, 0.2)` / `userSetAmbient = false`
    @Test("ambientLight() は begin() で既定へ戻る")
    func ambientLightResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.ambientLight(200)
        #expect(canvas.userSetAmbient, "前提: 明示指定の印が立っている")

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.ambientColor == SIMD3<Float>(0.2, 0.2, 0.2))
        #expect(!canvas.userSetAmbient)
    }

    /// 守る行: `currentMaterial = .default`
    ///
    /// `toneMapParams` だけは画面全体の性質なので比較から外す（`toneMappingAndExposureSurvive`
    /// が「戻らないこと」を別途固定している）。
    @Test("マテリアルは begin() で既定へ戻る（toneMapParams を除く）")
    func materialResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.specular(1, 0.5, 0.25)
        canvas.shininess(64)
        canvas.emissive(0.1, 0.2, 0.3)
        canvas.metallic(0.9)
        canvas.roughness(0.1)
        canvas.ambientOcclusion(0.25)
        canvas.pbr(true)

        canvas.begin(encoder: nil, time: 0)

        let expected = Material3D.default
        #expect(canvas.currentMaterial.ambientColor == expected.ambientColor)
        #expect(canvas.currentMaterial.specularAndShininess == expected.specularAndShininess)
        #expect(canvas.currentMaterial.emissiveAndMetallic == expected.emissiveAndMetallic)
        #expect(canvas.currentMaterial.pbrParams == expected.pbrParams)
    }

    /// 守る行: `currentTexture = nil`
    @Test("texture() は begin() で外れる")
    func textureResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        let texture = try #require(MetalTestHelper.makeTexture())
        canvas.texture(MImage(texture: texture))
        #expect(canvas.currentTexture != nil, "前提: テクスチャが束縛されている")

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.currentTexture == nil)
    }

    /// 守る行: `currentCustomMaterial = nil`
    @Test("material(CustomMaterial) は begin() で外れる")
    func customMaterialResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.material(try Self.probeMaterial(on: canvas))
        #expect(canvas.currentCustomMaterial != nil, "前提: カスタムマテリアルが載っている")

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.currentCustomMaterial == nil)
    }

    /// 守る行: `currentTransform = .identity` / `stateStack` / `styleOnlyStack` / `matrixStack`
    ///
    /// スタックは「不均衡な push が残っていてもフレームを跨いで無限成長しない」ための破棄。
    @Test("3D の変換とスタックは begin() で破棄される")
    func transformAndStacksReset() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.pushState()
        canvas.pushMatrix()
        canvas.pushStyle()
        canvas.translate(10, 20, 30)
        #expect(canvas.currentTransform != float4x4.identity, "前提: 変換が入っている")

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.currentTransform == float4x4.identity)
        #expect(canvas.stateStack.isEmpty)
        #expect(canvas.styleOnlyStack.isEmpty)
        #expect(canvas.matrixStack.isEmpty)
    }

    /// 守る行: `currentTime` / `recordedDrawCalls` / `skyboxDrawnThisFrame` /
    /// `meshCacheFrameCounter` / `shapeVertexBufferIndex` / `shapeVertexBufferUsed`
    @Test("3D のフレーム記録とバッファカーソルは begin() で更新される")
    func frameBookkeepingResets() throws {
        let canvas = try MetalTestHelper.canvas3D()
        let mesh = try #require(canvas.createBoxMesh(10))
        canvas.recordedDrawCalls.append(
            DrawCall3D(
                mesh: mesh,
                transform: .identity,
                fillColor: SIMD4(1, 1, 1, 1),
                material: .default,
                customMaterial: nil,
                texture: nil,
                isTextured: false,
                hasFill: true,
                hasStroke: false,
                strokeColor: SIMD4(1, 1, 1, 1)
            )
        )
        canvas.skyboxDrawnThisFrame = true
        canvas.shapeVertexBufferUsed = 128
        let meshCounterBefore = canvas.meshCacheFrameCounter

        canvas.begin(encoder: nil, time: 1.5, bufferIndex: 2)

        #expect(canvas.recordedDrawCalls.isEmpty)
        #expect(!canvas.skyboxDrawnThisFrame)
        #expect(canvas.meshCacheFrameCounter == meshCounterBefore + 1)
        #expect(canvas.shapeVertexBufferIndex == 2)
        #expect(canvas.shapeVertexBufferUsed == 0)
        #expect(canvas.currentTime == 1.5)
    }

    /// 守る行: `if environment != nil { applyDefaultAmbient() }`
    ///
    /// `currentMaterial = .default` はアンビエントを 0.2 に戻すので、環境が有効な間は
    /// 毎フレーム 0 へ焼き直さないと IBL の拡散項と二重計上になる（#710）。
    @Test("環境が有効な間、既定アンビエントは begin() ごとに 0 へ焼き直される（#710）")
    func defaultAmbientStaysZeroWhileEnvironmentIsActive() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.environment(.studio)

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.ambientColor == SIMD3<Float>.zero)
        #expect(canvas.currentMaterial.ambientColor == SIMD4<Float>(0, 0, 0, 0))
    }

    // MARK: - 3D: フレームを跨ぐ側

    /// 守る性質: `shadowMap` に `begin()` が触らないこと（`setup()` で 1 度設定すれば足りる）
    @Test("enableShadows() / shadowBias() は begin() を跨ぐ")
    func shadowStateSurvives() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.shadowMap = try ShadowMap(
            device: canvas.device, shaderLibrary: canvas.shaderLibrary, resolution: 256)
        canvas.shadowMap?.shadowBias = 0.02

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.shadowMap != nil)
        #expect(canvas.shadowMap?.shadowBias == 0.02)
    }

    /// 守る性質: `environment` / `environmentIntensity` / `environmentShowsBackground` に
    /// `begin()` が触らないこと
    @Test("environment() は begin() を跨ぐ")
    func environmentSurvives() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.environment(.sunset, intensity: 0.8, background: false)
        let baked = try #require(canvas.environment)

        canvas.begin(encoder: nil, time: 0)

        #expect(canvas.environment === baked)
        #expect(canvas.environmentIntensity == 0.8)
        #expect(!canvas.environmentShowsBackground)
    }

    /// 守る性質: `currentMaterial` の `didSet` が `toneMapParams` を現在値へ焼き直すこと（#706）
    ///
    /// `begin()` の `currentMaterial = .default` は見た目には
    /// トーンマップも露出も既定へ巻き戻しそうだが、`didSet` が焼き直すので戻らない。
    /// この 1 点が壊れると、`setup()` で設定した露出が 2 フレーム目から失われる。
    @Test("toneMapping() / exposure() は currentMaterial = .default でも巻き戻らない（#706）")
    func toneMappingAndExposureSurvive() throws {
        let canvas = try MetalTestHelper.canvas3D()
        canvas.toneMapping(.reinhard)
        canvas.exposure(2.5)

        canvas.begin(encoder: nil, time: 0)

        // 値の持ち主（Canvas3D 側）
        #expect(canvas.toneMapParams.x == Float(ToneMapMode.reinhard.rawValue))
        #expect(canvas.toneMapParams.y == 2.5)
        #expect(canvas.userSetToneMapping)
        // GPU へ運ぶ器（Material3D 側）— didSet の焼き直しが効いていること
        #expect(canvas.currentMaterial.toneMapParams.x == Float(ToneMapMode.reinhard.rawValue))
        #expect(canvas.currentMaterial.toneMapParams.y == 2.5)
    }

    // MARK: - 2D: フレーム開始で既定に戻る側

    /// 守る行: `vertexCount` / `bufferOffset` / `texturedVertexCount` /
    /// `texturedBufferOffset` / `massiveCircleBufferOffset` / `currentBoundTexture` /
    /// `texturedIsStraightAlpha` / `currentBufferIndex`
    @Test("2D の頂点カーソルとテクスチャ束縛は begin() で戻る")
    func canvas2DBuffersReset() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.vertexCount = 12
        canvas.bufferOffset = 48
        canvas.texturedVertexCount = 6
        canvas.texturedBufferOffset = 24
        canvas.massiveCircleBufferOffset = 96
        canvas.currentBoundTexture = MetalTestHelper.makeTexture()
        canvas.texturedIsStraightAlpha = true

        canvas.begin(encoder: nil, bufferIndex: 1)

        #expect(canvas.vertexCount == 0)
        #expect(canvas.bufferOffset == 0)
        #expect(canvas.texturedVertexCount == 0)
        #expect(canvas.texturedBufferOffset == 0)
        #expect(canvas.massiveCircleBufferOffset == 0)
        #expect(canvas.currentBoundTexture == nil)
        #expect(!canvas.texturedIsStraightAlpha)
        // bufferCount は 3 なので 1 % 3 == 1
        #expect(canvas.currentBufferIndex == 1)
    }

    /// 守る行: `currentTransform` / `stateStack` / `matrixStack` / `styleOnlyStack` /
    /// `frameCounter` / `hasDrawnAnything` / `backgroundCalledThisFrame` /
    /// `pendingClearColor` / `deferred2DCommands`
    @Test("2D の変換・スタック・フレームフラグは begin() で戻る")
    func canvas2DFrameStateResets() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.push()
        canvas.pushMatrix()
        canvas.pushStyle()
        canvas.translate(10, 20)
        canvas.hasDrawnAnything = true
        canvas.backgroundCalledThisFrame = true
        canvas.pendingClearColor = SIMD4(1, 0, 0, 1)
        canvas.deferred2DCommands.append(Deferred2DSlot(seq: 0, command: .setScissor(nil)))
        let frameCounterBefore = canvas.frameCounter
        #expect(canvas.currentTransform != float3x3(1), "前提: 変換が入っている")

        canvas.begin(encoder: nil, bufferIndex: 0)

        #expect(canvas.currentTransform == float3x3(1))
        #expect(canvas.stateStack.isEmpty)
        #expect(canvas.matrixStack.isEmpty)
        #expect(canvas.styleOnlyStack.isEmpty)
        #expect(!canvas.hasDrawnAnything)
        #expect(!canvas.backgroundCalledThisFrame)
        #expect(canvas.pendingClearColor == nil)
        #expect(canvas.deferred2DCommands.isEmpty)
        #expect(canvas.frameCounter == frameCounterBefore + 1)
    }

    // MARK: - 2D: フレームを跨ぐ側

    /// 守る性質: スタイル状態に `begin()` が触らないこと。
    ///
    /// Processing 互換の要（`setup()` で決めた `fill` / `stroke` が `draw()` へ引き継がれる）。
    /// ここが「戻る」に変わると、既存スケッチの絵が黙って変わる。
    @Test("2D のスタイルは begin() を跨ぐ（Processing 互換）")
    func canvas2DStyleSurvives() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.fillColor = SIMD4(0.1, 0.2, 0.3, 0.4)
        canvas.strokeColor = SIMD4(0.5, 0.6, 0.7, 0.8)
        canvas.tintColor = SIMD4(0.2, 0.4, 0.6, 1)
        canvas.strokeWeight(7)
        canvas.blendMode(.additive)
        canvas.textSize(41)
        // フォントとスタイルもフレームを跨ぐ側（#816）。
        canvas.textFont("Menlo")
        canvas.textStyle(.bold)
        canvas.currentStrokeCap = .square
        canvas.currentStrokeJoin = .bevel
        // 曲線の分割数とシェイプの座標解釈もスタイル状態（#813）。
        canvas.bezierDetail(7)
        canvas.curveDetail(9)
        canvas.shapeMode(.center)

        canvas.begin(encoder: nil, bufferIndex: 0)

        #expect(canvas.fillColor == SIMD4<Float>(0.1, 0.2, 0.3, 0.4))
        #expect(canvas.strokeColor == SIMD4<Float>(0.5, 0.6, 0.7, 0.8))
        #expect(canvas.tintColor == SIMD4<Float>(0.2, 0.4, 0.6, 1))
        #expect(canvas.currentStrokeWeight == 7)
        #expect(canvas.currentBlendMode == .additive)
        #expect(canvas.currentTextSize == 41)
        #expect(canvas.currentFontFamily == "Menlo")
        #expect(canvas.currentTextStyle == .bold)
        // 解決済み名まで残らないと、絵だけが黙って細字へ戻る。
        #expect(canvas.resolvedFontName == "Menlo-Bold")
        #expect(canvas.currentStrokeCap == .square)
        #expect(canvas.currentStrokeJoin == .bevel)
        #expect(canvas.bezierDetailCount == 7)
        #expect(canvas.curveDetailCount == 9)
        #expect(canvas.currentShapePositionMode == .center)
    }

    // MARK: - ヘルパー

    /// `currentCustomMaterial` を非 nil にするためだけの、最小のカスタムマテリアル。
    ///
    /// キャンバスが既に持つ ``ShaderLibrary`` を使い回す（新規に作ると組み込みシェーダーを
    /// 丸ごと再コンパイルすることになるため）。
    private static func probeMaterial(on canvas: Canvas3D) throws -> CustomMaterial {
        let key = "test.frameStateReset.probe"
        let source = """
            #include <metal_stdlib>
            using namespace metal;

            \(BuiltinShaders.canvas3DStructs)

            fragment float4 frameStateResetProbe(
                Canvas3DVertexOut in [[stage_in]],
                constant Canvas3DUniforms &uniforms [[buffer(1)]],
                constant Light3D *lights [[buffer(2)]],
                constant Material3D &material [[buffer(3)]]
            ) {
                return in.color;
            }
            """
        try canvas.shaderLibrary.register(source: source, as: key)
        let function = try #require(
            canvas.shaderLibrary.function(named: "frameStateResetProbe", from: key))
        return CustomMaterial(
            fragmentFunction: function, functionName: "frameStateResetProbe", libraryKey: key)
    }
}
