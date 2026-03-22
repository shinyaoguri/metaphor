import metaphor

/// Metal ネイティブ Ray Tracing の動作確認サンプル。
///
/// `MPSRayTracer` が提供する3つのレイトレーシングモードを同一シーンに対して実行し、
/// 結果を横に並べて比較表示します。床・箱・球・円柱で構成されたシーンが
/// ゆっくり回転し、各モードの特性の違いがリアルタイムで確認できます。
///
/// ## レイトレーシングモード
///
/// ### Ambient Occlusion（左）
/// 各ピクセルの表面から半球方向にランダムなレイを飛ばし、
/// 近くに他のジオメトリがあるかどうかで「遮蔽度」を計算します。
/// 隙間や角、物体が密集した部分が暗くなり、空間的な奥行き感が生まれます。
/// ライトの位置に依存せず、形状だけで陰影が決まるのが特徴です。
/// - `samples`: レイの本数。多いほど滑らかだがGPU負荷が増える（8で粗い粒状、64で滑らか）
/// - `radius`: 遮蔽を検出する範囲。小さいと細かい隙間だけ、大きいと広い範囲の遮蔽が出る
///
/// ### Soft Shadow（中央）
/// 一次レイでヒットした点から光源方向にシャドウレイを飛ばし、
/// 遮蔽物があれば影、なければ明るいと判定します。
/// 光源方向にランダムなジッターを加えることで、影の境界がぼやけた
/// ソフトシャドウになります。ディフューズ照明と組み合わせて出力されます。
/// - `lightDirection`: 平行光源の方向ベクトル
/// - `softness`: ジッター量。0で硬い影、大きくするほど柔らかい影
/// - `samples`: シャドウレイの本数。多いほど影の境界が滑らか
///
/// ### Diffuse（右）
/// 最もシンプルなモード。一次レイの交差点の面法線と光源方向の内積で
/// ランバート拡散反射を計算します。サンプリングは不要で1パスで完了するため
/// 最も高速です。形状の明暗がはっきり出ますが、影や遮蔽の表現はありません。
///
/// ## キー操作
/// - `1`: AO モード全画面
/// - `2`: Soft Shadow モード全画面
/// - `3`: Diffuse モード全画面
/// - `0`: 3分割表示に戻す
@main
final class RayTracingDemo: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 960, height: 320, title: "Ray Tracing — AO / Shadow / Diffuse")
    }

    // 3モード分のレイトレーサー
    var rtAO: MPSRayTracer!
    var rtShadow: MPSRayTracer!
    var rtDiffuse: MPSRayTracer!

    // 表示モード（0: 3分割, 1-3: 個別全画面）
    var displayMode: Int = 0

    // アニメーション用角度
    var angle: Float = 0

    func setup() {
        do {
            let size = 500
            rtAO = try createRayTracer(width: size, height: size)
            rtShadow = try createRayTracer(width: size, height: size)
            rtDiffuse = try createRayTracer(width: size, height: size)
        } catch {
            print("Ray tracer init failed: \(error)")
        }

        frameRate(30)
        renderScene()
    }

    func draw() {
        background(30)

        // ゆっくり回転してレンダリング更新
        angle += 0.02
        renderScene()

        // 結果テクスチャを画面に描画

        switch displayMode {
        case 1:
            if let tex = rtAO.outputTexture {
                let img = MImage(texture: tex)
                image(img, 0, 0, Float(width), Float(height))
            }
        case 2:
            if let tex = rtShadow.outputTexture {
                let img = MImage(texture: tex)
                image(img, 0, 0, Float(width), Float(height))
            }
        case 3:
            if let tex = rtDiffuse.outputTexture {
                let img = MImage(texture: tex)
                image(img, 0, 0, Float(width), Float(height))
            }
        default:
            // 3分割表示
            let w = Float(width) / 3.0
            let h = Float(height)

            if let tex = rtAO.outputTexture {
                let img = MImage(texture: tex)
                image(img, 0, 0, w, h)
            }
            if let tex = rtShadow.outputTexture {
                let img = MImage(texture: tex)
                image(img, w, 0, w, h)
            }
            if let tex = rtDiffuse.outputTexture {
                let img = MImage(texture: tex)
                image(img, w * 2, 0, w, h)
            }

            // ラベル
            fill(255)
            textSize(14)
            text("AO", 10, 20)
            text("Soft Shadow", w + 10, 20)
            text("Diffuse", w * 2 + 10, 20)
        }
    }

    func keyPressed() {
        switch key {
        case "1": displayMode = 1
        case "2": displayMode = 2
        case "3": displayMode = 3
        case "0": displayMode = 0
        default: break
        }
    }

    // MARK: - シーン構築とトレース

    private func renderScene() {
        guard let rtAO, let rtShadow, let rtDiffuse else { return }

        let dev = context.renderer.device

        // シーンを毎フレーム再構築（回転アニメーション）
        rtAO.clearScene()
        rtShadow.clearScene()
        rtDiffuse.clearScene()

        // 床
        do {
            let floor = try Mesh.box(device: dev, width: 6, height: 0.2, depth: 6)
            let floorTransform = float4x4(translation: SIMD3<Float>(0, -1.1, 0))
            rtAO.addMesh(floor, transform: floorTransform)
            rtShadow.addMesh(floor, transform: floorTransform)
            rtDiffuse.addMesh(floor, transform: floorTransform)
        } catch {}

        // 中央の箱（回転）
        do {
            let box = try Mesh.box(device: dev, width: 1.2, height: 1.2, depth: 1.2)
            let boxTransform = float4x4(rotationY: angle) * float4x4(rotationX: angle * 0.7)
            rtAO.addMesh(box, transform: boxTransform)
            rtShadow.addMesh(box, transform: boxTransform)
            rtDiffuse.addMesh(box, transform: boxTransform)
        } catch {}

        // 左の球体
        do {
            let sphere = try Mesh.sphere(device: dev, radius: 0.6, segments: 24)
            let sphereTransform = float4x4(translation: SIMD3<Float>(-1.8, 0, 0))
            rtAO.addMesh(sphere, transform: sphereTransform)
            rtShadow.addMesh(sphere, transform: sphereTransform)
            rtDiffuse.addMesh(sphere, transform: sphereTransform)
        } catch {}

        // 右の円柱
        do {
            let cylinder = try Mesh.cylinder(device: dev, radius: 0.5, height: 1.5, segments: 20)
            let cylTransform = float4x4(translation: SIMD3<Float>(1.8, -0.35, 0))
            rtAO.addMesh(cylinder, transform: cylTransform)
            rtShadow.addMesh(cylinder, transform: cylTransform)
            rtDiffuse.addMesh(cylinder, transform: cylTransform)
        } catch {}

        // アクセラレーション構造ビルド
        do {
            try rtAO.buildAccelerationStructure()
            try rtShadow.buildAccelerationStructure()
            try rtDiffuse.buildAccelerationStructure()
        } catch {
            print("Accel build failed: \(error)")
            return
        }

        // カメラ設定
        let camera = (
            eye: SIMD3<Float>(0, 2.5, 5),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0),
            fov: Float.pi / 3
        )

        // 各モードでトレース
        rtAO.trace(mode: .ambientOcclusion(samples: 64, radius: 2.0), camera: camera)
        rtShadow.trace(mode: .softShadow(lightDirection: SIMD3(1, 2, 1), softness: 0.15, samples: 32), camera: camera)
        rtDiffuse.trace(mode: .diffuse, camera: camera)
    }
}
