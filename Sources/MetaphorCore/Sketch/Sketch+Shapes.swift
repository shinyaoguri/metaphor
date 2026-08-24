// MARK: - 2D Transform & Shapes

extension Sketch {

    // MARK: 2D Transform Stack

    /// Saves the current transform and style state onto the stack.
    ///
    /// - Note: Affects **both 2D and 3D**. What separates it from ``pushMatrix()`` is not what it
    ///   affects but whether style is included: this one saves transform + style, while
    ///   ``pushMatrix()`` saves the transform only.
    ///
    /// ### Result
    ///
    /// Calling ``pop()`` rewinds both the transform and the style changed in between
    /// (the blue rectangle is unaffected by ``translate(_:_:)``).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![push() の実行結果](https://i.gyazo.com/ed6c97031c145c2561123ddf7fa4d8ad.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       push()
    ///       translate(120, 100)
    ///       fill(255, 190, 60)
    ///       rect(-60, -50, 120, 100)
    ///       pop()
    ///       fill(80, 170, 255)
    ///       rect(260, 210, 120, 100)
    ///       ```
    ///    }
    /// }
    public func push() {
        context.push()
    }

    /// Restores the most recently saved transform and style state from the stack.
    ///
    /// - Note: Affects **both 2D and 3D** (the counterpart to ``push()``).
    public func pop() {
        context.pop()
    }

    /// Saves the current style state (fill, stroke, and so on) onto the stack.
    ///
    /// - Note: Affects **both 2D and 3D**. What separates it from ``push()`` is that it does not
    ///   include the transform: this one saves the style only (ADR-0005 Amendment 2026-08-02).
    public func pushStyle() {
        context.pushStyle()
    }

    /// Restores the most recently saved style state from the stack.
    ///
    /// - Note: Affects **both 2D and 3D** (the counterpart to ``pushStyle()``).
    public func popStyle() {
        context.popStyle()
    }

    /// Applies a translation to the current transform.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it is a translation with z = 0, compatible with
    ///   Processing P3D; ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameters:
    ///   - x: The amount to move horizontally.
    ///   - y: The amount to move vertically.
    ///
    /// ### Result
    ///
    /// The origin of subsequent drawing moves, so the same ``rect(_:_:_:_:)`` arguments land
    /// somewhere else.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![translate(_:_:) の実行結果](https://i.gyazo.com/99b0ad0fcee4710064a4f8b5f0d59146.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(40, 40, 120, 100)
    ///       translate(180, 140)
    ///       fill(80, 170, 255)
    ///       rect(40, 40, 120, 100)
    ///       ```
    ///    }
    /// }
    public func translate(_ x: Float, _ y: Float) {
        context.translate(x, y)
    }

    /// Applies a rotation to the current transform.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it rotates around the z axis, the same as
    ///   ``rotateZ(_:)``, compatible with Processing P3D; ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The rotation angle, in radians.
    ///
    /// ### Result
    ///
    /// Rotation is centered on the origin, so move the origin with ``translate(_:_:)`` before
    /// rotating.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotate(_:) の実行結果（動き）](https://i.gyazo.com/8656acd6a04201a802b96f14ac58ac0a.gif)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       translate(width / 2, height / 2)
    ///       rotate(Float(frameCount) * 0.02)
    ///       fill(255, 190, 60)
    ///       rect(-70, -70, 140, 140)
    ///       ```
    ///    }
    /// }
    public func rotate(_ angle: Float) {
        context.rotate(angle)
    }

    /// Applies a non-uniform scale to the current transform.
    ///
    /// - Note: Affects **both 2D and 3D** (in 3D it scales with the z axis left at 1, compatible
    ///   with Processing P3D; ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    ///
    /// ### Result
    ///
    /// Scaling is anchored at the origin, so the position moves by the factor as well.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![scale(_:_:) の実行結果](https://i.gyazo.com/6582ff8b7eb8b8487a4d49b9a3cb4459.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(60, 60, 120, 90)
    ///       scale(1.6, 2.0)
    ///       fill(80, 170, 255)
    ///       rect(60, 60, 120, 90)
    ///       ```
    ///    }
    /// }
    public func scale(_ sx: Float, _ sy: Float) {
        context.scale(sx, sy)
    }

