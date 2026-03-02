import Metal
import simd

// MARK: - Image

extension Canvas2D {

    /// 画像を描画（元サイズ）
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        image(img, x, y, img.width, img.height)
    }

    /// 画像をサイズ指定で描画（座標解釈はimageModeに依存）
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let dx: Float, dy: Float, dw: Float, dh: Float
        switch currentImageMode {
        case .corner:
            dx = x; dy = y; dw = w; dh = h
        case .center:
            dx = x - w / 2; dy = y - h / 2; dw = w; dh = h
        case .corners:
            dx = min(x, w); dy = min(y, h); dw = abs(w - x); dh = abs(h - y)
        }
        drawTexturedQuad(texture: img.texture, x: dx, y: dy, w: dw, h: dh)
    }

    /// サブイメージ描画（スプライトシート/タイルマップ用）
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        drawTexturedQuad(
            texture: img.texture, x: dx, y: dy, w: dw, h: dh,
            srcX: sx, srcY: sy, srcW: sw, srcH: sh
        )
    }

    // MARK: - Private: Textured Quad (Batched)

    /// テクスチャ付きクワッドをバッファに蓄積（同一テクスチャはバッチされる）
    func drawTexturedQuad(
        texture: MTLTexture, x: Float, y: Float, w: Float, h: Float,
        srcX: Float = 0, srcY: Float = 0, srcW: Float? = nil, srcH: Float? = nil
    ) {
        guard encoder != nil else { return }

        // カラー頂点が蓄積されていたら先にフラッシュ（描画順序保持）
        if vertexCount > 0 {
            flushColorVertices()
        }

        // テクスチャが変わったらフラッシュ
        if let current = currentBoundTexture, current !== texture {
            flushTexturedVertices()
        }

        currentBoundTexture = texture
        hasDrawnAnything = true

        // バッファオーバーフロー検査
        if texturedBufferOffset + texturedVertexCount + 6 > maxTexturedVertices {
            flushTexturedVertices()
            texturedBufferOffset = 0
        }

        let tw = Float(texture.width)
        let th = Float(texture.height)
        let u0 = srcX / tw
        let v0 = srcY / th
        let u1 = (srcX + (srcW ?? tw)) / tw
        let v1 = (srcY + (srcH ?? th)) / th

        let tint = hasTint ? tintColor : SIMD4<Float>(1, 1, 1, 1)
        let r = tint.x, g = tint.y, b = tint.z, a = tint.w
        let p0 = currentTransform * SIMD3<Float>(x, y, 1)
        let p1 = currentTransform * SIMD3<Float>(x + w, y, 1)
        let p2 = currentTransform * SIMD3<Float>(x + w, y + h, 1)
        let p3 = currentTransform * SIMD3<Float>(x, y + h, 1)

        let verts = texturedVertices
        let off = texturedBufferOffset + texturedVertexCount

        verts[off + 0] = TexturedVertex2D(posX: p0.x, posY: p0.y, u: u0, v: v0, r: r, g: g, b: b, a: a)
        verts[off + 1] = TexturedVertex2D(posX: p1.x, posY: p1.y, u: u1, v: v0, r: r, g: g, b: b, a: a)
        verts[off + 2] = TexturedVertex2D(posX: p2.x, posY: p2.y, u: u1, v: v1, r: r, g: g, b: b, a: a)
        verts[off + 3] = TexturedVertex2D(posX: p0.x, posY: p0.y, u: u0, v: v0, r: r, g: g, b: b, a: a)
        verts[off + 4] = TexturedVertex2D(posX: p2.x, posY: p2.y, u: u1, v: v1, r: r, g: g, b: b, a: a)
        verts[off + 5] = TexturedVertex2D(posX: p3.x, posY: p3.y, u: u0, v: v1, r: r, g: g, b: b, a: a)

        texturedVertexCount += 6
    }

    /// アトラスからバッチテキスト描画（グリフをテクスチャバッファに蓄積）
    func drawTextFromAtlas(
        texture: MTLTexture,
        glyphs: [PositionedGlyph],
        x: Float, y: Float
    ) {
        guard encoder != nil, !glyphs.isEmpty else { return }

        // カラー頂点が蓄積されていたら先にフラッシュ
        if vertexCount > 0 {
            flushColorVertices()
        }

        // テクスチャが変わったらフラッシュ
        if let current = currentBoundTexture, current !== texture {
            flushTexturedVertices()
        }

        currentBoundTexture = texture
        hasDrawnAnything = true

        let verticesNeeded = glyphs.count * 6

        // バッファオーバーフロー検査
        if texturedBufferOffset + texturedVertexCount + verticesNeeded > maxTexturedVertices {
            flushTexturedVertices()
            texturedBufferOffset = 0
        }

        let tint = hasTint ? tintColor : SIMD4<Float>(1, 1, 1, 1)
        let r = tint.x, g = tint.y, b = tint.z, a = tint.w
        let verts = texturedVertices
        var off = texturedBufferOffset + texturedVertexCount

        for glyph in glyphs {
            let gx = x + glyph.x
            let gy = y + glyph.y
            let gw = glyph.width
            let gh = glyph.height

            let p0 = currentTransform * SIMD3<Float>(gx, gy, 1)
            let p1 = currentTransform * SIMD3<Float>(gx + gw, gy, 1)
            let p2 = currentTransform * SIMD3<Float>(gx + gw, gy + gh, 1)
            let p3 = currentTransform * SIMD3<Float>(gx, gy + gh, 1)

            verts[off + 0] = TexturedVertex2D(posX: p0.x, posY: p0.y, u: glyph.u0, v: glyph.v0, r: r, g: g, b: b, a: a)
            verts[off + 1] = TexturedVertex2D(posX: p1.x, posY: p1.y, u: glyph.u1, v: glyph.v0, r: r, g: g, b: b, a: a)
            verts[off + 2] = TexturedVertex2D(posX: p2.x, posY: p2.y, u: glyph.u1, v: glyph.v1, r: r, g: g, b: b, a: a)
            verts[off + 3] = TexturedVertex2D(posX: p0.x, posY: p0.y, u: glyph.u0, v: glyph.v0, r: r, g: g, b: b, a: a)
            verts[off + 4] = TexturedVertex2D(posX: p2.x, posY: p2.y, u: glyph.u1, v: glyph.v1, r: r, g: g, b: b, a: a)
            verts[off + 5] = TexturedVertex2D(posX: p3.x, posY: p3.y, u: glyph.u0, v: glyph.v1, r: r, g: g, b: b, a: a)
            off += 6
        }

        texturedVertexCount += verticesNeeded
    }
}
