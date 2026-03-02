import metaphor
import Foundation

/// 次世代実装 (Phase 1-8) の機能をデモするショーケース
///
/// 数字キー 1〜5 でシーンを切り替え:
///   1: PBR マテリアル (Phase 2-1)
///   2: シャドウマッピング (Phase 2-2)
///   3: シーングラフ (Phase 6)
///   4: 2D 物理エンジン (Phase 8)
///   5: 全機能統合デモ
///
/// その他の操作:
///   H: パフォーマンス HUD 表示切替 (Phase 7)
///   R: 物理シーンリセット (Scene 4)
@main
final class NextGenShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "Next-Gen Showcase (Phase 1-8)",
            windowScale: 1.0
        )
    }

    // MARK: - State

    var currentScene: Int = 1
    var hudEnabled = false

    // Scene 3: Scene Graph
    var solarRoot: Node?
    var sunNode: Node?
    var earthOrbit: Node?
    var earthNode: Node?
    var moonOrbit: Node?
    var moonNode: Node?
    var marsOrbit: Node?
    var marsNode: Node?

    // Scene 4: Physics
    var physics: Physics2D?
    var physicsFrameCount: Int = 0

    // MARK: - Lifecycle

    func setup() {
        setupSceneGraph()
        setupPhysics()
    }

    func draw() {
        background(Color(gray: 0.05))

        switch currentScene {
        case 1: drawScene1_PBR()
        case 2: drawScene2_Shadows()
        case 3: drawScene3_SceneGraph()
        case 4: drawScene4_Physics()
        case 5: drawScene5_Combined()
        default: drawScene1_PBR()
        }

        drawHUD()
    }

    // MARK: - Input

    func keyPressed() {
        guard let k = key else { return }

        switch k {
        case "1":
            currentScene = 1
            disableShadows()
        case "2":
            currentScene = 2
            enableShadows()
        case "3":
            currentScene = 3
            disableShadows()
        case "4":
            currentScene = 4
            disableShadows()
        case "5":
            currentScene = 5
            enableShadows()

        case "h", "H":
            hudEnabled.toggle()
            if hudEnabled {
                enablePerformanceHUD()
            } else {
                disablePerformanceHUD()
            }

        case "r", "R":
            if currentScene == 4 {
                setupPhysics()
            }

        default: break
        }
    }

    // =========================================================================
    // MARK: - Scene 1: PBR Material Gallery (Phase 2-1)
    // =========================================================================

    func drawScene1_PBR() {
        // Lighting setup
        lights()
        ambientLight(0.1)
        directionalLight(-0.5, -1.0, -0.8, color: .white)
        pointLight(300, 200, 400, color: Color(r: 1, g: 0.9, b: 0.8, a: 1))

        camera(eye: SIMD3(0, 0, 550), center: SIMD3(0, 0, 0))

        let rows = 5
        let cols = 7
        let spacingX: Float = 75
        let spacingY: Float = 85
        let startX = -Float(cols - 1) / 2 * spacingX
        let startY = -Float(rows - 1) / 2 * spacingY

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + Float(col) * spacingX
                let y = startY + Float(row) * spacingY

                let r = Float(col) / Float(cols - 1)  // roughness: 0 → 1
                let m = Float(row) / Float(rows - 1)  // metallic:  0 → 1

                push()
                translate(x, -y, 0)

                // PBR parameters
                roughness(r)
                metallic(m)
                ambientOcclusion(1.0)

                // Color: warm gold for metallic, cool blue for dielectric
                let baseR = lerp(0.4, 1.0, m)
                let baseG = lerp(0.5, 0.85, m)
                let baseB = lerp(0.9, 0.3, m)
                fill(Color(r: baseR, g: baseG, b: baseB, a: 1))
                noStroke()
                sphere(28, detail: 32)

                // Reset PBR
                pbr(false)
                pop()
            }
        }

        // Labels
        fill(Color.white)
        noStroke()
        textSize(12)

        // Top labels (roughness)
        textAlign(.center, .bottom)
        for col in 0..<cols {
            let r = Float(col) / Float(cols - 1)
            let sx = width / 2 + startX + Float(col) * spacingX
            text(String(format: "R=%.1f", r), sx, 50)
        }

        // Left labels (metallic)
        textAlign(.right, .center)
        for row in 0..<rows {
            let m = Float(row) / Float(rows - 1)
            let sy = height / 2 - startY - Float(row) * spacingY
            text(String(format: "M=%.1f", m), width / 2 + startX - 25, sy)
        }

        drawSceneLabel(
            "1: PBR Material (Cook-Torrance GGX)",
            "Roughness → (columns)   Metallic ↑ (rows) — Phase 2-1"
        )
    }

    // =========================================================================
    // MARK: - Scene 2: Shadow Mapping (Phase 2-2)
    // =========================================================================

    func drawScene2_Shadows() {
        lights()
        ambientLight(0.15)

        // Directional light (first one = shadow caster)
        directionalLight(-0.6, -1.0, -0.4, color: .white)

        camera(eye: SIMD3(200, 300, 400), center: SIMD3(0, 0, 0))

        let t = time

        // Floor
        push()
        translate(0, -60, 0)
        fill(Color(r: 0.6, g: 0.6, b: 0.65, a: 1))
        noStroke()
        box(600, 4, 600)
        pop()

        // Central sphere
        push()
        translate(0, 20, 0)
        fill(Color(r: 0.9, g: 0.3, b: 0.3, a: 1))
        roughness(0.3)
        metallic(0.1)
        sphere(50, detail: 32)
        pbr(false)
        pop()

        // Orbiting boxes
        for i in 0..<4 {
            push()
            let angle = Float(i) / 4.0 * Float.pi * 2 + t * 0.5
            let radius: Float = 150
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y: Float = 0 + sin(t * 1.5 + Float(i)) * 30

            translate(x, y, z)
            rotateY(t + Float(i))
            rotateX(t * 0.7)

            let hue = Float(i) / 4.0
            fill(Color(hue: hue, saturation: 0.7, brightness: 0.9))
            noStroke()
            box(40)
            pop()
        }

        // Tall pillar
        push()
        translate(-100, 10, -80)
        fill(Color(r: 0.3, g: 0.7, b: 0.4, a: 1))
        noStroke()
        box(30, 140, 30)
        pop()

        // Torus
        push()
        translate(80, 40, -60)
        rotateX(t * 0.4)
        rotateZ(t * 0.2)
        fill(Color(r: 0.9, g: 0.8, b: 0.2, a: 1))
        roughness(0.5)
        metallic(0.8)
        torus(ringRadius: 40, tubeRadius: 12, detail: 24)
        pbr(false)
        pop()

        drawSceneLabel(
            "2: Shadow Mapping (PCF 3x3)",
            "enableShadows() + directionalLight — Phase 2-2"
        )
    }

    // =========================================================================
    // MARK: - Scene 3: Scene Graph / Solar System (Phase 6)
    // =========================================================================

    func setupSceneGraph() {
        // Root node
        solarRoot = createNode("root")

        // Sun (center)
        sunNode = createNode("sun")
        sunNode?.onDraw = { [self] in
            fill(Color(r: 1, g: 0.85, b: 0.2, a: 1))
            emissive(Color(r: 0.5, g: 0.4, b: 0.1, a: 1))
            noStroke()
            sphere(45, detail: 32)
            emissive(Color.black)
        }
        solarRoot?.addChild(sunNode!)

        // Earth orbit pivot
        earthOrbit = createNode("earthOrbit")
        sunNode?.addChild(earthOrbit!)

        // Earth
        earthNode = createNode("earth")
        earthNode?.position = SIMD3(140, 0, 0)
        earthNode?.onDraw = { [self] in
            fill(Color(r: 0.2, g: 0.4, b: 0.9, a: 1))
            roughness(0.6)
            metallic(0.0)
            noStroke()
            sphere(18, detail: 24)
            pbr(false)
        }
        earthOrbit?.addChild(earthNode!)

        // Moon orbit pivot (child of earth)
        moonOrbit = createNode("moonOrbit")
        earthNode?.addChild(moonOrbit!)

        // Moon
        moonNode = createNode("moon")
        moonNode?.position = SIMD3(35, 0, 0)
        moonNode?.onDraw = { [self] in
            fill(Color(r: 0.7, g: 0.7, b: 0.7, a: 1))
            noStroke()
            sphere(6, detail: 16)
        }
        moonOrbit?.addChild(moonNode!)

        // Mars orbit pivot
        marsOrbit = createNode("marsOrbit")
        sunNode?.addChild(marsOrbit!)

        // Mars
        marsNode = createNode("mars")
        marsNode?.position = SIMD3(230, 0, 0)
        marsNode?.onDraw = { [self] in
            fill(Color(r: 0.85, g: 0.35, b: 0.15, a: 1))
            roughness(0.8)
            metallic(0.0)
            noStroke()
            sphere(12, detail: 24)
            pbr(false)
        }
        marsOrbit?.addChild(marsNode!)
    }

    func drawScene3_SceneGraph() {
        lights()
        ambientLight(0.2)
        pointLight(0, 0, 0, color: Color(r: 1, g: 0.9, b: 0.7, a: 1), falloff: 0.001)

        camera(eye: SIMD3(0, 250, 350), center: SIMD3(0, 0, 0))

        let t = time

        // Update rotations (orbits)
        sunNode?.rotation.y = t * 0.2
        earthOrbit?.rotation.y = t * 0.8
        earthNode?.rotation.y = t * 3.0
        moonOrbit?.rotation.y = t * 3.0
        marsOrbit?.rotation.y = t * 0.4

        // Draw orbit paths (2D-like rings)
        noFill()
        stroke(Color(r: 0.3, g: 0.3, b: 0.4, a: 0.3))
        strokeWeight(1)

        // Earth orbit ring
        push()
        rotateX(Float.pi / 2)
        circle(0, 0, 280) // radius = 140 * 2
        pop()

        // Mars orbit ring
        push()
        rotateX(Float.pi / 2)
        circle(0, 0, 460) // radius = 230 * 2
        pop()

        // Render scene graph
        if let root = solarRoot {
            drawScene(root)
        }

        // Node count info
        fill(Color(r: 0.6, g: 0.6, b: 0.6, a: 0.8))
        noStroke()
        textSize(12)
        textAlign(.left, .bottom)
        text("Nodes: sun → earthOrbit → earth → moonOrbit → moon", 20, height - 60)
        text("             → marsOrbit → mars", 20, height - 44)
        text("Hierarchical transforms: child orbits inherit parent rotation", 20, height - 24)

        drawSceneLabel(
            "3: Scene Graph (Solar System)",
            "createNode() + addChild() + drawScene() — Phase 6"
        )
    }

    // =========================================================================
    // MARK: - Scene 4: 2D Physics Engine (Phase 8)
    // =========================================================================

    func setupPhysics() {
        physics = createPhysics2D(cellSize: 60)
        physicsFrameCount = 0

        guard let p = physics else { return }

        // Gravity
        p.addGravity(0, 600)

        // World bounds
        p.bounds = (
            min: SIMD2(0, 0),
            max: SIMD2(Float(1280), Float(720))
        )

        // Floor (static rect)
        let floor = p.addRect(x: 640, y: 690, width: 1200, height: 30, mass: 1)
        floor.isStatic = true

        // Left wall
        let leftWall = p.addRect(x: 10, y: 360, width: 20, height: 700, mass: 1)
        leftWall.isStatic = true

        // Right wall
        let rightWall = p.addRect(x: 1270, y: 360, width: 20, height: 700, mass: 1)
        rightWall.isStatic = true

        // Ramp (static)
        let ramp = p.addRect(x: 400, y: 500, width: 300, height: 15, mass: 1)
        ramp.isStatic = true

        let ramp2 = p.addRect(x: 880, y: 380, width: 300, height: 15, mass: 1)
        ramp2.isStatic = true

        // Dynamic circles
        for i in 0..<20 {
            let x = 200 + Float(i % 10) * 90 + Float.random(in: -20...20)
            let y = 50 + Float(i / 10) * 60 + Float.random(in: -10...10)
            let radius = Float.random(in: 10...25)
            let body = p.addCircle(x: x, y: y, radius: radius, mass: radius * 0.1)
            body.restitution = 0.6
        }

        // Dynamic rects
        for i in 0..<8 {
            let x = 300 + Float(i) * 80 + Float.random(in: -20...20)
            let y = Float.random(in: 100...200)
            let w = Float.random(in: 20...40)
            let h = Float.random(in: 20...40)
            let body = p.addRect(x: x, y: y, width: w, height: h, mass: w * h * 0.001)
            body.restitution = 0.4
        }

        // Constraint chain (hanging pendulum)
        var prev: PhysicsBody2D?
        let anchorX: Float = 640
        let anchorY: Float = 80
        for i in 0..<6 {
            let body = p.addCircle(
                x: anchorX + Float(i) * 25,
                y: anchorY + Float(i) * 30,
                radius: 8,
                mass: 0.5
            )
            body.restitution = 0.3

            if i == 0 {
                p.pin(body, x: anchorX, y: anchorY)
            }
            if let prev = prev {
                p.addConstraint(prev, body, distance: 30)
            }
            prev = body
        }
    }

    func drawScene4_Physics() {
        guard let p = physics else {
            setupPhysics()
            return
        }

        // Step physics
        let dt: Float = min(deltaTime, 1.0 / 30.0)
        p.step(dt, iterations: 6)
        physicsFrameCount += 1

        // Spawn new circle on mouse click area
        if physicsFrameCount % 30 == 0 && physicsFrameCount < 600 {
            let x = Float.random(in: 200...1080)
            let radius = Float.random(in: 8...18)
            let body = p.addCircle(x: x, y: 30, radius: radius, mass: radius * 0.1)
            body.restitution = 0.5
        }

        // Draw bodies
        for body in p.bodies {
            let pos = body.position

            if body.isStatic {
                // Static bodies: dark gray
                fill(Color(r: 0.3, g: 0.3, b: 0.35, a: 1))
                noStroke()
            } else {
                // Dynamic bodies: colored by velocity
                let speed = simd_length(body.velocity) / dt
                let hue = min(speed / 500.0, 1.0) * 0.3
                fill(Color(hue: 0.55 - hue, saturation: 0.7, brightness: 0.9))
                stroke(Color(r: 1, g: 1, b: 1, a: 0.2))
                strokeWeight(1)
            }

            switch body.shape {
            case .circle(let radius):
                circle(pos.x, pos.y, radius * 2)
            case .rect(let w, let h):
                rect(pos.x - w / 2, pos.y - h / 2, w, h)
            }
        }

        // Draw constraints
        stroke(Color(r: 0.8, g: 0.8, b: 0.3, a: 0.6))
        strokeWeight(2)
        for constraint in p.constraints {
            if let pin = constraint.pinPosition {
                // Pin constraint
                line(constraint.bodyA.position.x, constraint.bodyA.position.y,
                     pin.x, pin.y)
            } else if let bodyB = constraint.bodyB {
                // Distance constraint
                line(constraint.bodyA.position.x, constraint.bodyA.position.y,
                     bodyB.position.x, bodyB.position.y)
            }
        }

        // Info
        fill(Color(r: 0.5, g: 0.5, b: 0.5, a: 0.7))
        noStroke()
        textSize(12)
        textAlign(.left, .bottom)
        text("Bodies: \(p.bodies.count)  Constraints: \(p.constraints.count)", 20, height - 24)
        text("Press R to reset", 20, height - 8)

        drawSceneLabel(
            "4: 2D Physics (Verlet Integration)",
            "Gravity + Collisions + Constraints + SpatialHash — Phase 8"
        )
    }

    // =========================================================================
    // MARK: - Scene 5: Combined Demo (PBR + Shadows + SceneGraph)
    // =========================================================================

    func drawScene5_Combined() {
        // Full lighting setup with shadows
        lights()
        ambientLight(0.12)
        directionalLight(-0.5, -1.0, -0.6, color: .white)
        pointLight(100, 200, 200, color: Color(r: 1, g: 0.85, b: 0.7, a: 1))

        camera(eye: SIMD3(0, 200, 400), center: SIMD3(0, 30, 0))

        let t = time

        // Floor with PBR
        push()
        translate(0, -30, 0)
        roughness(0.9)
        metallic(0.0)
        fill(Color(r: 0.5, g: 0.5, b: 0.55, a: 1))
        noStroke()
        box(500, 4, 500)
        pbr(false)
        pop()

        // PBR metallic sphere (center)
        push()
        translate(0, 40, 0)
        roughness(0.15)
        metallic(0.95)
        fill(Color(r: 1, g: 0.85, b: 0.5, a: 1))
        noStroke()
        sphere(50, detail: 32)
        pbr(false)
        pop()

        // Orbiting objects with different PBR settings
        for i in 0..<6 {
            push()
            let angle = Float(i) / 6.0 * Float.pi * 2 + t * 0.4
            let r: Float = 150
            translate(cos(angle) * r, 10 + sin(t * 1.2 + Float(i)) * 20, sin(angle) * r)
            rotateY(t + Float(i))

            let roughVal = Float(i) / 5.0
            roughness(roughVal)
            metallic(1.0 - roughVal)

            let hue = Float(i) / 6.0
            fill(Color(hue: hue, saturation: 0.6, brightness: 0.9))
            noStroke()

            if i % 2 == 0 {
                box(30)
            } else {
                sphere(18, detail: 24)
            }

            pbr(false)
            pop()
        }

        // Torus ring
        push()
        translate(0, 90, 0)
        rotateX(t * 0.3)
        rotateZ(t * 0.15)
        roughness(0.2)
        metallic(0.9)
        fill(Color(r: 0.9, g: 0.9, b: 0.95, a: 1))
        noStroke()
        torus(ringRadius: 80, tubeRadius: 8, detail: 32)
        pbr(false)
        pop()

        drawSceneLabel(
            "5: Combined (PBR + Shadows + Lighting)",
            "roughness() + metallic() + enableShadows() — Phase 2"
        )
    }

    // =========================================================================
    // MARK: - HUD
    // =========================================================================

    func drawHUD() {
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.6))
        rect(0, 0, width, 36)

        fill(Color.white)
        textSize(13)
        textAlign(.left, .top)
        text("Scene [\(currentScene)/5]  Keys: 1-5 scenes | H=HUD | R=reset physics", 10, 10)

        textAlign(.right, .top)
        let fps = Int(1.0 / max(deltaTime, 0.001))
        text("\(fps) fps  frame:\(frameCount)", width - 10, 10)

        if hudEnabled {
            fill(Color(r: 0.3, g: 1, b: 0.3, a: 0.8))
            textAlign(.center, .top)
            text("Performance HUD: ON", width / 2, 10)
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