    /// Applies a uniform scale to the current transform.
    ///
    /// - Note: Affects **both 2D and 3D**.
    ///
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) {
        context.scale(s)
    }

    /// Multiplies the current 2D transform by a 3x3 matrix.
    ///
    /// - Note: Affects **2D only**. For 3D, use ``applyMatrix(_:)`` (the `float4x4` version). The
    ///   unification with P3D semantics is limited to ``translate(_:_:)`` / ``rotate(_:)`` /
    ///   ``scale(_:_:)``, and applying a matrix directly is out of scope
    ///   (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter matrix: The 3x3 matrix to concatenate.
    public func applyMatrix(_ matrix: float3x3) {
        context.applyMatrix(matrix)
    }

    /// Multiplies the current 2D transform by a Processing-style six-component affine matrix.
    ///
    /// The components are row-major and the transform is `x' = n00*x + n01*y + n02`,
    /// `y' = n10*x + n11*y + n12` (compatible with Processing's
    /// `applyMatrix(n00, n01, n02, n10, n11, n12)`).
    ///
    /// - Note: Affects **2D only** (ADR-0005 Amendment 2026-08-02; out of scope for the P3D
    ///   unification).
    public func applyMatrix(
        _ n00: Float, _ n01: Float, _ n02: Float,
        _ n10: Float, _ n11: Float, _ n12: Float
    ) {
        context.applyMatrix(n00, n01, n02, n10, n11, n12)
    }

    /// Multiplies the current 3D transform by a 4x4 matrix.
    ///
    /// - Note: Affects **3D only**. For 2D, use ``applyMatrix(_:)`` (the `float3x3` version)
    ///   (ADR-0005).
    ///
    /// - Parameter matrix: The 4x4 matrix to concatenate.
    public func applyMatrix(_ matrix: float4x4) {
        context.applyMatrix(matrix)
    }

    /// Resets the current transformation matrix to the identity matrix.
    ///
    /// - Note: Affects **both 2D and 3D** (the same category as ``pushMatrix()``/``popMatrix()``;
    ///   ADR-0005).
    public func resetMatrix() {
        context.resetMatrix()
    }

    /// Applies a shear along the x axis to the current transform.
    ///
    /// `x' = x + tan(angle) * y` (compatible with Processing's `shearX()`).
    ///
    /// - Note: Affects **2D only**. The unification with P3D semantics is limited to
    ///   ``translate(_:_:)`` / ``rotate(_:)`` / ``scale(_:_:)``, and shear is out of scope
    ///   (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The shear angle, in radians.
    ///
    /// ### Result
    ///
    /// The larger the y, the further right it shifts (blue below, the original shape above).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shearX(_:) の実行結果](https://i.gyazo.com/b3c4494e7b7eb88b4bd839c0ced4d974.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(80, 40, 140, 90)
    ///       translate(0, 150)
    ///       shearX(0.4)
    ///       fill(80, 170, 255)
    ///       rect(80, 40, 140, 90)
    ///       ```
    ///    }
    /// }
    public func shearX(_ angle: Float) {
        context.shearX(angle)
    }

    /// Applies a shear along the y axis to the current transform.
    ///
    /// `y' = y + tan(angle) * x` (compatible with Processing's `shearY()`).
    ///
    /// - Note: Affects **2D only**. The unification with P3D semantics is limited to
    ///   ``translate(_:_:)`` / ``rotate(_:)`` / ``scale(_:_:)``, and shear is out of scope
    ///   (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The shear angle, in radians.
    ///
    /// ### Result
    ///
    /// The larger the x, the further down it shifts (blue on the right, the original shape on the
    /// left).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shearY(_:) の実行結果](https://i.gyazo.com/a5344a38d3dfaf3943dba560232c20a8.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(50, 60, 120, 90)
    ///       translate(200, 0)
    ///       shearY(0.35)
    ///       fill(80, 170, 255)
    ///       rect(50, 60, 120, 90)
    ///       ```
    ///    }
    /// }
    public func shearY(_ angle: Float) {
        context.shearY(angle)
    }

    /// Returns the screen x coordinate at which a 2D model coordinate is drawn.
    ///
    /// - Note: **2D only**. For 3D, use ``screenX(_:_:_:)`` (the three-argument version).
    public func screenX(_ x: Float, _ y: Float) -> Float {
        context.screenPosition(x, y).x
    }

    /// Returns the screen y coordinate at which a 2D model coordinate is drawn.
    ///
    /// - Note: **2D only**. For 3D, use ``screenY(_:_:_:)`` (the three-argument version).
    public func screenY(_ x: Float, _ y: Float) -> Float {
        context.screenPosition(x, y).y
    }

    /// Returns the screen x coordinate at which a 3D model coordinate is drawn.
    ///
    /// - Note: Affects **3D only** (for 2D coordinates use ``screenX(_:_:)``, the two-argument
    ///   version; ADR-0005).
    ///
    /// - Important: For points behind the camera the value is flipped through the origin.
    ///   Tell them apart with ``isInFront(_:_:_:)``.
    public func screenX(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).x
    }

    /// Returns the screen y coordinate at which a 3D model coordinate is drawn.
    ///
    /// - Note: Affects **3D only** (for 2D coordinates use ``screenY(_:_:)``, the two-argument
    ///   version; ADR-0005).
    ///
    /// - Important: For points behind the camera the value is flipped through the origin.
    ///   Tell them apart with ``isInFront(_:_:_:)``.
    public func screenY(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).y
    }

    /// Returns the normalized device depth (0...1) of a 3D model coordinate.
    ///
    /// The nearer the point, the smaller the value (the equivalent of Processing's `screenZ()`).
    ///
    /// - Note: Affects **3D only** (2D drawing has no depth; ADR-0005).
    ///
    /// - Important: The value stays within 0...1 only while the point is inside the view frustum.
    ///   Behind the camera it goes above 1, and between the camera and the near plane it goes
    ///   negative. Reject points behind the camera with ``isInFront(_:_:_:)`` before using it.
    public func screenZ(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).z
    }

    /// Returns whether a point in 3D model coordinates lies in front of the camera plane.
    ///
    /// ``screenX(_:_:_:)`` / ``screenY(_:_:_:)`` / ``screenZ(_:_:_:)`` return flipped values for
    /// points behind the camera, and the return value alone cannot separate them from points in
    /// front. Put this check in before placing labels or culling.
    ///
    /// ```swift
    /// if isInFront(px, py, pz) {
    ///     text("label", screenX(px, py, pz), screenY(px, py, pz))
    /// }
    /// ```
    ///
    /// - Note: Affects **3D only** (only 3D has a camera plane; ADR-0005).
    ///
    /// - Note: true guarantees only that the value is not flipped; it does not guarantee that the
    ///   point is on screen. An orthographic projection never flips, so it always returns true.
    public func isInFront(_ x: Float, _ y: Float, _ z: Float) -> Bool {
        context.isInFront(x, y, z)
    }

    /// Returns the world x coordinate of a 3D model coordinate taken through the current transform.
    ///
    /// It returns where the point ends up in world space once the `translate`, `rotateX/Y/Z`, and
    /// `scale` pushed onto the transform stack have been applied (the equivalent of Processing's
    /// `modelX()`). The typical use is to note a position inside ``pushMatrix()`` …
    /// ``popMatrix()`` and then place something else at the same spot after leaving it.
    ///
    /// ```swift
    /// pushMatrix()
    /// translate(100, 50, 0)
    /// rotateY(angle)
    /// translate(0, 0, 60)
    /// // note where the tip of the rotation lands in the world
    /// let wx = modelX(0, 0, 0)
    /// let wy = modelY(0, 0, 0)
    /// let wz = modelZ(0, 0, 0)
    /// popMatrix()
    ///
    /// pushMatrix()
    /// translate(wx, wy, wz)   // the same spot is reachable from outside the transform stack
    /// box(10)
    /// popMatrix()
    /// ```
    ///
    /// - Note: **3D only**. Use ``screenX(_:_:_:)`` when you want screen coordinates in pixels.
    /// - Important: What comes back is a **world coordinate**, independent of the camera. Changing
    ///   ``camera(eye:center:up:)`` or ``perspective(fov:near:far:)`` does not change the value
    ///   (the same semantics as Processing's `modelX()`).
    public func modelX(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).x
    }

    /// Returns the world y coordinate of a 3D model coordinate taken through the current transform.
    ///
    /// - Note: **3D only**. See ``modelX(_:_:_:)`` for an example and the caveats.
    /// - Important: It is independent of the camera (same semantics as Processing's `modelY()`).
    public func modelY(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).y
    }

    /// Returns the world z coordinate of a 3D model coordinate taken through the current transform.
    ///
    /// - Note: **3D only**. See ``modelX(_:_:_:)`` for an example and the caveats.
    ///   Use ``screenZ(_:_:_:)`` when you want the screen depth (0...1).
    /// - Important: It is independent of the camera (same semantics as Processing's `modelZ()`).
    public func modelZ(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).z
    }

    // MARK: 2D Shapes

    /// Draws a rectangle.
    ///
    /// - Note: Affects **2D only** (the 3D box is ``box(_:_:_:)`` and the 3D plane is
    ///   ``plane(_:_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///
    /// ### Result
    ///
    /// How x and y are interpreted changes with ``rectMode(_:)`` (the top-left corner by default).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:) の実行結果](https://i.gyazo.com/353e3c185f55a74b535e66da3cd85262.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       rect(60, 90, 160, 180)
    ///       ```
    ///    }
    /// }
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.rect(x, y, w, h)
    }

    /// Draws a rounded rectangle with a uniform corner radius.
    ///
    /// - Note: Affects **2D only** (there is no rounded 3D primitive; ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - r: The corner radius.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:_:) の実行結果](https://i.gyazo.com/0c7c14f4b93a5a76ae0345d776144159.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       rect(120, 90, 240, 180, 40)
    ///       ```
    ///    }
    /// }
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        context.rect(x, y, w, h, r)
    }

    /// Draws a rounded rectangle with a separate corner radius for each corner.
    ///
    /// - Note: Affects **2D only** (there is no rounded 3D primitive; ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - tl: The top-left corner radius.
    ///   - tr: The top-right corner radius.
    ///   - br: The bottom-right corner radius.
    ///   - bl: The bottom-left corner radius.
    ///
    /// ### Result
    ///
    /// The radii are given in the order top-left, top-right, bottom-right, bottom-left.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/41bbd3412e6f36396c93f0b52c9a6384.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       rect(
    ///           120, 90, 240, 180,
    ///           60, 0, 60, 0
    ///       )
    ///       ```
    ///    }
    /// }
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        context.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// Draws a rectangle filled with a linear gradient.
    ///
    /// - Note: Affects **2D only** (a 3D gradient is built with a shader or with vertex colors.
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - c1: The start color.
    ///   - c2: The end color.
    ///   - axis: The direction of the gradient.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![linearGradient(_:_:_:_:_:_:axis:) の実行結果](https://i.gyazo.com/23aa77a3c8669991320fadbb7db44090.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       linearGradient(
    ///           60, 60, 360, 240,
    ///           Color(r: 1, g: 0.75, b: 0.24),
    ///           Color(r: 0.31, g: 0.24, b: 0.63)
    ///       )
    ///       ```
    ///    }
    /// }
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        context.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// Draws a circle filled with a radial gradient.
    ///
    /// - Note: Affects **2D only** (a 3D gradient is built with a shader or with vertex colors.
    ///   ADR-0005).
    ///
    /// - Parameters:
    ///   - cx: The x coordinate of the center.
    ///   - cy: The y coordinate of the center.
    ///   - radius: The outer radius.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the outer edge.
    ///   - segments: The number of segments used for smoothness.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![radialGradient(_:_:_:_:_:segments:) の実行結果](https://i.gyazo.com/b0ed7cd91d7755617b9d404847fe07f5.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       radialGradient(
    ///           240, 180, 150,
    ///           Color(r: 1, g: 0.94, b: 0.78),
    ///           Color(r: 0.16, g: 0.16, b: 0.35)
    ///       )
    ///       ```
    ///    }
    /// }
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        context.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// Draws an ellipse.
    ///
    /// - Note: Affects **2D only** (the 3D sphere is ``sphere(_:detail:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width (the horizontal diameter).
    ///   - h: The height (the vertical diameter).
    ///
    /// ### Result
    ///
    /// How x and y are interpreted changes with ``ellipseMode(_:)`` (the center by default).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ellipse(_:_:_:_:) の実行結果](https://i.gyazo.com/53a1b556de5a248e28f134d21f84ab8b.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       ellipse(240, 180, 260, 150)
    ///       ```
    ///    }
    /// }
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.ellipse(x, y, w, h)
    }

    /// Draws a circle.
    ///
    /// - Note: Affects **2D only** (the 3D sphere is ``sphere(_:detail:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the center.
    ///   - y: The y coordinate of the center.
    ///   - diameter: The diameter of the circle.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![circle(_:_:_:) の実行結果](https://i.gyazo.com/5db1a81abf5604a4ee8a316406fc5049.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       circle(width / 2, height / 2, 200)
    ///       ```
    ///    }
    /// }
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        context.circle(x, y, diameter)
    }

    /// Draws many circles in a single batch.
    ///
    /// Instead of calling `circle()` many times over, it draws an array of ``CircleInstance``
    /// values — each carrying a position, a diameter, and a color — together through the compact
    /// instancing path.
    ///
    /// - Note: Affects **2D only** (the 3D batch draw is ``drawInstanced(_:transforms:)``.
    ///   ADR-0005).
    ///
    /// - Parameter instances: The circle instances to draw.
    public func circles(_ instances: [CircleInstance]) {
        context.circles(instances)
    }

    /// Draws circle instances held in a GPU buffer in a single batch.
    ///
    /// - Note: Affects **2D only** (the 3D batch draw is ``drawInstanced(_:transforms:)``.
    ///   ADR-0005).
    ///
    /// - Important: The buffer is drawn byte for byte, so a compute kernel that fills it has to
    ///   declare the struct in ``CircleInstance``'s memory order — `position` at 0, `diameter`
    ///   at 8, padding at 12, `color` at 16, stride 32 — not in the alphabetical order the
    ///   properties are documented in. The wrong order compiles without a warning and draws
    ///   nothing at all; the MSL definition to paste is in the documentation for
    ///   ``CircleInstance``.
    ///
    /// - Parameters:
    ///   - instances: The GPU buffer holding the ``CircleInstance`` values.
    ///   - count: The number of instances to draw. The whole buffer when omitted.
    public func circles(_ instances: GPUBuffer<CircleInstance>, count: Int? = nil) {
        context.circles(instances, count: count)
    }

    /// Draws a square.
    ///
    /// - Note: Affects **2D only** (the 3D cube is ``box(_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - size: The length of a side.
    ///
    /// ### Result
    ///
    /// How x and y are interpreted follows ``rectMode(_:)`` (the top-left corner by default).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![square(_:_:_:) の実行結果](https://i.gyazo.com/e39d66e012449b14a5ae4cdb4d346578.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       square(160, 100, 160)
    ///       ```
    ///    }
    /// }
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        context.square(x, y, size)
    }

    /// Draws a quadrilateral defined by four vertices.
    ///
    /// - Note: Affects **2D only** (to build an arbitrary quadrilateral in 3D, use
    ///   ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x1: The x coordinate of the first vertex.
    ///   - y1: The y coordinate of the first vertex.
    ///   - x2: The x coordinate of the second vertex.
    ///   - y2: The y coordinate of the second vertex.
    ///   - x3: The x coordinate of the third vertex.
    ///   - y3: The y coordinate of the third vertex.
    ///   - x4: The x coordinate of the fourth vertex.
    ///   - y4: The y coordinate of the fourth vertex.
    ///
    /// ### Result
    ///
    /// The vertices are connected in order, so the order they are listed in decides whether the
    /// shape comes out convex or concave.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![quad(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/dc84d016cc71fa60501d786d01d82692.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(150, 220, 120)
    ///       noStroke()
    ///       quad(
    ///           120, 70, 400, 120,
    ///           360, 300, 90, 250
    ///       )
    ///       ```
    ///    }
    /// }
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Draws a line between two points.
    ///
    /// - Note: Affects **2D only** (for a 3D line, pass ``ShapeMode/lines`` to
    ///   ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x1: The x coordinate of the start point.
    ///   - y1: The y coordinate of the start point.
    ///   - x2: The x coordinate of the end point.
    ///   - y2: The y coordinate of the end point.
    ///
    /// ### Result
    ///
    /// The thickness changes with ``strokeWeight(_:)`` and the shape of the ends with
    /// ``strokeCap(_:)``.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![line(_:_:_:_:) の実行結果](https://i.gyazo.com/20e8d9c58aedcf6c2eead71cb4fca8e7.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(6)
    ///       line(80, 280, 400, 80)
    ///       ```
    ///    }
    /// }
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        context.line(x1, y1, x2, y2)
    }

    /// Draws a triangle defined by three vertices.
    ///
    /// - Note: Affects **2D only** (a 3D triangle is built with ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x1: The x coordinate of the first vertex.
    ///   - y1: The y coordinate of the first vertex.
    ///   - x2: The x coordinate of the second vertex.
    ///   - y2: The y coordinate of the second vertex.
    ///   - x3: The x coordinate of the third vertex.
    ///   - y3: The y coordinate of the third vertex.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![triangle(_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/9f04166a0245ba36661e30099eae1e45.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 120, 90)
    ///       noStroke()
    ///       triangle(240, 60, 400, 300, 80, 300)
    ///       ```
    ///    }
    /// }
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        context.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// Draws a polygon from an array of coordinate tuples.
    ///
    /// - Note: Affects **2D only** (3D is built with ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameter points: The polygon vertices, as `(x, y)` tuples.
    public func polygon(_ points: [(Float, Float)]) {
        context.polygon(points)
    }

    /// Draws a polygon from an array of ``Vec2`` values.
    ///
    /// - Note: Affects **2D only** (3D is built with ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameter points: The polygon vertices.
    public func polygon(_ points: [Vec2]) {
        context.polygon(points)
    }

    /// Draws an arc (`stopAngle` must be greater than `startAngle`; a sweep past 2π is clamped
    /// to one turn).
    ///
    /// - Note: Affects **2D only** (there is no corresponding 3D primitive; ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the center of the arc.
    ///   - y: The y coordinate of the center of the arc.
    ///   - w: The width of the ellipse the arc is inscribed in.
    ///   - h: The height of the ellipse the arc is inscribed in.
    ///   - startAngle: The start angle, in radians.
    ///   - stopAngle: The stop angle, in radians. Nothing is drawn when it is at or below
    ///     `startAngle`.
    ///   - mode: The arc drawing mode. When omitted it matches Processing's default: a pie-shaped
    ///     fill plus a stroke along the arc only (``ArcMode/default``). An explicit
    ///     ``ArcMode/open`` differs in that its fill is a segment closed off by the chord.
    ///
    /// As in Processing, the angles are normalized before drawing. `stopAngle <= startAngle` draws
    /// nothing (it never sweeps backwards), and a range past 2π is clamped to 0...2π so nothing is
    /// drawn twice.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![arc(_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/66c138c57b6838b7a60c9d58b222b5eb.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 120, 140)
    ///       stroke(255)
    ///       strokeWeight(3)
    ///       let sweep = Float.pi * 1.2
    ///       arc(240, 180, 220, 220, 0, sweep)
    ///       ```
    ///    }
    /// }
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .default
    ) {
        context.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// Draws a cubic Bézier curve.
    ///
    /// - Note: Affects **2D only** (there is no 3D Bézier curve; ADR-0005).
    ///
    /// - Parameters:
    ///   - x1: The x coordinate of the start point.
    ///   - y1: The y coordinate of the start point.
    ///   - cx1: The x coordinate of the first control point.
    ///   - cy1: The y coordinate of the first control point.
    ///   - cx2: The x coordinate of the second control point.
    ///   - cy2: The y coordinate of the second control point.
    ///   - x2: The x coordinate of the end point.
    ///   - y2: The y coordinate of the end point.
    ///
    /// ### Result
    ///
    /// The control points (gray) do not sit on the curve; they only decide which way each end is
    /// pulled.
    ///
    /// <!-- reference-shot -->
    ///
    /// ```swift
    /// background(24)
    /// noFill()
    /// stroke(120, 230, 180)
    /// strokeWeight(4)
    /// bezier(60, 280, 140, 40, 340, 320, 420, 80)
    ///
    /// // 端点と、それを引っぱっている制御点を結んで見せる
    /// stroke(130)
    /// strokeWeight(1)
    /// line(60, 280, 140, 40)
    /// line(420, 80, 340, 320)
    /// strokeWeight(12)
    /// point(140, 40)
    /// point(340, 320)
    /// ```
    ///
    /// ![bezier(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/0b721460f802e496b860f974378c500c.png)
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        context.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// Draws a single point.
    ///
    /// - Note: Affects **2D only** (for a 3D point, pass ``ShapeMode/points`` to
    ///   ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///
    /// ### Result
    ///
    /// The size of a point comes from ``strokeWeight(_:)`` and its color from `stroke()`.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![point(_:_:) の実行結果](https://i.gyazo.com/3878c966403fc6876992923c40bb27bd.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(12)
    ///       for i in 0..<9 {
    ///           let x = 80 + Float(i) * 40
    ///           point(x, 180 - Float(i % 3) * 50)
    ///       }
    ///       ```
    ///    }
    /// }
    public func point(_ x: Float, _ y: Float) {
        context.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    /// Starts recording the vertices of a custom shape.
    ///
    /// - Note: Affects **2D only** (the 3D custom shape is ``beginShape3D(_:)``. ADR-0005).
    ///
    /// - Parameter mode: The shape mode (polygon, triangles, or lines, for example).
    ///
    /// ### Result
    ///
    /// Lay the vertices out with ``vertex(_:_:)``, then close and draw with ``endShape(_:)``.
    /// Listing them in star order (5 points, skipping two each time) makes the edges cross one
    /// another, but because filling follows the nonzero winding rule the result is a pentagram.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![beginShape(_:) の実行結果](https://i.gyazo.com/d965e3aa16851653671ff363b8edd959.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       beginShape()
    ///       vertex(240, 60)
    ///       vertex(330, 300)
    ///       vertex(90, 150)
    ///       vertex(390, 150)
    ///       vertex(150, 300)
    ///       endShape(.close)
    ///       ```
    ///    }
    /// }
    public func beginShape(_ mode: ShapeMode = .polygon) {
        context.beginShape(mode)
    }

    /// Adds a 2D vertex to the current shape.
    ///
    /// - Note: What it affects is decided by **the shape being recorded**. If recording started
    ///   with ``beginShape(_:)`` it goes to 2D, and if it started with ``beginShape3D(_:)`` it
    ///   flows through as a 3D vertex with z = 0 (compatible with Processing. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///
    /// ### Result
    ///
    /// Leaving ``endShape(_:)`` at ``CloseMode/open`` instead of closing it yields a polyline.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![vertex(_:_:) の実行結果](https://i.gyazo.com/050fa166d5c66c43957cb13a43d68b44.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(6)
    ///       beginShape()
    ///       vertex(70, 260)
    ///       vertex(150, 110)
    ///       vertex(240, 230)
    ///       vertex(330, 90)
    ///       vertex(410, 240)
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func vertex(_ x: Float, _ y: Float) {
        context.vertex(x, y)
    }

    /// Adds a 2D vertex with a vertex color to the current shape.
    ///
    /// - Note: What it affects is decided by **the shape being recorded**. If recording started
    ///   with ``beginShape(_:)`` it goes to 2D, and if it started with ``beginShape3D(_:)`` it
    ///   flows through as a 3D vertex with z = 0 (ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        context.vertex(x, y, color)
    }

    /// Adds a 2D vertex with texture coordinates to the current shape.
    ///
    /// - Note: What it affects is decided by **the shape being recorded**. If recording started
    ///   with ``beginShape(_:)`` it goes to 2D. While ``beginShape3D(_:)`` is recording, the UVs
    ///   are dropped and it becomes a 3D vertex with z = 0, warning once (ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - u: The horizontal texture coordinate.
    ///   - v: The vertical texture coordinate.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, u, v)
    }

    /// Adds a cubic Bézier vertex to the current shape.
    ///
    /// - Note: Affects **2D only** (a 3D shape has no Bézier vertices; ADR-0005).
    ///
    /// - Parameters:
    ///   - cx1: The x coordinate of the first control point.
    ///   - cy1: The y coordinate of the first control point.
    ///   - cx2: The x coordinate of the second control point.
    ///   - cy2: The y coordinate of the second control point.
    ///   - x: The x coordinate of the anchor point.
    ///   - y: The y coordinate of the anchor point.
    ///
    /// ### Result
    ///
    /// The preceding vertex becomes the start point, so place one ``vertex(_:_:)`` before calling
    /// it.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![bezierVertex(_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/96c2d0ca7b953a80922e8477d611243e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(255, 190, 60)
    ///       strokeWeight(4)
    ///       beginShape()
    ///       vertex(80, 260)
    ///       bezierVertex(
    ///           120, 60, 360, 60, 400, 260
    ///       )
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        context.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Adds a Catmull-Rom spline vertex to the current shape.
    ///
    /// - Note: Affects **2D only** (a 3D shape has no spline vertices; ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///
    /// ### Result
    ///
    /// The first and last points are control points that decide the direction of the curve, so the
    /// same coordinate is placed twice.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![curveVertex(_:_:) の実行結果](https://i.gyazo.com/46e0b074f4363c0b55f426584e360940.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(4)
    ///       beginShape()
    ///       curveVertex(60, 240)
    ///       curveVertex(60, 240)
    ///       curveVertex(180, 120)
    ///       curveVertex(300, 280)
    ///       curveVertex(420, 140)
    ///       curveVertex(420, 140)
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func curveVertex(_ x: Float, _ y: Float) {
        context.curveVertex(x, y)
    }

    /// Sets the number of segments used for curve interpolation.
    ///
    /// - Note: Affects **2D only** (it is for ``curveVertex(_:_:)`` /
    ///   ``curve(_:_:_:_:_:_:_:_:)`` and has no effect on 3D. ADR-0005).
    ///
    /// - Parameter n: The curve detail.
    public func curveDetail(_ n: Int) {
        context.curveDetail(n)
    }

    /// Sets how tightly Catmull-Rom spline curves are drawn.
    ///
    /// - Note: Affects **2D only** (it is for ``curveVertex(_:_:)`` /
    ///   ``curve(_:_:_:_:_:_:_:_:)`` and has no effect on 3D. ADR-0005).
    ///
    /// - Note: `-5.0` to `5.0` is the useful range. Values outside it are accepted as well (there
    ///   is no clamping, as in Processing), but the curve strays far from the control points.
    ///
    /// - Parameter t: The tightness value (0 = the default, 1 = straight lines).
    public func curveTightness(_ t: Float) {
        context.curveTightness(t)
    }

    /// Starts defining a contour (a hole) inside the current shape. 2D shapes only.
    ///
    /// A 3D shape built with `beginShape3D()` cannot be given a hole (calling this does nothing,
    /// and it warns once). When a face with a hole is needed in 3D, triangulate the ring between
    /// the inner and outer boundaries yourself.
    ///
    /// - Note: Affects **2D only** (while ``beginShape3D(_:)`` is recording it does nothing and
    ///   warns once. #736 / ADR-0005).
    ///
    /// ### Result
    ///
    /// Wind the hole in the opposite direction from the outer boundary. Close it with
    /// ``endContour()`` before calling ``endShape(_:)``.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![beginContour() の実行結果](https://i.gyazo.com/0589e9f453959e2667e5a33fb94cf8a4.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       beginShape()
    ///       vertex(100, 70)
    ///       vertex(380, 70)
    ///       vertex(380, 290)
    ///       vertex(100, 290)
    ///       beginContour()
    ///       vertex(190, 130)
    ///       vertex(190, 230)
    ///       vertex(290, 230)
    ///       vertex(290, 130)
    ///       endContour()
    ///       endShape(.close)
    ///       ```
    ///    }
    /// }
    public func beginContour() {
        context.beginContour()
    }

    /// Ends the current contour definition. 2D shapes only.
    ///
    /// - Note: Affects **2D only** (while ``beginShape3D(_:)`` is recording it does nothing and
    ///   warns once. #736 / ADR-0005).
    public func endContour() {
        context.endContour()
    }

    /// Draws a Catmull-Rom spline curve through four points.
    ///
    /// - Note: Affects **2D only** (there is no 3D spline curve; ADR-0005).
    ///
    /// - Parameters:
    ///   - x1: The x coordinate of the first control point.
    ///   - y1: The y coordinate of the first control point.
    ///   - x2: The x coordinate of the start point.
    ///   - y2: The y coordinate of the start point.
    ///   - x3: The x coordinate of the end point.
    ///   - y3: The y coordinate of the end point.
    ///   - x4: The x coordinate of the second control point.
    ///   - y4: The y coordinate of the second control point.
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Ends recording the current shape and draws it.
    ///
    /// - Note: What it affects is decided by **the shape being recorded**. A shape started with
    ///   ``beginShape3D(_:)`` can be closed with this one as well (with the same result as
    ///   ``endShape3D(_:)``. ADR-0005).
    ///
    /// - Note: Filling a self-intersecting vertex sequence, such as a pentagram, follows the
    ///   **nonzero winding** rule (the same as Processing and p5.js). Regions whose winding number
    ///   is not 0 are filled, so a pentagram comes out as a solid star with the central pentagon
    ///   filled in as well.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape(_ close: CloseMode = .open) {
        context.endShape(close)
    }

    // MARK: - Clipping

    /// Clips subsequent drawing to the given rectangle.
    ///
    /// - Note: Affects **2D only** (3D drawing is not clipped; ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the clip region.
    ///   - y: The y coordinate of the clip region.
    ///   - w: The width of the clip region.
    ///   - h: The height of the clip region.
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.beginClip(x, y, w, h)
    }

    /// Ends the current clip region and restores the previous state.
    ///
    /// - Note: Affects **2D only** (3D drawing is not clipped; ADR-0005).
    public func endClip() {
        context.endClip()
    }
}
