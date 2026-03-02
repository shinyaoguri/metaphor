import metaphor
import Foundation

/// CoreImage Filter Showcase
///
/// 30 種の CIFilter プリセットをリアルタイムプレビュー。
/// 左に元画像、右にフィルタ適用結果を表示。
///
/// 操作:
///   UP/DOWN: フィルタ選択
///   LEFT/RIGHT: カテゴリ切替
///   Space: アニメーション ON/OFF
///   G: ジェネレーターモード切替
@main
final class CIFilterShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "CoreImage Filter Showcase",
            windowScale: 1.0
        )
    }

    // MARK: - State

    var selectedCategory = 0
    var selectedFilter = 0
    var animate = true
    var showGenerator = false

    var sourceImage: MImage!

    struct FilterEntry {
        let name: String
        let preset: CIFilterPreset
    }

    let categories = ["Distortion", "Stylize", "Tile", "Color", "Blur"]

    let filters: [[FilterEntry]] = [
        // Distortion
        [
            FilterEntry(name: "Twirl", preset: .twirl()),
            FilterEntry(name: "Vortex", preset: .vortex()),
            FilterEntry(name: "Bump", preset: .bump()),
            FilterEntry(name: "Pinch", preset: .pinch()),
            FilterEntry(name: "Circular Wrap", preset: .circularWrap()),
        ],
        // Stylize
        [
            FilterEntry(name: "Pixellate", preset: .ciPixellate(scale: 12)),
            FilterEntry(name: "Crystallize", preset: .crystallize(radius: 15)),
            FilterEntry(name: "Pointillize", preset: .pointillize(radius: 10)),
            FilterEntry(name: "Edges", preset: .ciEdges(intensity: 3)),
            FilterEntry(name: "Comic", preset: .comic),
            FilterEntry(name: "Hex Pixellate", preset: .hexPixellate(scale: 10)),
        ],
        // Tile
        [
            FilterEntry(name: "Kaleidoscope", preset: .kaleidoscope(count: 6)),
            FilterEntry(name: "Triangle Kaleidoscope", preset: .triangleKaleidoscope()),
        ],
        // Color
        [
            FilterEntry(name: "Photo Mono", preset: .photoEffectMono),
            FilterEntry(name: "Photo Chrome", preset: .photoEffectChrome),
            FilterEntry(name: "Photo Noir", preset: .photoEffectNoir),
            FilterEntry(name: "Photo Fade", preset: .photoEffectFade),
            FilterEntry(name: "Color Posterize", preset: .colorPosterize(levels: 4)),
            FilterEntry(name: "False Color", preset: .falseColor()),
        ],
        // Blur
        [
            FilterEntry(name: "Gaussian Blur", preset: .ciGaussianBlur(radius: 10)),
            FilterEntry(name: "Motion Blur", preset: .motionBlur(radius: 25, angle: .pi / 6)),
            FilterEntry(name: "Zoom Blur", preset: .zoomBlur(amount: 15)),
            FilterEntry(name: "Disc Blur", preset: .discBlur(radius: 12)),
            FilterEntry(name: "Box Blur", preset: .boxBlur(radius: 8)),
        ],
    ]

    let generators: [FilterEntry] = [
        FilterEntry(name: "Checkerboard", preset: .checkerboard(width: 40)),
        FilterEntry(name: "Stripes", preset: .stripes(width: 30)),
        FilterEntry(name: "Star Shine", preset: .starShine()),
        FilterEntry(name: "Sunbeams", preset: .sunbeams()),
    ]

    var selectedGenerator = 0

    // MARK: - Lifecycle

    func setup() {
        sourceImage = generateTestImage()
    }

    func draw() {
        background(Color(gray: 0.05))

        let time = Float(frameCount) * 0.02

        if showGenerator {
            drawGeneratorMode(time)
        } else {
            drawFilterMode(time)
        }

        drawHUD()
    }

    func keyPressed() {
        guard let k = key else { return }

        switch k {
        case " ": animate.toggle()
        case "g", "G": showGenerator.toggle(); selectedFilter = 0
        default: break
        }

        if showGenerator {
            if keyCode == 126 { // UP
                selectedGenerator = max(0, selectedGenerator - 1)
            } else if keyCode == 125 { // DOWN
                selectedGenerator = min(generators.count - 1, selectedGenerator + 1)
            }
        } else {
            if keyCode == 126 { // UP
                selectedFilter = max(0, selectedFilter - 1)
            } else if keyCode == 125 { // DOWN
                let maxIdx = filters[selectedCategory].count - 1
                selectedFilter = min(maxIdx, selectedFilter + 1)
            } else if keyCode == 124 { // RIGHT
                selectedCategory = (selectedCategory + 1) % categories.count
                selectedFilter = 0
            } else if keyCode == 123 { // LEFT
                selectedCategory = (selectedCategory - 1 + categories.count) % categories.count
                selectedFilter = 0
            }
        }
    }

    // MARK: - Filter Mode

    func drawFilterMode(_ time: Float) {
        let previewSize: Float = 400
        let gap: Float = 40

        // Left: original
        let origX: Float = width / 2 - previewSize - gap / 2
        let origY: Float = 90
        drawImagePreview(sourceImage, x: origX, y: origY, size: previewSize, label: "Original")

        // Right: filtered
        let filtX = width / 2 + gap / 2
        let currentFilter = filters[selectedCategory][selectedFilter]

        // Create animated preset based on type
        let animatedPreset = animatePreset(currentFilter.preset, time: time)

        let filtered = MImage(texture: sourceImage.texture)
        ciFilter(filtered, animatedPreset)
        drawImagePreview(filtered, x: filtX, y: origY, size: previewSize, label: currentFilter.name)

        // Arrow
        fill(Color(gray: 0.3))
        textSize(30)
        text("->", width / 2 - 18, origY + previewSize / 2 + 10)

        // Category tabs
        drawCategoryTabs()

        // Filter list
        drawFilterList()
    }

    // MARK: - Generator Mode

    func drawGeneratorMode(_ time: Float) {
        let previewSize: Float = 480
        let centerX = (width - previewSize) / 2
        let centerY: Float = 100

        let gen = generators[selectedGenerator]
        let generated = ciGenerate(gen.preset, width: Int(previewSize), height: Int(previewSize))

        if let img = generated {
            image(img, centerX, centerY, previewSize, previewSize)
        }

        // Border
        noFill()
        stroke(Color(gray: 0.3))
        strokeWeight(1)
        rect(centerX - 1, centerY - 1, previewSize + 2, previewSize + 2)

        // Label
        fill(Color(hue: 0.12, saturation: 0.8, brightness: 1))
        textSize(18)
        text("Generator: \(gen.name)", centerX, centerY - 12)

        // Generator list
        let listX = centerX + previewSize + 30
        let listY = centerY

        fill(Color(gray: 0.5))
        textSize(13)
        text("Generators", listX, listY + 14)

        for (i, g) in generators.enumerated() {
            let y = listY + Float(i) * 28 + 36
            let isSelected = i == selectedGenerator
            if isSelected {
                noStroke()
                fill(Color(hue: 0.12, saturation: 0.3, brightness: 0.2))
                rect(listX - 4, y - 12, 180, 24, 4)
            }
            fill(isSelected ? Color(hue: 0.12, saturation: 0.8, brightness: 1) : Color(gray: 0.6))
            textSize(12)
            text(g.name, listX, y)
        }
    }

    // MARK: - Drawing Helpers

    func drawImagePreview(_ img: MImage, x: Float, y: Float, size: Float, label: String) {
        image(img, x, y, size, size)

        // Border
        noFill()
        stroke(Color(gray: 0.3))
        strokeWeight(1)
        rect(x - 1, y - 1, size + 2, size + 2)

        // Label
        fill(Color(gray: 0.7))
        textSize(13)
        text(label, x, y - 8)
    }

    func drawCategoryTabs() {
        let tabY: Float = 58
        var tabX: Float = 20

        for (i, cat) in categories.enumerated() {
            let isSelected = i == selectedCategory
            let tabW: Float = Float(cat.count) * 9 + 20

            if isSelected {
                noStroke()
                fill(Color(hue: 0.6, saturation: 0.4, brightness: 0.25))
                rect(tabX, tabY - 12, tabW, 22, 4)
            }

            fill(isSelected ? Color(hue: 0.6, saturation: 0.8, brightness: 1) : Color(gray: 0.5))
            textSize(12)
            text(cat, tabX + 10, tabY)

            tabX += tabW + 8
        }
    }

    func drawFilterList() {
        let listX: Float = 20
        let listY: Float = 530
        let currentFilters = filters[selectedCategory]

        fill(Color(gray: 0.5))
        textSize(12)
        text("Filters (\(currentFilters.count))", listX, listY)

        for (i, f) in currentFilters.enumerated() {
            let x = listX + Float(i) * 160
            let y = listY + 20
            let isSelected = i == selectedFilter

            if isSelected {
                noStroke()
                fill(Color(hue: 0.6, saturation: 0.3, brightness: 0.2))
                rect(x - 4, y - 10, 150, 22, 4)
            }

            fill(isSelected ? .white : Color(gray: 0.6))
            textSize(12)
            text(f.name, x, y)
        }
    }

    func animatePreset(_ preset: CIFilterPreset, time: Float) -> CIFilterPreset {
        guard animate else { return preset }

        switch preset {
        case .twirl:
            return .twirl(radius: 200, angle: time * 2)
        case .vortex:
            return .vortex(radius: 200, angle: time * 50)
        case .kaleidoscope:
            return .kaleidoscope(count: 6, angle: time)
        default:
            return preset
        }
    }

    // MARK: - HUD

    func drawHUD() {
        // Title bar
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.75))
        rect(0, 0, width, 48)

        fill(.white)
        textSize(18)
        text(showGenerator ? "CoreImage Generators" : "CoreImage Filters", 20, 30)

        // Mode indicator
        fill(showGenerator ? Color(hue: 0.12, saturation: 0.8, brightness: 1) : Color(hue: 0.6, saturation: 0.8, brightness: 1))
        textSize(11)
        text(showGenerator ? "GENERATOR" : "FILTER", 280, 30)

        // Animate indicator
        if animate {
            fill(Color(hue: 0.33, saturation: 1, brightness: 1))
            circle(width - 30, 24, 8)
        }

        // Controls
        fill(Color(gray: 0.4))
        textSize(10)
        text("[Up/Down] Select  [Left/Right] Category  [G] Generator  [Space] Animate", 20, height - 10)
    }

    // MARK: - Test Image

    func generateTestImage() -> MImage {
        let w = 512
        let h = 512
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let u = Float(x) / Float(w)
                let v = Float(y) / Float(h)

                // Colorful gradient with shapes
                var r: Float = u * 0.6
                var g: Float = v * 0.5
                var b: Float = (1 - u) * 0.7

                // Circle
                let dx = u - 0.35
                let dy = v - 0.4
                if dx * dx + dy * dy < 0.04 {
                    r = 0.9; g = 0.3; b = 0.2
                }

                // Another circle
                let dx2 = u - 0.7
                let dy2 = v - 0.6
                if dx2 * dx2 + dy2 * dy2 < 0.025 {
                    r = 0.2; g = 0.7; b = 0.9
                }

                // Rectangle
                if u > 0.1 && u < 0.3 && v > 0.6 && v < 0.85 {
                    r = 0.9; g = 0.8; b = 0.2
                }

                // Diagonal stripe
                let stripe = sin((u + v) * 20) * 0.5 + 0.5
                if v < 0.15 {
                    r = stripe * 0.8
                    g = stripe * 0.9
                    b = stripe * 1.0
                }

                pixels[i] = UInt8(min(255, b * 255))      // B
                pixels[i + 1] = UInt8(min(255, g * 255))  // G
                pixels[i + 2] = UInt8(min(255, r * 255))  // R
                pixels[i + 3] = 255                        // A
            }
        }

        guard let img = createImage(w, h) else {
            fatalError("Failed to create test image")
        }
        img.loadPixels()
        img.pixels = pixels
        img.updatePixels()
        return img
    }
}
