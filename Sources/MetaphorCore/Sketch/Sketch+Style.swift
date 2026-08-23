// MARK: - Style (Shape Modes, Color, Fill, Stroke, Blend, Tint)

extension Sketch {

    // MARK: Shape Mode Settings

    /// Sets the rectangle drawing mode.
    ///
    /// - Note: Affects **2D only** (it is for ``rect(_:_:_:_:)`` and does not change how the
    ///   position of 3D primitives is interpreted; ADR-0005).
    ///
    /// - Parameter mode: The interpretation mode for rectangles.
    ///
    /// ### Result
    ///
    /// The same ``rect(_:_:_:_:)`` arguments land at a different position and size depending on
    /// the mode (the default ``RectMode/corner`` on the left, ``RectMode/center`` on the right).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rectMode(_:) の実行結果](https://i.gyazo.com/6ac18537fecfcc54f72e033ecca4fa67.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       rectMode(.corner)
    ///       fill(255, 190, 60)
    ///       rect(60, 130, 100, 100)
    ///
    ///       rectMode(.center)
    ///       fill(80, 170, 255)
    ///       rect(340, 180, 100, 100)
    ///       ```
    ///    }
    /// }
    public func rectMode(_ mode: RectMode) {
        context.rectMode(mode)
    }

    /// Sets the ellipse drawing mode.
    ///
    /// - Note: Affects **2D only** (it is for ``ellipse(_:_:_:_:)`` and does not change how the
    ///   position of 3D primitives is interpreted; ADR-0005).
    ///
    /// - Parameter mode: The interpretation mode for ellipses.
    ///
    /// ### Result
    ///
    /// The same ``ellipse(_:_:_:_:)`` arguments land at a different position depending on the mode
    /// (the default ``EllipseMode/center`` on the left, ``EllipseMode/corner`` on the right).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ellipseMode(_:) の実行結果](https://i.gyazo.com/4873852670151d89625389351ee618d0.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       ellipseMode(.center)
    ///       fill(255, 190, 60)
    ///       ellipse(140, 180, 140, 100)
    ///
    ///       ellipseMode(.corner)
    ///       fill(80, 170, 255)
    ///       ellipse(280, 130, 140, 100)
    ///       ```
    ///    }
    /// }
    public func ellipseMode(_ mode: EllipseMode) {
        context.ellipseMode(mode)
    }

    /// Sets the image drawing mode.
    ///
    /// - Note: Affects **2D only** (it is for `image()` and has no effect on 3D ``texture(_:)``;
    ///   ADR-0005).
    ///
    /// - Parameter mode: The interpretation mode for images.
    public func imageMode(_ mode: ImageMode) {
        context.imageMode(mode)
    }

    // MARK: Color Mode

    /// Sets the color mode with a maximum value for each channel.
    ///
    /// The default color mode is RGB from 0 to 255 (the same as Processing).
    /// Channels that are not specified keep their current maximum.
    ///
    /// - Note: Affects **both 2D and 3D** (channel interpretation for ``fill(_:)-(Color)`` and
    ///   ``stroke(_:)-(Color)`` stays in step across both canvases; ADR-0005).
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value of the first channel. Keeps the current value when omitted.
    ///   - max2: The maximum value of the second channel. Keeps the current value when omitted.
    ///   - max3: The maximum value of the third channel. Keeps the current value when omitted.
    ///   - maxA: The maximum value of the alpha channel. Keeps the current value when omitted.
    ///
    /// ### Result
    ///
    /// With ``ColorSpace/hsb``, the first channel becomes the hue.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![colorMode(_:_:_:_:_:) の実行結果](https://i.gyazo.com/9f0d6c7c8fee971710865b73239fa811.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       colorMode(.hsb, 360, 100, 100, 100)
    ///       noStroke()
    ///       for i in 0..<12 {
    ///           fill(Float(i) * 30, 80, 100)
    ///           rect(Float(i) * 40, 120, 40, 120)
    ///       }
    ///       ```
    ///    }
    /// }
    public func colorMode(
        _ space: ColorSpace, _ max1: Float? = nil, _ max2: Float? = nil, _ max3: Float? = nil,
        _ maxA: Float? = nil
    ) {
        context.colorMode(space, max1, max2, max3, maxA)
    }

