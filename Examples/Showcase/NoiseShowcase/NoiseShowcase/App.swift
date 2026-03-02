import metaphor
import Foundation

/// GameplayKit Noise Showcase
///
/// 8 種のノイズを並べて表示。リアルタイムでパラメータ変化をプレビュー。
///
/// 操作:
///   1-8: ノイズタイプ切替（全体表示）
///   Tab: グリッド / 単体 表示切替
///   UP/DOWN: frequency 変更
///   LEFT/RIGHT: octaves 変更
///   S: seed をランダム変更
///   Space: アニメーション ON/OFF
@main
final class NoiseShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "GameplayKit Noise Showcase",
            windowScale: 1.0
        )
    }

    // MARK: - State

    var showGrid = true
    var selectedType = 0
    var animate = true
    var frequency: Double = 2.0
    var octaves: Int = 6
    var currentSeed: Int32 = 0

    let noiseNames = [
        "Perlin", "Voronoi", "Billow", "Ridged",
        "Cylinders", "Spheres", "Checkerboard", "Constant",
    ]

    let noiseTypes: [NoiseType] = [
        .perlin, .voronoi, .billow, .ridged,
        .cylinders, .spheres, .checkerboard, .constant(value: 0.5),
    ]

    // Cached textures
    var noiseTextures: [MTLTexture?] = Array(repeating: nil, count: 8)
    var needsUpdate = true
    var lastUpdateFrame = 0

    // MARK: - Lifecycle

    func setup() {
        regenerateAll()
    }

    func draw() {
        background(Color(gray: 0.06))

        // Animate: shift origin over time
        if animate && frameCount % 6 == 0 {
            regenerateAll()
        }

        if needsUpdate {
            regenerateAll()
            needsUpdate = false
        }

        if showGrid {
            drawGrid()
        } else {
            drawSingle()
        }

        drawHUD()
    }

    func keyPressed() {
        guard let k = key else { return }

        switch k {
        case "1": selectedType = 0; needsUpdate = true
        case "2": selectedType = 1; needsUpdate = true
        case "3": selectedType = 2; needsUpdate = true
        case "4": selectedType = 3; needsUpdate = true
        case "5": selectedType = 4; needsUpdate = true
        case "6": selectedType = 5; needsUpdate = true
        case "7": selectedType = 6; needsUpdate = true
        case "8": selectedType = 7; needsUpdate = true
        case "\t": showGrid.toggle()
        case " ": animate.toggle()
        case "s", "S":
            currentSeed = Int32.random(in: 0...9999)
            needsUpdate = true
        default:
            break
        }

        if keyCode == 126 { // UP
            frequency = min(16.0, frequency + 0.5)
            needsUpdate = true
        } else if keyCode == 125 { // DOWN
            frequency = max(0.5, frequency - 0.5)
            needsUpdate = true
        } else if keyCode == 124 { // RIGHT
            octaves = min(10, octaves + 1)
            needsUpdate = true
        } else if keyCode == 123 { // LEFT
            octaves = max(1, octaves - 1)
            needsUpdate = true
        }
    }

    // MARK: - Noise Generation

    func regenerateAll() {
        let texSize = showGrid ? 256 : 512
        let timeOffset = animate ? Double(frameCount) * 0.02 : 0

        for i in 0..<8 {
            var config = NoiseConfig()
            config.frequency = frequency
            config.octaves = octaves
            config.seed = currentSeed
            config.normalized = true
            config.origin = SIMD2(timeOffset, 0)

            let noise = createNoise(noiseTypes[i], config: config)
            noiseTextures[i] = noise.texture(width: texSize, height: texSize)
        }
    }

    // MARK: - Drawing: Grid View

    func drawGrid() {
        let cols = 4
        let rows = 2
        let margin: Float = 16
        let topOffset: Float = 60
        let cellW = (width - margin * Float(cols + 1)) / Float(cols)
        let cellH = (height - topOffset - margin * Float(rows + 1)) / Float(rows)
        let texSize = min(cellW, cellH) - 8

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                guard idx < 8 else { continue }

                let x = margin + Float(col) * (cellW + margin)
                let y = topOffset + margin + Float(row) * (cellH + margin)

                // Background
                noStroke()
                fill(Color(gray: 0.1))
                rect(x, y, cellW, cellH, 4)

                // Texture
                if let tex = noiseTextures[idx] {
                    let img = MImage(texture: tex)
                    let texX = x + (cellW - texSize) / 2
                    let texY = y + 24
                    image(img, texX, texY, texSize, texSize - 28)
                }

                // Label
                let isSelected = idx == selectedType
                fill(isSelected ? Color(hue: 0.55, saturation: 0.8, brightness: 1) : Color(gray: 0.7))
                textSize(13)
                text("\(idx + 1): \(noiseNames[idx])", x + 8, y + 16)

                // Selection highlight
                if isSelected {
                    noFill()
                    stroke(Color(hue: 0.55, saturation: 0.8, brightness: 1))
                    strokeWeight(2)
                    rect(x, y, cellW, cellH, 4)
                }
            }
        }
    }

    // MARK: - Drawing: Single View

    func drawSingle() {
        let idx = selectedType
        let texSize: Float = 512
        let texX = (width - texSize) / 2
        let texY: Float = 80

        // Texture
        if let tex = noiseTextures[idx] {
            let img = MImage(texture: tex)
            image(img, texX, texY, texSize, texSize)

            // Border
            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(texX - 1, texY - 1, texSize + 2, texSize + 2)
        }

        // Type name
        fill(Color(hue: 0.55, saturation: 0.8, brightness: 1))
        textSize(20)
        text(noiseNames[idx], texX, texY - 12)

        // Parameters panel
        let panelX = texX + texSize + 30
        let panelY = texY

        fill(Color(gray: 0.6))
        textSize(14)
        text("Parameters", panelX, panelY + 16)

        fill(Color(gray: 0.8))
        textSize(12)
        text("Frequency: \(String(format: "%.1f", frequency))", panelX, panelY + 44)
        text("Octaves: \(octaves)", panelX, panelY + 66)
        text("Seed: \(currentSeed)", panelX, panelY + 88)

        // Mini sliders (visual only)
        let barW: Float = 150
        noStroke()

        // Frequency bar
        fill(Color(gray: 0.15))
        rect(panelX, panelY + 50, barW, 6, 3)
        fill(Color(hue: 0.55, saturation: 0.6, brightness: 0.9))
        let freqPct = Float((frequency - 0.5) / 15.5)
        rect(panelX, panelY + 50, barW * freqPct, 6, 3)

        // Octaves bar
        fill(Color(gray: 0.15))
        rect(panelX, panelY + 72, barW, 6, 3)
        fill(Color(hue: 0.35, saturation: 0.6, brightness: 0.9))
        let octPct = Float(octaves - 1) / 9.0
        rect(panelX, panelY + 72, barW * octPct, 6, 3)

        // Sample value at mouse position
        if mouseX >= texX && mouseX < texX + texSize && mouseY >= texY && mouseY < texY + texSize {
            let nx = (mouseX - texX) / texSize
            let ny = (mouseY - texY) / texSize
            var config = NoiseConfig()
            config.frequency = frequency
            config.octaves = octaves
            config.seed = currentSeed
            config.normalized = true
            let noise = createNoise(noiseTypes[idx], config: config)
            let val = noise.sample(x: nx, y: ny)

            fill(Color(gray: 0.5))
            textSize(11)
            text("Value at cursor: \(String(format: "%.4f", val))", panelX, panelY + 130)

            // Crosshair
            stroke(Color(hue: 0.0, saturation: 0.8, brightness: 1, alpha: 0.6))
            strokeWeight(1)
            line(mouseX, texY, mouseX, texY + texSize)
            line(texX, mouseY, texX + texSize, mouseY)
        }
    }

    // MARK: - HUD

    func drawHUD() {
        // Title bar
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.75))
        rect(0, 0, width, 50)

        fill(.white)
        textSize(20)
        text("GameplayKit Noise", 20, 32)

        fill(Color(gray: 0.6))
        textSize(11)
        text("freq: \(String(format: "%.1f", frequency))  oct: \(octaves)  seed: \(currentSeed)", 260, 32)

        // Animation indicator
        if animate {
            fill(Color(hue: 0.33, saturation: 1, brightness: 1))
            circle(width - 30, 25, 10)
            fill(Color(gray: 0.5))
            textSize(10)
            text("LIVE", width - 55, 29)
        }

        // Controls
        fill(Color(gray: 0.4))
        textSize(10)
        text("[1-8] Type  [Tab] Grid/Single  [Up/Down] Freq  [Left/Right] Oct  [S] Seed  [Space] Animate", 20, height - 10)
    }
}
