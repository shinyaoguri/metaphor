import metaphor

/// Phase 3 デモ: マルチライト、マテリアル、テクスチャマッピング
///
/// - 左列: ライティングデモ（directional / point / spot）
/// - 中列: マテリアルデモ（specular / emissive / metallic）
/// - 右列: ライトの色と組み合わせ
///
/// マウスX座標でスポットライトの向きが変化する
@main
final class Lighting3D: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Lighting3D — Multi-Light, Material, Texture")
    }

    func draw() {
        background(Color(gray: 0.03))

        camera(
            eye: SIMD3<Float>(0, 0, 800),
            center: .zero,
            up: SIMD3<Float>(0, 1, 0)
        )
        perspective(fov: radians(50), near: 1, far: 2000)

        let t = time

        // ── 左列: ライティング種別 ──
        drawLightingColumn(x: -350, t: t)

        // ── 中列: マテリアル ──
        drawMaterialColumn(x: 0, t: t)

        // ── 右列: カラフルなマルチライト ──
        drawMultiLightColumn(x: 350, t: t)

        // ── UI ──
        fill(Color(gray: 0.35))
        textSize(13)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Directional / Point / Spot", 20, 20)
        text("Specular / Emissive / Metallic", 20, 38)
        text("Multi-Light Color Mix", 20, 56)
    }

    // MARK: - 左列: ライト種別

    private func drawLightingColumn(x: Float, t: Float) {
        let size: Float = 70

        // 1. Directional light のみ
        pushMatrix()
        translate(x, 150, 0)
        rotateY(t * 0.5)
        rotateX(t * 0.3)

        noLights()
        directionalLight(0.5, -1, -0.7)
        ambientLight(0.15)
        fill(Color(gray: 0.85))
        sphere(size * 0.6, detail: 32)
        popMatrix()

        // 2. Point light（回転する光源）
        pushMatrix()
        translate(x, -10, 0)

        noLights()
        let px = cos(t * 1.5) * 80
        let pz = sin(t * 1.5) * 80
        pointLight(px, 30, pz, color: Color(r: 1, g: 0.9, b: 0.6), falloff: 0.005)
        ambientLight(0.05)
        fill(Color(gray: 0.9))
        sphere(size * 0.6, detail: 32)
        popMatrix()

        // 3. Spot light（マウス追従）
        pushMatrix()
        translate(x, -170, 0)

        noLights()
        let spotDirX = (input.mouseX / width - 0.5) * 2
        spotLight(0, 60, 80, spotDirX, -0.4, -1, angle: radians(35), falloff: 0.005, color: .white)
        ambientLight(0.03)
        fill(Color(r: 0.7, g: 0.85, b: 1.0))
        sphere(size * 0.6, detail: 32)
        popMatrix()
    }

    // MARK: - 中列: マテリアル

    private func drawMaterialColumn(x: Float, t: Float) {
        let size: Float = 65

        // 1. Specular（光沢）
        pushMatrix()
        translate(x, 150, 0)
        rotateY(t * 0.6)
        rotateX(0.3)

        noLights()
        directionalLight(0.5, -1, -0.8)
        ambientLight(0.15)
        specular(1.0)
        shininess(64)
        fill(Color(r: 0.2, g: 0.4, b: 0.9))
        sphere(size * 0.6, detail: 32)

        specular(0)
        popMatrix()

        // 2. Emissive（自発光）
        pushMatrix()
        translate(x, -10, 0)
        rotateY(t * 0.5)

        noLights()
        directionalLight(0, -1, -0.5)
        ambientLight(0.05)

        let pulse = (sin(t * 3) + 1) * 0.5
        emissive(Color(r: pulse * 0.8, g: pulse * 0.2, b: pulse * 0.6))
        fill(Color(gray: 0.3))
        sphere(size * 0.6, detail: 32)

        emissive(0)
        popMatrix()

        // 3. Metallic
        pushMatrix()
        translate(x, -170, 0)
        rotateY(t * 0.7)
        rotateX(0.2)

        noLights()
        directionalLight(0.3, -1, -0.6)
        pointLight(60, 40, 80, color: Color(r: 1, g: 0.95, b: 0.8), falloff: 0.005)
        ambientLight(0.1)
        metallic(0.9)
        specular(0.8)
        shininess(48)
        fill(Color(r: 1.0, g: 0.85, b: 0.4))
        sphere(size * 0.6, detail: 32)

        metallic(0)
        specular(0)
        popMatrix()
    }

    // MARK: - 右列: マルチライト

    private func drawMultiLightColumn(x: Float, t: Float) {
        let size: Float = 80

        // 3色のポイントライトが回転
        pushMatrix()
        translate(x, 0, 0)
        rotateY(t * 0.3)

        noLights()
        ambientLight(0.03)

        let orbitR: Float = 120

        // 赤
        let r0 = t * 1.2
        pointLight(
            cos(r0) * orbitR, 60, sin(r0) * orbitR,
            color: Color(r: 1, g: 0.2, b: 0.1), falloff: 0.005
        )

        // 緑
        let r1 = t * 1.2 + Float.pi * 2 / 3
        pointLight(
            cos(r1) * orbitR, -30, sin(r1) * orbitR,
            color: Color(r: 0.1, g: 1, b: 0.3), falloff: 0.005
        )

        // 青
        let r2 = t * 1.2 + Float.pi * 4 / 3
        pointLight(
            cos(r2) * orbitR, 0, sin(r2) * orbitR,
            color: Color(r: 0.2, g: 0.3, b: 1), falloff: 0.005
        )

        specular(0.6)
        shininess(32)
        fill(Color(gray: 0.9))

        // 中央の大きな球体
        sphere(size * 0.7, detail: 48)

        // 周囲の小さなボックス
        for i in 0..<6 {
            let angle = Float(i) / 6 * Float.pi * 2 + t * 0.5
            let dist: Float = 130
            pushMatrix()
            translate(cos(angle) * dist, sin(angle * 2) * 30, sin(angle) * dist)
            rotateY(t + Float(i))
            rotateX(t * 0.7)
            box(30)
            popMatrix()
        }

        specular(0)
        popMatrix()
    }
}