    /// Sets the color mode with a single maximum value shared by every channel.
    ///
    /// - Note: Affects **both 2D and 3D** (channel interpretation for ``fill(_:)-(Color)`` and
    ///   ``stroke(_:)-(Color)`` stays in step across both canvases; ADR-0005).
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The maximum value for every channel.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        context.colorMode(space, maxAll)
    }

    // MARK: Background

    /// Clears the canvas with the given color.
    ///
    /// **Clearing replaces rather than composites.** `blendMode()` has no effect, and a background
    /// color with α < 1 is written as it is instead of mixing with what is underneath
    /// (`background(0, 0, 0, 0)` returns the canvas to transparent). To leave a faint trace of the
    /// previous frame, draw a `rect()` in the background color across the whole screen
    /// (ADR-0012 / #829).
    ///
    /// - Note: Affects **both 2D and 3D**. The offscreen canvas is shared between 2D and 3D, so any
    ///   3D already drawn is erased along with it (ADR-0005).
    ///
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        context.background(color)
    }

    /// Clears the canvas with a grayscale value.
    ///
    /// - Note: Affects **both 2D and 3D**. The offscreen canvas is shared between 2D and 3D, so any
    ///   3D already drawn is erased along with it (ADR-0005).
    ///
    /// - Parameter gray: The grayscale brightness. In the default color mode, 0 is black and 255 is
    ///   white.
    public func background(_ gray: Float) {
        context.background(gray)
    }

    /// Clears the canvas with the given color channel values.
    ///
    /// - Note: Affects **both 2D and 3D**. The offscreen canvas is shared between 2D and 3D, so any
    ///   3D already drawn is erased along with it (ADR-0005).
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The alpha value (optional).
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.background(v1, v2, v3, a)
    }

    // MARK: Style

    /// Sets the fill color.
    ///
    /// - Note: Affects **both 2D and 3D**. In 3D it becomes the color of primitives and meshes, and
    ///   when a ``texture(_:)`` is applied it is multiplied into the texture color (ADR-0005).
    ///
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        context.fill(color)
    }

    /// Sets the fill color from channel values.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it becomes the color of primitives and meshes;
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The alpha value (optional).
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.fill(v1, v2, v3, a)
    }

    /// Sets the fill color from a grayscale value.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it becomes the color of primitives and meshes;
    ///   ADR-0005).
    ///
    /// - Parameter gray: The grayscale brightness.
    public func fill(_ gray: Float) {
        context.fill(gray)
    }

    /// Sets the fill color from a grayscale value with alpha.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it becomes the color of primitives and meshes;
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func fill(_ gray: Float, _ alpha: Float) {
        context.fill(gray, alpha)
    }

    /// Disables filling shapes.
    ///
    /// - Note: Affects **both 2D and 3D**. In 3D the faces stop being drawn, and calling
    ///   ``noStroke()`` as well leaves that shape drawing nothing at all (ADR-0005).
    ///
    /// ### Result
    ///
    /// Only the fill disappears; the stroke remains (the right one is after calling ``noFill()``).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![noFill() の実行結果](https://i.gyazo.com/01df4c758c2b0ef1adef4252a47eef79.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(6)
    ///       fill(80, 170, 255)
    ///       circle(150, 180, 150)
    ///       noFill()
    ///       circle(330, 180, 150)
    ///       ```
    ///    }
    /// }
    public func noFill() {
        context.noFill()
    }

    /// Sets the stroke color.
    ///
    /// - Note: Affects **both 2D and 3D**. However, ``strokeWeight(_:)``, which decides the
    ///   thickness, is **2D only**, so the thickness of 3D lines cannot be changed (ADR-0005).
    ///
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        context.stroke(color)
    }

    /// Sets the stroke color from channel values.
    ///
    /// - Note: Affects **both 2D and 3D** (``strokeWeight(_:)``, which decides the thickness, is
    ///   2D only; ADR-0005).
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The alpha value (optional).
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.stroke(v1, v2, v3, a)
    }

    /// Sets the stroke color from a grayscale value.
    ///
    /// - Note: Affects **both 2D and 3D** (``strokeWeight(_:)``, which decides the thickness, is
    ///   2D only; ADR-0005).
    ///
    /// - Parameter gray: The grayscale brightness.
    public func stroke(_ gray: Float) {
        context.stroke(gray)
    }

    /// Sets the stroke color from a grayscale value with alpha.
    ///
    /// - Note: Affects **both 2D and 3D** (``strokeWeight(_:)``, which decides the thickness, is
    ///   2D only; ADR-0005).
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        context.stroke(gray, alpha)
    }

    /// Disables stroking shapes.
    ///
    /// - Note: Affects **both 2D and 3D**. 3D has no stroke by default to begin with, so the
    ///   appearance does not change unless ``stroke(_:)-(Color)`` has been called (ADR-0005).
    ///
    /// ### Result
    ///
    /// Only the outline disappears; the fill remains (the right one is after calling
    /// ``noStroke()``).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![noStroke() の実行結果](https://i.gyazo.com/6196c1479b479d50c9d06fa4943ad56d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255)
    ///       strokeWeight(8)
    ///       fill(255, 190, 60)
    ///       circle(150, 180, 150)
    ///       noStroke()
    ///       circle(330, 180, 150)
    ///       ```
    ///    }
    /// }
    public func noStroke() {
        context.noStroke()
    }

    /// Sets the stroke weight (line width).
    ///
    /// - Note: Affects **2D only** (it has no effect on 3D wireframes; ADR-0005).
    ///
    /// - Parameter weight: The stroke width, in pixels.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeWeight(_:) の実行結果](https://i.gyazo.com/d8e6cd010c5b5629ebfd57cf15e400ba.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255)
    ///       var y: Float = 70
    ///       for weight in [1, 4, 12, 28] {
    ///           strokeWeight(Float(weight))
    ///           line(80, y, 400, y)
    ///           y += 70
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeWeight(_ weight: Float) {
        context.strokeWeight(weight)
    }

    /// Sets the stroke cap style.
    ///
    /// - Note: Affects **2D only** (like ``strokeWeight(_:)``, it has no effect on 3D lines;
    ///   ADR-0005).
    ///
    /// - Parameter cap: The line cap style.
    ///
    /// ### Result
    ///
    /// From the top: ``StrokeCap/butt`` (the default) / ``StrokeCap/round`` /
    /// ``StrokeCap/square``. The thicker the line, the more the difference shows.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeCap(_:) の実行結果](https://i.gyazo.com/adb3a1d176e5578166f0633159e709a3.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       let caps: [StrokeCap] = [
    ///           .butt, .round, .square
    ///       ]
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(26)
    ///       var y: Float = 90
    ///       for cap in caps {
    ///           strokeCap(cap)
    ///           line(140, y, 340, y)
    ///           y += 90
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeCap(_ cap: StrokeCap) {
        context.strokeCap(cap)
    }

    /// Sets the stroke join style.
    ///
    /// - Note: Affects **2D only** (like ``strokeWeight(_:)``, it has no effect on 3D lines;
    ///   ADR-0005).
    ///
    /// - Parameter join: The line join style.
    ///
    /// ### Result
    ///
    /// From the left: ``StrokeJoin/miter`` (the default; keeps corners sharp) /
    /// ``StrokeJoin/round`` (rounds them with an arc of radius `strokeWeight / 2`) /
    /// ``StrokeJoin/bevel`` (cuts them off flat). The thicker the line, the more the difference
    /// shows.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeJoin(_:) の実行結果](https://i.gyazo.com/7d327109e9183273cabce9fb05601bf5.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       let joins: [StrokeJoin] = [
    ///           .miter, .round, .bevel
    ///       ]
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(22)
    ///       var x: Float = 70
    ///       for join in joins {
    ///           strokeJoin(join)
    ///           beginShape()
    ///           vertex(x, 240)
    ///           vertex(x + 45, 120)
    ///           vertex(x + 90, 240)
    ///           endShape()
    ///           x += 140
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeJoin(_ join: StrokeJoin) {
        context.strokeJoin(join)
    }

    /// Sets the blend mode for subsequent drawing operations.
    ///
    /// In every mode, the alpha of `fill` and `stroke` expresses **how strongly the blend takes
    /// effect** (ADR-0012). `α = 0` does nothing in any mode, and `α = 0.5` lands exactly halfway
    /// between the backdrop and the result that mode composites. The resulting alpha is
    /// `src.a + dst.a · (1 − src.a)` regardless of the mode, so ``blendMode(_:)`` never eats into
    /// the opacity of the area it paints.
    ///
    /// - Note: Affects **2D only** (3D follows the opaque/additive material settings;
    ///   ADR-0005).
    ///
    /// - Note: ``BlendMode/multiply`` / ``BlendMode/screen`` / ``BlendMode/subtract`` /
    ///   ``BlendMode/lightest`` / ``BlendMode/darkest`` / ``BlendMode/difference`` /
    ///   ``BlendMode/exclusion`` are implemented with dedicated fragments that read the destination
    ///   color, so they **cannot be combined with a custom 2D shader** (while one is applied they
    ///   fall back to ``BlendMode/alpha`` and warn once on the console).
    ///
    /// - Parameter mode: The blend mode to apply.
    ///
    /// ### Result
    ///
    /// ``BlendMode/additive`` brightens the overlaps, while ``BlendMode/alpha`` (the default) puts
    /// whatever is drawn later on top.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![blendMode(_:) の実行結果](https://i.gyazo.com/c073f497a82f5354038960f521ec3029.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       blendMode(.additive)
    ///       fill(255, 60, 60)
    ///       circle(190, 150, 150)
    ///       fill(60, 255, 60)
    ///       circle(260, 150, 150)
    ///       fill(60, 60, 255)
    ///       circle(225, 220, 150)
    ///       ```
    ///    }
    /// }
    public func blendMode(_ mode: BlendMode) {
        context.blendMode(mode)
    }

    // MARK: Tint

    /// Sets the tint color for images.
    ///
    /// - Note: Affects **2D only**. It applies to images drawn with `image()` and has no effect on
    ///   3D ``texture(_:)`` — a 3D texture is tinted by multiplying in the ``fill(_:)-(Color)``
    ///   color, so there is no dedicated tint slot to begin with (ADR-0005). Use
    ///   ``fill(_:)-(Color)`` when you want to multiply a color into textured 3D.
    ///
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) {
        context.tint(color)
    }

    /// Sets the image tint color from channel values.
    ///
    /// - Note: Affects **2D only** (a 3D texture is tinted with the ``fill(_:)-(Color)`` color;
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The alpha value (optional).
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.tint(v1, v2, v3, a)
    }

    /// Sets the image tint from a grayscale value.
    ///
    /// - Note: Affects **2D only** (a 3D texture is tinted with the ``fill(_:)-(Color)`` color;
    ///   ADR-0005).
    ///
    /// - Parameter gray: The grayscale brightness.
    public func tint(_ gray: Float) {
        context.tint(gray)
    }

    /// Sets the image tint from a grayscale value with alpha.
    ///
    /// - Note: Affects **2D only** (a 3D texture is tinted with the ``fill(_:)-(Color)`` color;
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func tint(_ gray: Float, _ alpha: Float) {
        context.tint(gray, alpha)
    }

    /// Clears the image tint.
    ///
    /// - Note: Affects **2D only** (the counterpart to ``tint(_:)-(Color)``; ADR-0005).
    public func noTint() {
        context.noTint()
    }
}
