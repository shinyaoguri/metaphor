import metaphor

/// Feature 7: GPU ImageFilter 拡充 + Feature 6: 自動フラッシュ
///
/// 元画像に各種フィルタを適用し、グリッドで比較表示。
/// 大量の描画呼び出しで Feature 6 の自動フラッシュも暗黙的に活用。
@main
final class FilterGalleryExample: Sketch {
    var filteredImages: [(String, MImage)] = []

    let filterNames: [String] = [
        "Original", "Gray", "Invert", "Threshold",
        "Posterize", "Blur", "Edge Detect", "Sharpen",
        "Sepia", "Pixelate", "Erode", "Dilate",
    ]
    let filterTypes: [FilterType?] = [
        nil, .gray, .invert, .threshold(0.5),
        .posterize(4), .blur(8), .edgeDetect, .sharpen(2.0),
        .sepia, .pixelate(8), .erode, .dilate,
    ]

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Filter Gallery (GPU)")
    }

    func setup() {
        // 各フィルタごとにソース画像を生成してフィルタ適用
        for i in 0..<filterNames.count {
            // ソース画像をオフスクリーンで毎回生成
            guard let pg = createGraphics(400, 300) else { continue }
            pg.beginDraw()
            pg.noStroke()
            for y in 0..<300 {
                let t = Float(y) / 300.0
                pg.fill(Color(hue: t * 0.3 + 0.6, saturation: 0.7, brightness: 0.3 + t * 0.5))
                pg.rect(0, Float(y), 400, 1)
            }
            pg.fill(Color(r: 1.0, g: 0.3, b: 0.2))
            pg.circle(200, 150, 120)
            pg.fill(Color(r: 0.2, g: 0.8, b: 1.0))
            pg.rect(50, 200, 100, 60)
            pg.fill(Color(r: 1.0, g: 0.9, b: 0.1))
            pg.triangle(300, 80, 350, 200, 250, 200)
            pg.fill(.white)
            pg.textSize(28)
            pg.textAlign(.center, .center)
            pg.text("metaphor", 200, 40)
            pg.endDraw()

            let img = pg.toImage()
            if let ft = filterTypes[i] {
                img.filter(ft)
            }
            filteredImages.append((filterNames[i], img))
        }
    }

    func draw() {
        background(Color(gray: 0.08))

        let cols = 4
        let rows = 3
        let padding: Float = 20
        let labelHeight: Float = 30
        let cellW = (width - padding * Float(cols + 1)) / Float(cols)
        let cellH = (height - padding * Float(rows + 1) - labelHeight * Float(rows)) / Float(rows)

        for i in 0..<filteredImages.count {
            let col = i % cols
            let row = i / cols
            let x = padding + Float(col) * (cellW + padding)
            let y = padding + Float(row) * (cellH + padding + labelHeight)

            let (name, img) = filteredImages[i]

            image(img, x, y + labelHeight, cellW, cellH)

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x, y + labelHeight, cellW, cellH)
            noStroke()

            fill(Color(gray: 0.8))
            textSize(14)
            textAlign(.center, .top)
            text(name, x + cellW / 2, y + 4)
        }
    }
}
