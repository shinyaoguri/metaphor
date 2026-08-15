import simd

// MARK: - テキストのアウトライン（textToPoints / textToContours）

extension Canvas2D {

    /// テキストのグリフアウトラインを、輪郭ごとの閉じたポリラインとして返します。
    ///
    /// 現在の ``textSize(_:)`` / ``textFont(_:)-(String)`` / ``textAlign(_:_:)`` を
    /// `text()` と同じように解釈するため、同じ引数で呼べば描画結果と同じ位置の輪郭が
    /// 得られます。
    ///
    /// 文字の穴（`o` の内側など）も 1 本の輪郭として返ります。塗り分けに穴の情報が要る
    /// 場合は ``SketchContext/textToShape(_:_:_:sampleFactor:)`` を使ってください。
    ///
    /// 改行を含む文字列は ``text(_:_:_:)`` と同じく行ごとに分けて配置され、行の高さは
    /// ``textLeading(_:)`` に従います。水平方向の揃えは行ごとの幅で、垂直方向の揃えは
    /// 全行を 1 つのブロックとみなして決まります。
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - x: テキストの x 座標（`text()` と同じ意味）。
    ///   - y: テキストの y 座標（`text()` と同じ意味）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: 輪郭ごとのポリライン。空文字や輪郭を持たない文字だけなら空配列。
    public func textToContours(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [[Vec2]] {
        guard !string.isEmpty, sampleFactor > 0 else { return [] }

        let lines = Self.lines(of: string)
        guard lines.count > 1 else {
            return lineContours(lines[0], x, y, sampleFactor: sampleFactor)
        }

        // 描画側 text(_:_:_:) と同じ持ち上げ量。1 行のときは 0 になり単一行と一致する。
        let leading = effectiveTextLeading
        let hangingHeight = Float(lines.count - 1) * leading
        var lineY = y
        switch currentTextAlignV {
        case .top, .baseline: break
        case .center: lineY -= hangingHeight / 2
        case .bottom: lineY -= hangingHeight
        }

        var contours: [[Vec2]] = []
        for line in lines {
            contours += lineContours(line, x, lineY, sampleFactor: sampleFactor)
            lineY += leading
        }
        return contours
    }

    /// 改行を含まない 1 行のアウトラインを返します（``textToContours(_:_:_:sampleFactor:)`` の実体）。
    private func lineContours(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float
    ) -> [[Vec2]] {
        guard !string.isEmpty else { return [] }
        let contours = textRenderer.glyphContours(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily,
            sampleFactor: sampleFactor)
        guard !contours.isEmpty else { return [] }

        let width = textRenderer.textWidth(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
        let origin = textBaselineOrigin(x: x, y: y, width: width)
        let offset = Vec2(origin.x, origin.y)
        return contours.map { $0.map { $0 + offset } }
    }

    /// テキストのグリフアウトライン上の点を 1 本の配列で返します（p5 の `textToPoints` 相当）。
    ///
    /// 輪郭の区切りは失われます。文字を粒子や図形の配置元として使うときに向きます。
    /// 輪郭ごとに扱いたい場合は ``textToContours(_:_:_:sampleFactor:)`` を使ってください。
    ///
    /// ```swift
    /// for p in textToPoints("metaphor", 40, 200) {
    ///     circle(p.x, p.y, 4)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - x: テキストの x 座標（`text()` と同じ意味）。
    ///   - y: テキストの y 座標（`text()` と同じ意味）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: アウトライン上の点。
    public func textToPoints(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [Vec2] {
        textToContours(string, x, y, sampleFactor: sampleFactor).flatMap { $0 }
    }
}

// MARK: - 輪郭の包含判定

/// アウトラインの輪郭群を「外周 1 本 + その穴」の組へ仕分けます。
///
/// 巻き方向では判定しません（TrueType と CFF で外周の慣習が逆のため）。ある輪郭が
/// 別の輪郭の内側にあれば穴とみなす、という包含関係だけで決めます。`i` の点と軸のように
/// 1 文字が離れた外周を複数持つ場合も、これなら正しく 2 つの外周として扱えます。
enum ContourNesting {

    /// 外周とその穴の組。
    struct Group {
        var outer: [Vec2]
        var holes: [[Vec2]]
    }

    /// 輪郭群を外周ごとに仕分けます。
    static func group(_ contours: [[Vec2]]) -> [Group] {
        let boxes = contours.map(boundingBox)

        // 各輪郭について、自分を含む輪郭の数を数える。偶数（0）なら外周、奇数なら穴。
        // 穴の中の島（ネスト 2 段）まで踏み込まないのは、通常の書体では現れないため。
        var containerIndex = [Int?](repeating: nil, count: contours.count)
        var isHole = [Bool](repeating: false, count: contours.count)

        for i in contours.indices {
            var smallestArea = Float.greatestFiniteMagnitude
            for j in contours.indices where i != j {
                guard contains(boxes[j], boxes[i]),
                      contains(polygon: contours[j], point: contours[i][0]) else { continue }
                let area = (boxes[j].maxX - boxes[j].minX) * (boxes[j].maxY - boxes[j].minY)
                if area < smallestArea {
                    smallestArea = area
                    containerIndex[i] = j
                }
                isHole[i] = true
            }
        }

        var groups: [Int: Group] = [:]
        for i in contours.indices where !isHole[i] {
            groups[i] = Group(outer: contours[i], holes: [])
        }
        for i in contours.indices where isHole[i] {
            // 直近の親が穴だった場合（ネスト 2 段）は外周として扱えないので捨てる
            if let parent = containerIndex[i], groups[parent] != nil {
                groups[parent]?.holes.append(contours[i])
            }
        }
        // 入力順を保って返す（文字の並び順が保たれる）
        return contours.indices.compactMap { groups[$0] }
    }

    // MARK: - Private

    private struct Box {
        var minX: Float, minY: Float, maxX: Float, maxY: Float
    }

    private static func boundingBox(_ contour: [Vec2]) -> Box {
        var box = Box(
            minX: .greatestFiniteMagnitude, minY: .greatestFiniteMagnitude,
            maxX: -.greatestFiniteMagnitude, maxY: -.greatestFiniteMagnitude)
        for p in contour {
            box.minX = min(box.minX, p.x)
            box.minY = min(box.minY, p.y)
            box.maxX = max(box.maxX, p.x)
            box.maxY = max(box.maxY, p.y)
        }
        return box
    }

    /// `outer` が `inner` を完全に含むか（先に弾いて多角形判定の回数を減らす）。
    private static func contains(_ outer: Box, _ inner: Box) -> Bool {
        outer.minX <= inner.minX && outer.minY <= inner.minY
            && outer.maxX >= inner.maxX && outer.maxY >= inner.maxY
    }

    /// 多角形の内外判定（レイキャスト）。
    private static func contains(polygon: [Vec2], point: Vec2) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
