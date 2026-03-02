import metaphor
import Foundation

/// Phase A〜D の実装機能を網羅的にデモするショーケース
///
/// 数字キー 1〜8 でシーンを切り替え:
///   1: beginShape + 頂点カラー (Phase B-6)
///   2: DynamicMesh + 3D (Phase B-9)
///   3: Vec2 + randomGaussian (Phase B-7, B-12)
///   4: pushStyle/pushMatrix 分離 (Phase B-11)
///   5: Custom Shader Material (Phase C-11, Phase 5)
///   6: FBO Feedback (Phase C-14)
///   7: Orbit Camera + 3D (Phase D-20)
///   8: Tween + Post Effects (Phase 6, Phase C)
///
/// その他の操作:
///   G: GIF 録画開始/停止 (Phase D-19)
@main
final class PhaseShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "Phase A~D Showcase",
            windowScale: 1.0,
        )
    }

    // MARK: - State

    var currentScene: Int = 1

    // Scene 1: Vertex color shape
    var shapeRotation: Float = 0

    // Scene 2: DynamicMesh
    var dynamicMesh: DynamicMesh?
    var meshPhase: Float = 0

    // Scene 3: Gaussian particles
    var gaussianPoints: [Vec2] = []
    var gaussianColors: [SIMD4<Float>] = []

    // Scene 5: Custom shader
    var customMat: CustomMaterial?

    // Scene 6: FBO feedback
    var feedbackInitialized = false

    // Scene 7: Orbit camera (uses built-in orbitCamera)

    // Scene 8: Tween
    var tweenX: Float = 100
    var tweenY: Float = 360
    var tweenSize: Float = 30
    var tweenStarted = false

    // GIF recording
    var isRecordingGIF = false
    var gifFrameCount = 0

    // MARK: - Lifecycle

    func setup() {
        generateGaussianPoints()
    }

    func draw() {
        background(Color(gray: 0.08))

        // Draw current scene
        switch currentScene {
        case 1: drawScene1_VertexColors()
        case 2: drawScene2_DynamicMesh()
        case 3: drawScene3_GaussianVectors()
        case 4: drawScene4_PushStyleMatrix()
        case 5: drawScene5_CustomShader()
        case 6: drawScene6_FBOFeedback()
        case 7: drawScene7_OrbitCamera()
        case 8: drawScene8_TweenPostFX()
        default: drawScene1_VertexColors()
        }

        // HUD overlay
        drawHUD()

        // GIF capture
        if isRecordingGIF {
            gifFrameCount += 1
        }
    }

    // MARK: - Input

    func keyPressed() {
        guard let k = key else { return }

        switch k {
        case "1": currentScene = 1
        case "2":
            currentScene = 2
            setupDynamicMesh()
        case "3":
            currentScene = 3
            generateGaussianPoints()
        case "4": currentScene = 4
        case "5":
            currentScene = 5
            setupCustomShader()
        case "6":
            currentScene = 6
            if !feedbackInitialized {
                enableFeedback()
                feedbackInitialized = true
            }
        case "7": currentScene = 7
        case "8":
            currentScene = 8
            startTweens()

        // GIF record toggle (D-19)
        case "g", "G":
            toggleGIFRecord()

        default: break
        }
    }

    // =========================================================================
    // MARK: - Scene 1: beginShape + Vertex Colors (Phase B-6)
    // =========================================================================

    func drawScene1_VertexColors() {
        shapeRotation += deltaTime

        let cx = width / 2
        let cy = height / 2

        push()
        translate(cx, cy)
        rotate(shapeRotation)

        // Vertex-colored polygon
        let n = 7
        let r: Float = 200
        beginShape()
        for i in 0..<n {
            let angle = Float(i) / Float(n) * Float.pi * 2 - Float.pi / 2
            let px = r * cos(angle)
            let py = r * sin(angle)
            let hue = Float(i) / Float(n)
            let col = Color(hue: hue, saturation: 0.8, brightness: 1.0)
            vertex(px, py, col)
        }
        endShape(.close)
        pop()

        // Inner ring with UV textured vertices
        push()
        translate(cx, cy)
        rotate(-shapeRotation * 0.7)
        noFill()
        stroke(Color(r: 1, g: 1, b: 1, a: 0.5))
        strokeWeight(2)
        beginShape()
        let innerN = 12
        let innerR: Float = 100
        for i in 0...innerN {
            let angle = Float(i) / Float(innerN) * Float.pi * 2
            let px = innerR * cos(angle)
            let py = innerR * sin(angle)
            vertex(px, py)
        }
        endShape(.close)
        pop()

        drawSceneLabel("1: beginShape + Vertex Colors", "(Phase B-6)")
    }

    // =========================================================================
    // MARK: - Scene 2: DynamicMesh + 3D (Phase B-9)
    // =========================================================================

    func setupDynamicMesh() {
        guard dynamicMesh == nil else { return }
        dynamicMesh = createDynamicMesh()
    }

    func drawScene2_DynamicMesh() {
        guard let mesh = dynamicMesh else {
            setupDynamicMesh()
            return
        }

        meshPhase += deltaTime

        // Rebuild mesh each frame as a parametric surface
        mesh.clear()
        let gridSize = 20
        let spacing: Float = 20
        let offset = Float(gridSize) * spacing / 2

        for iz in 0..<gridSize {
            for ix in 0..<gridSize {
                let x = Float(ix) * spacing - offset
                let z = Float(iz) * spacing - offset
                let y = sin(x * 0.05 + meshPhase * 2) * cos(z * 0.05 + meshPhase) * 40

                let hue = (y + 40) / 80
                mesh.addVertex(x, y, z)
                mesh.addNormal(SIMD3<Float>(0, 1, 0))
                mesh.addColor(Color(hue: hue, saturation: 0.7, brightness: 0.9))

                // Create triangles
                if ix < gridSize - 1 && iz < gridSize - 1 {
                    let i0 = UInt32(iz * gridSize + ix)
                    let i1 = i0 + 1
                    let i2 = i0 + UInt32(gridSize)
                    let i3 = i2 + 1
                    mesh.addTriangle(i0, i2, i1)
                    mesh.addTriangle(i1, i2, i3)
                }
            }
        }

        // 3D rendering
        lights()
        camera(eye: SIMD3(0, 150, 300), center: SIMD3(0, 0, 0))

        push()
        rotateY(meshPhase * 0.3)
        dynamicMesh(mesh)
        pop()

        drawSceneLabel("2: DynamicMesh (Parametric Surface)", "(Phase B-9)")
    }

    // =========================================================================
    // MARK: - Scene 3: Vec2 + randomGaussian (Phase B-7, B-12)
    // =========================================================================

    func generateGaussianPoints() {
        gaussianPoints.removeAll()
        gaussianColors.removeAll()

        for _ in 0..<500 {
            let gx = randomGaussian(0, 100)
            let gy = randomGaussian(0, 100)
            let v = createVector(gx, gy)
            gaussianPoints.append(v)

            let dist = v.magnitude
            let hue = dist / 300.0
            let col = Color(hue: hue, saturation: 0.8, brightness: 1.0)
            gaussianColors.append(col.simd)
        }
    }

    func drawScene3_GaussianVectors() {
        let cx = width / 2
        let cy = height / 2

        noStroke()
        for i in 0..<gaussianPoints.count {
            let p = gaussianPoints[i]
            let c = gaussianColors[i]
            fill(Color(r: c.x, g: c.y, b: c.z, a: c.w))
            circle(cx + p.x, cy + p.y, 6)
        }

        // Show Vec2 operations
        let v1 = createVector(100, 0)
        let v2 = createVector(0, 80)
        let angle = v1.angleBetween(v2)
        let crossVal = v1.cross(v2)
        let scaled = v1.withMagnitude(150)

        // Draw vectors
        stroke(Color(r: 1, g: 0.3, b: 0.3, a: 1))
        strokeWeight(2)
        line(cx, cy, cx + scaled.x, cy + scaled.y)

        stroke(Color(r: 0.3, g: 1, b: 0.3, a: 1))
        line(cx, cy, cx + v2.x * 1.8, cy + v2.y * 1.8)

        // Info text
        fill(Color.white)
        noStroke()
        textSize(14)
        textAlign(.left, .top)
        text("angleBetween: \(String(format: "%.2f", angle)) rad", 20, height - 80)
        text("cross product: \(String(format: "%.1f", crossVal))", 20, height - 60)
        text("withMagnitude(150): (\(String(format: "%.1f", scaled.x)), \(String(format: "%.1f", scaled.y)))", 20, height - 40)

        drawSceneLabel("3: Vec2 + randomGaussian", "(Phase B-7, B-12)")
    }

    // =========================================================================
    // MARK: - Scene 4: pushStyle/pushMatrix (Phase B-11)
    // =========================================================================

    func drawScene4_PushStyleMatrix() {
        let cx = width / 2
        let cy = height / 2

        // Demonstrate style-only isolation
        fill(Color.white)
        stroke(Color.white)
        strokeWeight(1)
        textSize(16)

        // --- pushStyle demo ---
        let leftX: Float = 200
        let topY: Float = 150

        fill(Color(r: 0.3, g: 0.6, b: 1, a: 1))
        noStroke()
        text("pushStyle() / popStyle()", leftX, topY - 30)

        fill(Color(r: 0.3, g: 0.6, b: 1, a: 1))
        noStroke()
        rect(leftX, topY, 120, 80)

        pushStyle()
        fill(Color(r: 1, g: 0.3, b: 0.3, a: 1))
        stroke(Color.white)
        strokeWeight(3)
        rect(leftX + 140, topY, 120, 80)
        popStyle()

        // After popStyle: back to blue, no stroke
        rect(leftX + 280, topY, 120, 80)

        // --- pushMatrix demo ---
        let rightX = cx + 80
        fill(Color(r: 0.3, g: 1, b: 0.5, a: 1))
        noStroke()
        text("pushMatrix() / popMatrix()", rightX, topY - 30)

        let t = time

        pushMatrix()
        translate(rightX + 60, topY + 100)
        rotate(t)
        fill(Color(r: 0.3, g: 1, b: 0.5, a: 1))
        noStroke()
        rect(-30, -30, 60, 60)

        pushMatrix()
        translate(80, 0)
        rotate(t * 2)
        fill(Color(r: 1, g: 0.8, b: 0.2, a: 1))
        rect(-20, -20, 40, 40)

        pushMatrix()
        translate(50, 0)
        rotate(t * 3)
        fill(Color(r: 1, g: 0.3, b: 0.8, a: 1))
        rect(-12, -12, 24, 24)
        popMatrix()

        popMatrix()
        popMatrix()

        // --- Combined push/pop demo ---
        fill(Color(r: 0.8, g: 0.8, b: 0.2, a: 1))
        text("push() / pop() (both)", leftX, cy + 80)

        push()
        translate(leftX + 200, cy + 180)
        rotate(sin(t) * 0.5)
        fill(Color(r: 0.8, g: 0.8, b: 0.2, a: 1))
        stroke(Color.white)
        strokeWeight(2)

        for i in 0..<5 {
            push()
            let angle = Float(i) / 5.0 * Float.pi * 2 + t
            translate(cos(angle) * 80, sin(angle) * 80)
            rotate(angle)
            scale(0.5 + sin(t + Float(i)) * 0.3)
            rect(-25, -25, 50, 50)
            pop()
        }
        pop()

        drawSceneLabel("4: pushStyle / pushMatrix Isolation", "(Phase B-11)")
    }

    // =========================================================================
    // MARK: - Scene 5: Custom Shader Material (Phase C-11, Phase 5)
    // =========================================================================

    func setupCustomShader() {
        guard customMat == nil else { return }

        let shaderSrc = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        fragment float4 toonShading(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(0)]],
            constant Material3D &material [[buffer(2)]],
            constant Light3D *lights [[buffer(3)]]
        ) {
            float3 N = normalize(in.worldNormal);
            float3 lightDir = normalize(float3(-0.5, -1.0, -0.8));
            float NdotL = dot(N, -lightDir);

            // Toon shading: quantize light levels
            float toon;
            if (NdotL > 0.8) toon = 1.0;
            else if (NdotL > 0.4) toon = 0.7;
            else if (NdotL > 0.1) toon = 0.4;
            else toon = 0.2;

            float3 baseColor = in.color.rgb;
            float3 finalColor = baseColor * toon;

            // Rim light
            float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition.xyz);
            float rim = 1.0 - max(dot(viewDir, N), 0.0);
            rim = pow(rim, 3.0) * 0.5;
            finalColor += float3(0.3, 0.5, 1.0) * rim;

            return float4(finalColor, in.color.a);
        }
        """

        customMat = try? createMaterial(source: shaderSrc, fragmentFunction: "toonShading")
    }

    func drawScene5_CustomShader() {
        if customMat == nil { setupCustomShader() }

        lights()
        camera(eye: SIMD3(0, 100, 400), center: SIMD3(0, 0, 0))

        let t = time

        if let mat = customMat {
            material(mat)
        }

        // Toon-shaded spheres
        for i in 0..<5 {
            push()
            let angle = Float(i) / 5.0 * Float.pi * 2 + t * 0.5
            let x = cos(angle) * 120
            let z = sin(angle) * 120
            translate(x, sin(t + Float(i)) * 30, z)

            let hue = Float(i) / 5.0
            let col = Color(hue: hue, saturation: 0.7, brightness: 0.9)
            fill(col)
            sphere(40, detail: 32)
            pop()
        }

        // Center box
        push()
        translate(0, 0, 0)
        rotateY(t * 0.3)
        rotateX(t * 0.2)
        fill(Color(r: 0.9, g: 0.9, b: 0.9, a: 1))
        box(60)
        pop()

        drawSceneLabel("5: Custom Toon Shader Material", "(Phase C-11, Phase 5)")
    }

    // =========================================================================
    // MARK: - Scene 6: FBO Feedback (Phase C-14)
    // =========================================================================

    func drawScene6_FBOFeedback() {
        if !feedbackInitialized {
            enableFeedback()
            feedbackInitialized = true
        }

        // Draw previous frame with slight fade and offset
        if let prev = previousFrame() {
            push()
            tint(Color(r: 1, g: 1, b: 1, a: 0.92))
            translate(width / 2, height / 2)
            rotate(0.005)
            scale(1.005)
            translate(-width / 2, -height / 2)
            image(prev, 0, 0, width, height)
            pop()
            noTint()
        }

        // Draw new elements on top
        let t = time
        let cx = width / 2
        let cy = height / 2

        noStroke()
        for i in 0..<3 {
            let angle = t * 0.8 + Float(i) * Float.pi * 2 / 3
            let x = cx + cos(angle) * 200
            let y = cy + sin(angle) * 200
            let hue = fmod(t * 0.1 + Float(i) * 0.33, 1.0)
            fill(Color(hue: hue, saturation: 0.9, brightness: 1.0))
            circle(x, y, 20)
        }

        drawSceneLabel("6: FBO Feedback", "(Phase C-14) — Trails via previousFrame()")
    }

    // =========================================================================
    // MARK: - Scene 7: Orbit Camera (Phase D-20)
    // =========================================================================

    func drawScene7_OrbitCamera() {
        // orbitControl() handles mouse drag + scroll automatically
        orbitControl()

        lights()
        pointLight(200, 200, 200, color: Color(r: 1, g: 0.8, b: 0.6, a: 1))

        // Ground grid
        stroke(Color(r: 0.3, g: 0.3, b: 0.3, a: 1))
        strokeWeight(1)
        noFill()
        let gridSize: Float = 500
        let step: Float = 50
        var g = -gridSize
        while g <= gridSize {
            // Lines along X
            beginShape3D(.lines)
            vertex(-gridSize, 0, g)
            vertex(gridSize, 0, g)
            endShape3D()

            // Lines along Z
            beginShape3D(.lines)
            vertex(g, 0, -gridSize)
            vertex(g, 0, gridSize)
            endShape3D()

            g += step
        }

        // 3D objects
        let t = time
        noStroke()

        // Central sphere
        push()
        fill(Color(r: 0.8, g: 0.3, b: 0.3, a: 1))
        specular(Color(r: 1, g: 1, b: 1, a: 1))
        shininess(32)
        sphere(60, detail: 32)
        pop()

        // Orbiting boxes
        for i in 0..<6 {
            push()
            let angle = Float(i) / 6.0 * Float.pi * 2 + t * 0.4
            let r: Float = 180
            translate(cos(angle) * r, 40 + sin(t + Float(i)) * 30, sin(angle) * r)
            rotateY(t + Float(i))
            rotateX(t * 0.7)

            let hue = Float(i) / 6.0
            fill(Color(hue: hue, saturation: 0.7, brightness: 0.9))
            box(35)
            pop()
        }

        // Torus
        push()
        translate(0, 100, 0)
        rotateX(t * 0.5)
        rotateZ(t * 0.3)
        fill(Color(r: 0.9, g: 0.8, b: 0.2, a: 1))
        metallic(0.8)
        torus(ringRadius: 70, tubeRadius: 15, detail: 32)
        metallic(0)
        pop()

        // Camera info
        let cam = orbitCamera
        drawSceneLabel(
            "7: Orbit Camera (drag to rotate, scroll to zoom)",
            String(format: "(Phase D-20) — dist: %.0f  az: %.2f  el: %.2f",
                   cam.distance, cam.azimuth, cam.elevation)
        )
    }

    // =========================================================================
    // MARK: - Scene 8: Tween + Post Effects (Phase 6, Phase C)
    // =========================================================================

    func startTweens() {
        guard !tweenStarted else { return }
        tweenStarted = true
    }

    func drawScene8_TweenPostFX() {
        let t = time

        // Animated shapes using sine/easing
        let cy = height / 2

        noStroke()

        // Bouncing circles with easing-like motion
        for i in 0..<8 {
            let phase = Float(i) * 0.4
            let progress = fmod(t * 0.5 + phase, 2.0)
            let easedProgress: Float
            if progress < 1.0 {
                easedProgress = easeOutBounce(progress)
            } else {
                easedProgress = easeOutBounce(2.0 - progress)
            }

            let x = 100 + Float(i) * (width - 200) / 7.0
            let y = cy - 200 + easedProgress * 400
            let size: Float = 20 + easedProgress * 20

            let hue = Float(i) / 8.0
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
            circle(x, y, size)
        }

        // Bezier curves
        stroke(Color(r: 1, g: 1, b: 1, a: 0.4))
        strokeWeight(2)
        noFill()
        let waveAmp: Float = 80
        beginShape()
        for i in 0...60 {
            let px = Float(i) / 60.0 * width
            let py = cy + sin(Float(i) * 0.15 + t * 2) * waveAmp
            vertex(px, py)
        }
        endShape()

        // Triangle wave
        stroke(Color(r: 0.5, g: 1, b: 0.5, a: 0.3))
        beginShape()
        for i in 0...60 {
            let px = Float(i) / 60.0 * width
            let phase2 = fmod(Float(i) * 0.1 + t, 2.0)
            let tri = phase2 < 1.0 ? phase2 : 2.0 - phase2
            let py = cy + 100 + (tri - 0.5) * waveAmp * 2
            vertex(px, py)
        }
        endShape()

        drawSceneLabel("8: Easing Animation + Waveforms", "(Phase 6 Tween, Phase 2 Easing)")
    }

    // =========================================================================
    // MARK: - GIF Recording (Phase D-19)
    // =========================================================================

    func toggleGIFRecord() {
        if isRecordingGIF {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let path = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
            try? endGIFRecord(path)
            isRecordingGIF = false
            print("[GIF] Exported \(gifFrameCount) frames to \(path)")
            gifFrameCount = 0
        } else {
            beginGIFRecord(fps: 15)
            isRecordingGIF = true
            gifFrameCount = 0
            print("[GIF] Recording started...")
        }
    }

    // =========================================================================
    // MARK: - HUD
    // =========================================================================

    func drawHUD() {
        // Reset 2D state
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.6))
        rect(0, 0, width, 36)

        fill(Color.white)
        textSize(13)
        textAlign(.left, .top)
        text("Scene [\(currentScene)/8]  Keys: 1-8 scenes | G=GIF", 10, 10)

        textAlign(.right, .top)
        let fps = Int(1.0 / max(deltaTime, 0.001))
        text("\(fps) fps  frame:\(frameCount)", width - 10, 10)

        if isRecordingGIF {
            fill(Color(r: 1, g: 0.2, b: 0.2, a: 1))
            textAlign(.center, .top)
            text("REC GIF (\(gifFrameCount) frames) — press G to stop", width / 2, 10)
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    func drawSceneLabel(_ title: String, _ subtitle: String) {
        fill(Color(r: 1, g: 1, b: 1, a: 0.9))
        noStroke()
        textSize(20)
        textAlign(.center, .top)
        text(title, width / 2, 50)

        fill(Color(r: 0.6, g: 0.6, b: 0.6, a: 0.8))
        textSize(14)
        text(subtitle, width / 2, 76)
    }
}
