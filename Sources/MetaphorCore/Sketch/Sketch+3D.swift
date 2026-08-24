// MARK: - 3D Drawing (Camera, Lighting, Material, Shapes, Transform)
//
// 2D と 3D の重ね順は ``Sketch/enableShadows(resolution:)`` の Note が正典。
// 要点だけ: 既定（影オフ）の即時経路では重ね順が呼び出し順ではなくエンコード順で
// 決まり、2D は 3D の手前に出る（#832 / ADR-0003 の 2026-08-16 追記）。

extension Sketch {

    // MARK: 3D Custom Shapes

    /// Begins recording the vertices of a custom 3D shape.
    ///
    /// The current color is applied to each vertex exactly once. Changing the color
    /// between `beginShape3D` and `endShape3D` gives only the vertices added from that
    /// point on the new color (per-vertex coloring). Face modes (`.polygon`,
    /// `.triangles`, and so on) use `fill`, while **`.lines` and `.points` use
    /// `stroke`** (the same as LINES / POINTS in Processing; under `noStroke()` it falls
    /// back to `fill`).
    ///
    /// - Note: Affects **3D only** (the 2D custom shape is ``beginShape(_:)``. ADR-0005).
    ///
    /// - Parameter mode: The shape mode (for example polygon, triangles, or lines).
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        context.beginShape3D(mode)
    }

    /// Adds a 3D vertex to the current shape.
    ///
    /// - Note: The destination is decided by **the shape being recorded**. If it was
    ///   started with ``beginShape3D(_:)`` the vertex goes to 3D; if it was started with
    ///   the 2D ``beginShape(_:)`` the z is dropped and it flows to 2D (Processing
    ///   compatible. Because a solid you meant to build comes out flat, a warning is
    ///   emitted the first time only. ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        context.vertex(x, y, z)
    }

    /// Adds a 3D vertex with a vertex color to the current shape.
    ///
    /// The given color is emitted as is, independent of the current `fill`. Vertex colors
    /// are not used on a shape with a `texture()` applied (the texture color shows
    /// instead).
    ///
    /// - Note: The destination is decided by **the shape being recorded**. If it was
    ///   started with ``beginShape3D(_:)`` the vertex goes to 3D; if it was started with
    ///   the 2D ``beginShape(_:)`` the z is dropped and it flows to 2D (ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        context.vertex(x, y, z, color)
    }

    /// Adds a 3D vertex with texture coordinates to the current shape.
    ///
    /// This has an effect only on a shape whose image was set with `texture(_:)`. Without
    /// a texture the UVs are ignored and the shape is painted with the normal fill.
    ///
    /// - Note: The destination is decided by **the shape being recorded**. If it was
    ///   started with ``beginShape3D(_:)`` the vertex goes to 3D; if it was started with
    ///   the 2D ``beginShape(_:)`` the z is dropped and it flows to 2D (ADR-0005).
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    ///   - u: The horizontal texture coordinate (normalized to 0.0 through 1.0).
    ///   - v: The vertical texture coordinate (normalized to 0.0 through 1.0).
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, z, u, v)
    }

    /// Sets the normal vector for subsequent 3D vertices.
    ///
    /// It stays in effect until `endShape3D()`. The retained ``MShape/normal(_:_:_:)`` has
    /// the same scope (#876). Call it per vertex to give each vertex a different normal.
    ///
    /// - Note: Affects **3D only** (2D shapes have no normals. ADR-0005).
    ///
    /// - Parameters:
    ///   - nx: The x component of the normal.
    ///   - ny: The y component of the normal.
    ///   - nz: The z component of the normal.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        context.normal(nx, ny, nz)
    }

    /// Ends recording of the current 3D shape and draws it.
    ///
    /// - Note: The destination is decided by **the shape being recorded**. If it was
    ///   started with the 2D ``beginShape(_:)``, it closes in 2D just like
    ///   ``endShape(_:)`` (ADR-0005).
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape3D(_ close: CloseMode = .open) {
        context.endShape3D(close)
    }

    // MARK: 3D Camera

    /// Sets the 3D camera from eye, center, and up vectors.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by the camera. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The camera returns to the default pixel-space view at the
    ///   start of every frame, so call this from `draw()` — a call in `setup()` is discarded
    ///   before the first frame is drawn. `llms-sketch.txt` lists every state that does and does
    ///   not survive a frame boundary.
    ///
    /// - Parameters:
    ///   - eye: The position of the camera.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector.
    ///
    /// ### Result
    ///
    /// The default camera is a pixel space whose origin is the top-left corner of the
    /// canvas, but calling `camera()` moves to a coordinate system that looks at `center`
    /// (in the example below a box placed at the origin lands in the middle of the screen
    /// as is, so ``translate(_:_:_:)`` is not needed).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![camera(eye:center:up:) の実行結果](https://i.gyazo.com/300bb909ffb972fba5ac4e2ff4589779.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 200, 255)
    ///       camera(
    ///           eye: SIMD3(190, -150, 330),
    ///           center: SIMD3(0, 0, 0)
    ///       )
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        context.camera(eye: eye, center: center, up: up)
    }

    /// Sets a perspective projection.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by the projection. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The projection returns to the default perspective (a 60°
    ///   field of view) at the start of every frame, so call this from `draw()` — a call in
    ///   `setup()` is discarded before the first frame is drawn. `llms-sketch.txt` lists every
    ///   state that does and does not survive a frame boundary.
    ///
    /// - Parameters:
    ///   - fov: The field of view in radians.
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    ///
    /// ### Result
    ///
    /// Lining up three boxes of the same size into the distance makes the farther ones
    /// look smaller. Narrowing `fov` flattens the perspective like a telephoto lens. The
    /// same arrangement shot with a parallel projection is in
    /// ``ortho(left:right:bottom:top:near:far:)``, so the two can be compared side by side.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![perspective(fov:near:far:) の実行結果](https://i.gyazo.com/8d0b1db9bce559a2b3c9789b5f8112da.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       perspective(fov: PI / 3)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.25)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               Float(i) * 120 - 120,
    ///               0,
    ///               Float(i) * -170
    ///           )
    ///           box(90)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        context.perspective(fov: fov, near: near, far: far)
    }

    /// Sets an orthographic projection.
    ///
    /// Omitted planes are filled in with **the range that lines up with the default
    /// camera**. An orthographic projection acts on **view space**, while the default
    /// camera looks at the center of the canvas, so the range used when a plane is
    /// omitted also straddles the origin (that is, the center of the screen). This way a
    /// bare `ortho()` call is enough to switch to a parallel projection while keeping the
    /// same pixel coordinates as 2D (#777).
    ///
    /// - Important: Following the convention of projection matrices, `bottom` is the side
    ///   where y in view space is **smaller**. Because y in metaphor points down the
    ///   screen just as it does in 2D, `bottom` corresponds to the **top** edge of the
    ///   screen and `top` to the **bottom** edge. Passing the two the other way around
    ///   flips the image vertically.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by the projection. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The projection returns to the default perspective at the
    ///   start of every frame, so call this from `draw()` — a call in `setup()` is discarded
    ///   before the first frame is drawn. `llms-sketch.txt` lists every state that does and does
    ///   not survive a frame boundary.
    ///
    /// - Parameters:
    ///   - left: The left clipping plane (`-width / 2` when `nil`).
    ///   - right: The right clipping plane (`width / 2` when `nil`).
    ///   - bottom: The bottom clipping plane (`-height / 2` when `nil`).
    ///   - top: The top clipping plane (`height / 2` when `nil`).
    ///   - near: The distance to the near clipping plane (-10 times the default camera
    ///     distance when `nil`).
    ///   - far: The distance to the far clipping plane (10 times the default camera
    ///     distance when `nil`).
    ///
    /// ### Result
    ///
    /// The **same arrangement** as ``perspective(fov:near:far:)``, shot with a parallel
    /// projection. Shifting the depth does not change the size, so the three boxes line up
    /// at identical dimensions.
    ///
    /// The example below states the range explicitly, but with the default camera a bare
    /// `ortho()` also puts them at the same size in the center (state the range only when
    /// you want to narrow down what is captured).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ortho(left:right:bottom:top:near:far:) の実行結果](https://i.gyazo.com/2d792009de4259626f4828d453a0807e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 220, 120)
    ///       ortho(
    ///           left: -width / 2,
    ///           right: width / 2,
    ///           bottom: -height / 2,
    ///           top: height / 2
    ///       )
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.25)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               Float(i) * 120 - 120,
    ///               0,
    ///               Float(i) * -170
    ///           )
    ///           box(90)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float? = nil, far: Float? = nil
    ) {
        context.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    /// Enables the default lighting (a directional light and an ambient light).
    ///
    /// The ambient is set to 30% of the `colorMode` range (equivalent to
    /// `ambientLight(76.5)` with the default range of 0 to 255). The same value is
    /// installed when the first light is added, even if you add lights one by one, unless
    /// `ambientLight()` has already been called.
    ///
    /// The light of the default rig shines from **the upper right, in front**
    /// (`(-0.5, 1, -0.8)` in terms of ``directionalLight(_:_:_:color:intensity:)``). The
    /// shadows of ``enableShadows(resolution:)`` fall along the same direction.
    ///
    /// The light of the default rig has an `intensity` of 0.7, a brightness tuned for
    /// Blinn-Phong (the default). Under PBR (``pbr(_:)``) direct light is attenuated by
    /// `albedo / π`, so the same rig comes out **30 to 40% darker** (measured on a 96×96
    /// sphere: Blinn-Phong 80.4 / PBR 51.2). When you need a sense of volume under PBR,
    /// place your own ``directionalLight(_:_:_:color:intensity:)`` with an `intensity`.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by lighting. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The set of lights is emptied at the start of every frame,
    ///   so call this from `draw()` — a call in `setup()` is discarded before the first frame is
    ///   drawn. `llms-sketch.txt` lists every state that does and does not survive a frame
    ///   boundary.
    ///
    /// ### Result
    ///
    /// With no lights at all the shading computation itself is skipped and shapes are
    /// filled flat with the ``fill(_:_:_:_:)`` color (left). Lights are evaluated at every
    /// draw, so adding one partway through the same frame lights only the shapes that
    /// follow (right).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![lights() の実行結果](https://i.gyazo.com/016885f45d91c0122a6c2c8718c53d7d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       lights()
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func lights() {
        context.lights()
    }

    /// Disables all lights.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The set of lights is emptied at the start of every frame,
    ///   so call this from `draw()` — a call in `setup()` is discarded before the first frame is
    ///   drawn. `llms-sketch.txt` lists every state that does and does not survive a frame
    ///   boundary.
    public func noLights() {
        context.noLights()
    }

    /// Adds a directional light.
    ///
    /// What you specify is the direction the light **travels**, and the y axis points down
    /// the screen just as in Processing. That means `directionalLight(0, 1, 0)` is a light
    /// shining straight down from above, and `(0, -1, 0)` is a light shining straight up
    /// from below (the direction of the shadows under `enableShadows()` follows this too).
    ///
    /// `intensity` is a strength multiplier applied to the color. Direct light under PBR
    /// (``pbr(_:)``) is attenuated by `albedo / π`, and the only ambient available is the
    /// ``ambientLight(_:)`` fallback, so **a single light needs roughly 2 to 4 to give a
    /// sense of volume**. Under Blinn-Phong (the default), 1.0 keeps the usual brightness.
    ///
    /// ```swift
    /// pbr(true)
    /// directionalLight(-0.4, 1, -0.6, intensity: 3)   // Lift the key light
    /// ```
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by lighting. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The set of lights is emptied at the start of every frame,
    ///   so call this from `draw()` — a call in `setup()` is discarded before the first frame is
    ///   drawn. `llms-sketch.txt` lists every state that does and does not survive a frame
    ///   boundary.
    ///
    /// - Parameters:
    ///   - x: The x component of the light direction.
    ///   - y: The y component of the light direction.
    ///   - z: The z component of the light direction.
    ///   - color: The color of the light (white by default).
    ///   - intensity: The strength multiplier of the light (1.0 by default).
    ///
    /// ### Result
    ///
    /// Three spheres with only the x component of the light changed to -1 / 0 / +1. A
    /// directional light has no position, so a sphere is lit from the same direction
    /// wherever it is placed.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![directionalLight(_:_:_:color:intensity:) の実行結果](https://i.gyazo.com/91028fa6f248fab585f01a0e5fcc3d8f.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///
    ///       for i in 0..<3 {
    ///           noLights()
    ///           ambientLight(40)
    ///           directionalLight(
    ///               Float(i - 1), 1, -0.6
    ///           )
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func directionalLight(
        _ x: Float, _ y: Float, _ z: Float, color: Color = .white, intensity: Float = 1.0
    ) {
        context.directionalLight(x, y, z, color: color, intensity: intensity)
    }

    /// Adds a point light at the given position.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The set of lights is emptied at the start of every frame,
    ///   so call this from `draw()` — a call in `setup()` is discarded before the first frame is
    ///   drawn. `llms-sketch.txt` lists every state that does and does not survive a frame
    ///   boundary.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the light position.
    ///   - y: The y coordinate of the light position.
    ///   - z: The z coordinate of the light position.
    ///   - color: The color of the light.
    ///   - falloff: The attenuation coefficient.
    ///   - intensity: The strength multiplier of the light (1.0 by default). A single
    ///     light under PBR needs a value greater than 1.0 (see
    ///     ``directionalLight(_:_:_:color:intensity:)``).
    ///
    /// ### Result
    ///
    /// Unlike a directional light this one has a **position**, so the closer a sphere is
    /// to the light the brighter it gets (a single light is placed in front of the center
    /// of the canvas). `falloff` is the distance attenuation coefficient, and it goes
    /// **into the linear term as is and into the quadratic term at one tenth of that**. In
    /// pixel space distances are on the order of hundreds, so with the default of 0.1
    /// almost no light reaches the geometry.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![pointLight(_:_:_:color:falloff:intensity:) の実行結果](https://i.gyazo.com/0bc0a58c490fe49b0292db8bc80817dd.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///       ambientLight(30)
    ///       pointLight(
    ///           240, 180, 130,
    ///           falloff: 0.004,
    ///           intensity: 3
    ///       )
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           sphere(70)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1,
        intensity: Float = 1.0
    ) {
        context.pointLight(x, y, z, color: color, falloff: falloff, intensity: intensity)
    }

    /// Adds a spot light at the given position and direction.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The set of lights is emptied at the start of every frame,
    ///   so call this from `draw()` — a call in `setup()` is discarded before the first frame is
    ///   drawn. `llms-sketch.txt` lists every state that does and does not survive a frame
    ///   boundary.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the light position.
    ///   - y: The y coordinate of the light position.
    ///   - z: The z coordinate of the light position.
    ///   - dirX: The x component of the light direction.
    ///   - dirY: The y component of the light direction.
    ///   - dirZ: The z component of the light direction.
    ///   - angle: The cone angle in radians.
    ///   - falloff: The attenuation coefficient.
    ///   - color: The color of the light.
    ///   - intensity: The strength multiplier of the light (1.0 by default). A single
    ///     light under PBR needs a value greater than 1.0 (see
    ///     ``directionalLight(_:_:_:color:intensity:)``).
    ///
    /// ### Result
    ///
    /// Lighting a head-on ``plane(_:_:)`` from the front cuts the cross section of the
    /// cone determined by `angle` out as a circle. `falloff` is the same distance
    /// attenuation as in ``pointLight(_:_:_:color:falloff:intensity:)``, and in pixel
    /// space even the default of 0.01 lets almost no light reach the geometry.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![spotLight(_:_:_:_:_:_:angle:falloff:color:intensity:) の実行結果](https://i.gyazo.com/1fe96b4c5fb912f33eb124a9faca0af2.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///       ambientLight(20)
    ///       spotLight(
    ///           240, 180, 300,
    ///           0, 0, -1,
    ///           angle: PI / 7,
    ///           falloff: 0.0005,
    ///           intensity: 4
    ///       )
    ///       translate(width / 2, height / 2, 0)
    ///       plane(460, 340)
    ///       ```
    ///    }
    /// }
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white,
        intensity: Float = 1.0
    ) {
        context.spotLight(
            x, y, z, dirX, dirY, dirZ,
            angle: angle, falloff: falloff, color: color, intensity: intensity
        )
    }

    /// Sets the intensity of the ambient light from a grayscale value.
    ///
    /// Like `fill` and friends, the value is **relative to the `colorMode` range** (0 to
    /// 255 by default). A value meant as 0 to 1, such as `ambientLight(0.35)`, comes out
    /// almost pitch black (with the default range, pass the equivalent of
    /// `ambientLight(90)` instead).
    ///
    /// The default ambient that `lights()`, or the first light you add, installs
    /// automatically is **30% of the range** (`ambientLight(76.5)` with the default
    /// range). To state the same brightness as the default explicitly, write
    /// `ambientLight(76.5)`, not `ambientLight(0.3)`.
    ///
    /// The ambient is not attenuated inside the shadows of `enableShadows()` (only the
    /// diffuse and specular of direct light are shadowed). The detail inside a shadow is
    /// determined by this value.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by lighting. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The ambient light returns to its default at the start of
    ///   every frame, so call this from `draw()` — a call in `setup()` is discarded before the
    ///   first frame is drawn. `llms-sketch.txt` lists every state that does and does not survive
    ///   a frame boundary.
    ///
    /// - Parameter strength: The ambient light intensity (relative to the `colorMode` range).
    ///
    /// ### Result
    ///
    /// The ambient has no direction, so on its own it produces no shading and merely lifts
    /// the color uniformly (left). Combine it with a light that has a direction to give a
    /// sense of volume (right).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ambientLight(_:) の実行結果](https://i.gyazo.com/2e655165dc3a1d94aa012eaae135a24e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///       ambientLight(90)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       directionalLight(-0.5, 1, -0.8)
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func ambientLight(_ strength: Float) {
        context.ambientLight(strength)
    }

    /// Sets the color of the ambient light from RGB values.
    ///
    /// Like `fill` and friends, the values are **relative to the `colorMode` range** (0 to
    /// 255 by default).
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The ambient light returns to its default at the start of
    ///   every frame, so call this from `draw()` — a call in `setup()` is discarded before the
    ///   first frame is drawn. `llms-sketch.txt` lists every state that does and does not survive
    ///   a frame boundary.
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        context.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// Enables shadow mapping.
    ///
    /// - Note: Affects **3D only** (only 3D shapes cast shadows. ADR-0005).
    ///
    /// - Note: **Survives across frames.** Unlike the lights themselves, the shadow map is
    ///   **not** reset at the start of a frame, so setting it once in `setup()` is enough.
    ///   `llms-sketch.txt` lists every state that does and does not survive a frame boundary.
    ///
    /// - Note: **Layering of 2D and 3D** (#832 / the Amendment section of ADR-0003). On
    ///   the default immediate path (shadows off), the layering is determined by **encode
    ///   order, not call order**. 2D is collected into a batch and flushed at the end of
    ///   the frame, so **2D comes in front of 3D by default** (2D drawn before `box()`
    ///   still ends up in front). If the 2D batch is flushed partway through, however, it
    ///   falls behind any 3D encoded after that — the triggers are a change of
    ///   `blendMode()`, alternating with `image()` or `text()`, alternating with instanced
    ///   drawing such as `circles()`, `beginClip()` / `endClip()`, `loadPixels()`, and the
    ///   vertex buffer limit. **To layer in call order**, either enable this
    ///   `enableShadows()` or take the recording path with the environment variable
    ///   `METAPHOR_COMMAND_RECORD=1` (in both cases `Canvas3D` finalizes the 2D right
    ///   before it records the 3D, so the call order is restored as is).
    ///
    /// - Parameter resolution: The resolution of the shadow map, in pixels.
    public func enableShadows(resolution: Int = 2048) {
        context.enableShadows(resolution: resolution)
    }

    /// Disables shadow mapping.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Survives across frames.** Unlike the lights themselves, the shadow map is
    ///   **not** reset at the start of a frame, so setting it once in `setup()` is enough.
    ///   `llms-sketch.txt` lists every state that does and does not survive a frame boundary.
    public func disableShadows() {
        context.disableShadows()
    }

    /// Sets the shadow depth bias used to reduce shadow acne.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Survives across frames.** The shadow bias is **not** reset at the start of a
    ///   frame, so setting it once in `setup()` is enough. `llms-sketch.txt` lists every state
    ///   that does and does not survive a frame boundary.
    ///
    /// - Parameter value: The bias value.
    public func shadowBias(_ value: Float) {
        context.shadowBias(value)
    }

    // MARK: 3D Material

    /// Sets the color of specular highlights.
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by materials. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        context.specular(color)
    }

    /// Sets the color of specular highlights from channel values.
    ///
    /// Like `fill` and friends, the values are **relative to the `colorMode` range** (0 to
    /// 255 by default).
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by materials. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///
    /// ### Result
    ///
    /// Three spheres with the same dark ``fill(_:_:_:_:)``, given a red, a green, and a
    /// blue highlight. Unlike the diffuse color, only the color of the highlight changes.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![specular(_:_:_:) の実行結果](https://i.gyazo.com/57ad27360e44b22561d478fcaeb42c4f.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(75, 82, 105)
    ///       shininess(28)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           specular(
    ///               i == 0 ? 255 : 70,
    ///               i == 1 ? 255 : 70,
    ///               i == 2 ? 255 : 70
    ///           )
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func specular(_ v1: Float, _ v2: Float, _ v3: Float) {
        context.specular(v1, v2, v3)
    }

    /// Sets the color of specular highlights from a grayscale value.
    ///
    /// Like `fill` and friends, the value is **relative to the `colorMode` range** (0 to
    /// 255 by default).
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func specular(_ gray: Float) {
        context.specular(gray)
    }

    /// Sets the specular shininess exponent.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter value: The shininess (the larger the value, the smaller the highlight).
    ///
    /// ### Result
    ///
    /// 4 / 44 / 84 from the left. The larger the value, the smaller and sharper the highlight.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shininess(_:) の実行結果](https://i.gyazo.com/bea51a3d3dd331ebe38a1c640df52995.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(70, 100, 170)
    ///       specular(255)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           shininess(4 + Float(i) * 40)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func shininess(_ value: Float) {
        context.shininess(value)
    }

    /// Sets the emissive (self-illumination) color.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        context.emissive(color)
    }

    /// Sets the emissive color from channel values.
    ///
    /// Like `fill` and friends, the values are **relative to the `colorMode` range** (0 to
    /// 255 by default).
    ///
    /// - Note: Affects **3D only** (2D drawing is not affected by materials. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    public func emissive(_ v1: Float, _ v2: Float, _ v3: Float) {
        context.emissive(v1, v2, v3)
    }

    /// Sets the emissive color from a grayscale value.
    ///
    /// Like `fill` and friends, the value is **relative to the `colorMode` range** (0 to
    /// 255 by default).
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func emissive(_ gray: Float) {
        context.emissive(gray)
    }

    /// Sets the metallic coefficient of the material.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter value: The metallic value (0 = dielectric, 1 = metal).
    ///
    /// ### Result
    ///
    /// 0 / 0.5 / 1.0 from the left. The closer to metal, the more the diffuse color is
    /// lost, until the form is visible only through the reflection of the lights. PBR is
    /// dark under the default rig, so the example places its own light with a raised
    /// `intensity`.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![metallic(_:) の実行結果](https://i.gyazo.com/11783e6a751c5ff69bc3ca34b12138c6.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       pbr(true)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///       roughness(0.25)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           metallic(Float(i) * 0.5)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func metallic(_ value: Float) {
        context.metallic(value)
    }

    /// Sets the PBR roughness (this switches to PBR mode automatically).
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults (roughness 0.5, PBR
    ///   off) at the start of every frame, so call this from `draw()` — a call in `setup()` is
    ///   discarded before the first frame is drawn. `llms-sketch.txt` lists every state that does
    ///   and does not survive a frame boundary.
    ///
    /// - Parameter value: The roughness value (0 = smooth, 1 = rough).
    ///
    /// ### Result
    ///
    /// 0.1 / 0.45 / 0.8 from the left, all kept metal (`metallic(1)`). The rougher it
    /// gets, the wider and duller the highlight, moving from polished metal to a matte
    /// finish.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![roughness(_:) の実行結果](https://i.gyazo.com/3319317fd51bee92127acc9719282fbe.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       pbr(true)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///       metallic(1)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           roughness(0.1 + Float(i) * 0.35)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func roughness(_ value: Float) {
        context.roughness(value)
    }

    /// Sets the PBR ambient occlusion coefficient.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter value: The ambient occlusion value (0 = fully occluded, 1 = no occlusion).
    public func ambientOcclusion(_ value: Float) {
        context.ambientOcclusion(value)
    }

    // MARK: 3D Tone Mapping

    /// Sets the tone mapping applied to the 3D lighting result.
    ///
    /// The render target is LDR (8-bit), so a lighting result above 1.0 is clamped as is
    /// and the highlights blow out to white. Tone mapping rolls off the high end smoothly
    /// and keeps the gradation.
    ///
    /// ```swift
    /// toneMapping(.acesFilmic)
    /// metallic(0.9)
    /// roughness(0.25)
    /// sphere(80)
    /// ```
    ///
    /// The default is ``ToneMapMode/none`` (so that the image of an existing sketch does
    /// not change). **Specify ``ToneMapMode/acesFilmic`` explicitly when you use metals or
    /// strong light sources.**
    ///
    /// - Note: This applies to **the 3D lighting result only**. The colors of 2D drawing
    ///   do not change (the asymmetry is deliberate: 3D shading is a physical quantity,
    ///   while a 2D color is a final color). It does not apply to drawing with no lights
    ///   at all (the unlit pass) either.
    ///
    /// - Note: It is **not restored** by `pushStyle()` / `popStyle()`. It is treated as a
    ///   property of the whole screen.
    ///
    /// - Note: **Survives across frames.** Unlike the rest of the material state, tone mapping is
    ///   a property of the whole screen and is **not** reset at the start of a frame, so setting
    ///   it once in `setup()` is enough. `llms-sketch.txt` lists every state that does and does
    ///   not survive a frame boundary.
    ///
    /// - Parameter mode: The tone mapping method.
    public func toneMapping(_ mode: ToneMapMode) {
        context.toneMapping(mode)
    }

    /// Sets the exposure multiplier applied before tone mapping.
    ///
    /// The exposure applies regardless of the ``toneMapping(_:)`` mode. The default of 1.0
    /// is the identity multiplier, so the image does not change unless you set it.
    ///
    /// - Note: Affects **3D only** (ADR-0005). It is not restored by `pushStyle()` /
    ///   `popStyle()`.
    ///
    /// - Note: **Survives across frames.** Unlike the rest of the material state, the exposure is
    ///   a property of the whole screen and is **not** reset at the start of a frame, so setting
    ///   it once in `setup()` is enough. `llms-sketch.txt` lists every state that does and does
    ///   not survive a frame boundary.
    ///
    /// - Parameter value: The exposure multiplier (1.0 by default; larger is brighter).
    public func exposure(_ value: Float) {
        context.exposure(value)
    }

    // MARK: 3D Environment (IBL / skybox)

    /// Sets the environment (IBL and the background skybox).
    ///
    /// Under PBR, the higher `metallic` goes the more the diffuse reflection disappears
    /// (which is the physically correct behavior). What fills in for what is lost is **the
    /// reflection of the surrounding environment**, so raising `metallic` with no
    /// environment present gives a featureless gray lump instead of a metal.
    /// `environment()` supplies that environment, so only once you call it do `metallic`
    /// and `roughness` produce the material you intended.
    ///
    /// ```swift
    /// func setup() {
    ///     environment(.studio)   // This alone brings in both the IBL and the background
    /// }
    ///
    /// func draw() {
    ///     background(0)
    ///     directionalLight(-0.4, -0.6, -1, intensity: 2)
    ///     translate(width / 2, height / 2, 0)
    ///     metallic(0.9)
    ///     roughness(0.25)
    ///     sphere(120)
    /// }
    /// ```
    ///
    /// Every preset is generated procedurally, so no assets such as HDR images are needed.
    /// The bake (generating and convolving the cube map) runs only once per preset, and
    /// the cost on later frames is sampling alone.
    ///
    /// - Note: Affects **3D only** (ADR-0005). It is not restored by `pushStyle()` /
    ///   `popStyle()`; it is treated as a property of the whole screen.
    ///
    /// - Note: **Survives across frames.** Unlike the lights, the environment is **not** reset at
    ///   the start of a frame, so setting it once in `setup()` is enough. `llms-sketch.txt` lists
    ///   every state that does and does not survive a frame boundary.
    ///
    /// - Note: IBL applies to **the PBR path only** (when you call ``roughness(_:)`` or
    ///   enable ``pbr(_:)``). The Blinn-Phong image does not change.
    ///
    /// - Note: If tone mapping has not been specified, it is promoted automatically to
    ///   ``ToneMapMode/acesFilmic`` (because adding an environment pushes the luminance
    ///   above 1.0). If you specified ``toneMapping(_:)`` explicitly, that wins.
    ///
    /// - Note: When `background: true`, the skybox is drawn exactly once, **right before
    ///   the first 3D drawing**. Therefore 2D drawn before that is covered by the skybox,
    ///   while 2D drawn after it (a HUD or other foreground) stays on top. On a frame that
    ///   draws no 3D at all, the skybox is not drawn either.
    ///
    /// - Note: If ``ambientLight(_:)`` has not been specified explicitly, the default
    ///   ambient becomes 0 (so that it is not added twice with the diffuse term of the IBL).
    ///
    /// - Parameters:
    ///   - preset: The environment preset.
    ///   - intensity: The strength of the environment (1.0 by default). 0 or less disables it.
    ///   - background: When `true` (the default), it is drawn as the background as well.
    ///     Pass `false` when you want the IBL only.
    public func environment(
        _ preset: EnvironmentPreset,
        intensity: Float = 1.0,
        background: Bool = true
    ) {
        context.environment(preset, intensity: intensity, background: background)
    }

    /// Disables the environment (IBL and skybox).
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Survives across frames.** Unlike the lights, the environment is **not** reset at
    ///   the start of a frame, so setting it once in `setup()` is enough. `llms-sketch.txt` lists
    ///   every state that does and does not survive a frame boundary.
    public func noEnvironment() {
        context.noEnvironment()
    }

    /// Switches the PBR rendering mode explicitly.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The material returns to its defaults (PBR off) at the
    ///   start of every frame, so call this from `draw()` — a call in `setup()` is discarded
    ///   before the first frame is drawn. `llms-sketch.txt` lists every state that does and does
    ///   not survive a frame boundary.
    ///
    /// - Parameter enabled: Whether to enable PBR rendering.
    ///
    /// ### Result
    ///
    /// The same lights and the same ``fill(_:_:_:_:)``: the default Blinn-Phong on the
    /// left, PBR on the right (with ``metallic(_:)`` and ``roughness(_:)``). Direct light
    /// under PBR is attenuated by `albedo / π`, so it comes out darker with the same rig
    /// (see the description of ``lights()``).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![pbr(_:) の実行結果](https://i.gyazo.com/8f4a9111a6510b0a7238c4ca69cefba9.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       pbr(true)
    ///       metallic(0.9)
    ///       roughness(0.3)
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func pbr(_ enabled: Bool) {
        context.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// Creates a custom shader material from MSL source code.
    ///
    /// ``BuiltinShaders/canvas3DPreamble`` (the stdlib, the struct definitions for 3D, and
    /// the lighting functions) is **always** prepended, so writing just the fragment
    /// function is enough. Do not define `Canvas3DUniforms`, `Canvas3DVertexOut`, or the
    /// like yourself (#713).
    ///
    /// ```swift
    /// let mat = try createMaterial(source: """
    /// fragment float4 myFragment(Canvas3DVertexOut in [[stage_in]],
    ///                            constant Canvas3DUniforms &u [[buffer(1)]]) {
    ///     return float4(abs(normalize(in.normal)), 1.0);
    /// }
    /// """, fragmentFunction: "myFragment")
    /// material(mat)
    /// box(100)
    /// noMaterial()
    /// ```
    ///
    /// - Note: The material that is created applies to **3D only**. To apply a custom
    ///   shader to 2D, use ``loadShader(_:fragment:)`` / ``shader(_:)`` (ADR-0005).
    ///
    /// - Parameters:
    ///   - source: The Metal Shading Language source code.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The name of a custom vertex function (optional).
    /// - Returns: A new ``CustomMaterial`` instance.
    /// - Throws: ``MetaphorError``. If the MSL fails to compile,
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``; if the specified
    ///   function is not found, ``MetaphorError/MaterialFailure/shaderNotFound(_:)`` of
    ///   ``MetaphorError/material(_:)``.
    public func createMaterial(
        source: String, fragmentFunction: String, vertexFunction: String? = nil
    ) throws -> CustomMaterial {
        try context.createMaterial(
            source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// Applies a custom material to subsequent 3D drawing.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The custom material binding is cleared at the start of
    ///   every frame, so call this from `draw()` — a call in `setup()` is discarded before the
    ///   first frame is drawn. `llms-sketch.txt` lists every state that does and does not survive
    ///   a frame boundary.
    ///
    /// - Parameter customMaterial: The custom material to apply.
    public func material(_ customMaterial: CustomMaterial) {
        context.material(customMaterial)
    }

    /// Clears the active custom material and returns to the default shading.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The custom material binding is cleared at the start of
    ///   every frame, so call this from `draw()` — a call in `setup()` is discarded before the
    ///   first frame is drawn. `llms-sketch.txt` lists every state that does and does not survive
    ///   a frame boundary.
    public func noMaterial() {
        context.noMaterial()
    }

    // MARK: 3D Texture

    /// Sets the texture for subsequent 3D shapes.
    ///
    /// - Note: Affects **3D only** (to draw an image in 2D, use `image()`. ADR-0005).
    ///
    /// - Note: **Resets every frame.** The texture binding is cleared at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    ///
    /// - Parameter img: The texture image.
    public func texture(_ img: MImage) {
        context.texture(img)
    }

    /// Clears the active texture.
    ///
    /// - Note: Affects **3D only** (ADR-0005).
    ///
    /// - Note: **Resets every frame.** The texture binding is cleared at the start of every
    ///   frame, so call this from `draw()` — a call in `setup()` is discarded before the first
    ///   frame is drawn. `llms-sketch.txt` lists every state that does and does not survive a
    ///   frame boundary.
    public func noTexture() {
        context.noTexture()
    }

    // MARK: 3D Transform Stack

    /// Saves the current transform matrix (both 2D and 3D) onto the stack.
    ///
    /// - Note: Affects **both 2D and 3D**. What sets it apart from ``push()`` is not what
    ///   it affects but whether style is included: this one saves the transform only.
    public func pushMatrix() {
        context.pushMatrix()
    }

    /// Restores the last saved transform matrix (both 2D and 3D) from the stack.
    ///
    /// - Note: Affects **both 2D and 3D** (the counterpart of ``pushMatrix()``).
    public func popMatrix() {
        context.popMatrix()
    }

    /// Applies a 3D translation to the current transform.
    ///
    /// - Note: Affects **3D only**. The two-argument ``translate(_:_:)`` affects both 2D
    ///   and 3D (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameters:
    ///   - x: The amount to move along the x axis.
    ///   - y: The amount to move along the y axis.
    ///   - z: The amount to move along the z axis.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        context.translate(x, y, z)
    }

    /// Applies a rotation around the x axis.
    ///
    /// - Note: Affects **3D only** (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The rotation angle in radians.
    ///
    /// ### Result
    ///
    /// 0 / 0.5 / 1.0 radians from the left. Around the x axis (the horizontal direction of
    /// the screen), the top edge tips away from the viewer.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotateX(_:) の実行結果](https://i.gyazo.com/b0b8e39439a4f019fce20cc0b3d9b242.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               110 + Float(i) * 130,
    ///               height / 2, 0
    ///           )
    ///           rotateX(Float(i) * 0.5)
    ///           box(95)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func rotateX(_ angle: Float) {
        context.rotateX(angle)
    }

    /// Applies a rotation around the y axis.
    ///
    /// - Note: Affects **3D only** (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The rotation angle in radians.
    ///
    /// ### Result
    ///
    /// Using `frameCount` as the angle keeps it turning around the y axis (the vertical
    /// direction of the screen).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotateY(_:) の実行結果（動き）](https://i.gyazo.com/c3943175afcd9b9dbe6774544cce3d6d.gif)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateY(Float(frameCount) * 0.0873)
    ///       rotateX(-0.3)
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func rotateY(_ angle: Float) {
        context.rotateY(angle)
    }

    /// Applies a rotation around the z axis.
    ///
    /// - Note: Affects **3D only**. The one-argument ``rotate(_:)`` affects both 2D and
    ///   3D, and on the 3D side it is the same rotation around the z axis as this method
    ///   (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) {
        context.rotateZ(angle)
    }

    /// Applies a non-uniform 3D scale to the current transform.
    ///
    /// - Note: Affects **3D only**. The two-argument ``scale(_:_:)`` affects both 2D and
    ///   3D (ADR-0005 Amendment 2026-08-02).
    ///
    /// - Parameters:
    ///   - x: The scale factor along the x axis.
    ///   - y: The scale factor along the y axis.
    ///   - z: The scale factor along the z axis.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        context.scale(x, y, z)
    }

    // MARK: 3D Shapes

    /// Draws a box of the given size.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - width: The width of the box.
    ///   - height: The height of the box.
    ///   - depth: The depth of the box.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        context.box(width, height, depth)
    }

    /// Draws a cube whose edges are all the same length.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameter size: The edge length.
    ///
    /// ### Result
    ///
    /// The origin of the default camera is the top-left corner of the canvas, so
    /// ``translate(_:_:_:)`` brings it to the center. Head-on it would look like nothing
    /// but a square, so it is tilted around two axes.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![box(_:) の実行結果](https://i.gyazo.com/0628f02a4dc47cb59470fef39ebbb2ee.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateY(0.6)
    ///       rotateX(-0.35)
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func box(_ size: Float) {
        context.box(size)
    }

    /// Draws a sphere.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the sphere.
    ///   - detail: The subdivision count of the mesh tessellation.
    ///
    /// ### Result
    ///
    /// `detail` is how finely the sphere is subdivided; a small value turns it into a
    /// polyhedron (`detail: 5` on the left, the default of 24 on the right).
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![sphere(_:detail:) の実行結果](https://i.gyazo.com/8c6edd1a90dba05c05819b18ef94be4d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///
    ///       push()
    ///       translate(130, height / 2, 0)
    ///       sphere(80, detail: 5)
    ///       pop()
    ///
    ///       push()
    ///       translate(350, height / 2, 0)
    ///       sphere(80)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func sphere(_ radius: Float, detail: Int = 24) {
        context.sphere(radius, detail: detail)
    }

    /// Draws a plane.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - width: The width of the plane.
    ///   - height: The height of the plane.
    ///
    /// ### Result
    ///
    /// Head-on it would be indistinguishable from ``rect(_:_:_:_:)``, so ``rotateX(_:)``
    /// lays it down to bring out the depth.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![plane(_:_:) の実行結果](https://i.gyazo.com/2e0a8660fec506bbd00c282c843ab94e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 220, 120)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-1.1)
    ///       plane(280, 220)
    ///       ```
    ///    }
    /// }
    public func plane(_ width: Float, _ height: Float) {
        context.plane(width, height)
    }

    /// Draws a cylinder.
    ///
    /// The default camera is a pixel space (1 world unit = 1 pixel), so `radius` and
    /// `height` are given at pixel-equivalent sizes.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the cylinder.
    ///   - height: The height of the cylinder.
    ///   - detail: The subdivision count around the circumference.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![cylinder(radius:height:detail:) の実行結果](https://i.gyazo.com/47680338f40c5454225003010160b2a1.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 150, 120)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.45)
    ///       cylinder(radius: 80, height: 190)
    ///       ```
    ///    }
    /// }
    public func cylinder(radius: Float, height: Float, detail: Int = 24) {
        context.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draws a cone.
    ///
    /// The default camera is a pixel space (1 world unit = 1 pixel), so `radius` and
    /// `height` are given at pixel-equivalent sizes.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the base.
    ///   - height: The height of the cone.
    ///   - detail: The subdivision count around the circumference.
    ///
    /// ### Result
    ///
    /// The y axis points down the screen, so drawn as is the **apex points downward**. To
    /// get a cone that points up, turn it half a revolution with ``rotateZ(_:)``.
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![cone(radius:height:detail:) の実行結果](https://i.gyazo.com/26fccf002e09c5699fcf42b9935b6379.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 205, 90)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.45)
    ///       cone(radius: 95, height: 200)
    ///       ```
    ///    }
    /// }
    public func cone(radius: Float, height: Float, detail: Int = 24) {
        context.cone(radius: radius, height: height, detail: detail)
    }

    /// Draws a torus (a doughnut shape).
    ///
    /// The default camera is a pixel space (1 world unit = 1 pixel), so `ringRadius` and
    /// `tubeRadius` are given at pixel-equivalent sizes.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The subdivision count.
    ///
    /// ### Result
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![torus(ringRadius:tubeRadius:detail:) の実行結果](https://i.gyazo.com/6238ad4f021c6d0294b39d844d9796f0.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(200, 140, 255)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.95)
    ///       torus(
    ///           ringRadius: 110,
    ///           tubeRadius: 40
    ///       )
    ///       ```
    ///    }
    /// }
    public func torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24) {
        context.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draws a prebuilt mesh.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) {
        context.mesh(mesh)
    }

    /// Draws the same mesh in one batch with multiple transforms (explicit instancing).
    ///
    /// Each instance is drawn with "the current transform matrix × `transforms[i]`". This
    /// is equivalent to the loop below, but lighter on the CPU because the state is
    /// evaluated only once.
    ///
    /// ```swift
    /// for t in transforms {
    ///     pushMatrix(); applyMatrix(t); mesh(m); popMatrix()
    /// }
    /// ```
    ///
    /// fill, stroke, material, texture, and the lights are shared across instances (the
    /// only thing that can vary per instance is the fill color of
    /// ``drawInstanced(_:transforms:colors:)``).
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - mesh: The mesh to draw.
    ///   - transforms: The local transform of each instance. An empty array draws nothing.
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4]) {
        context.drawInstanced(mesh, transforms: transforms)
    }

    /// Draws the same mesh in one batch with a per-instance fill color.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameters:
    ///   - mesh: The mesh to draw.
    ///   - transforms: The local transform of each instance. An empty array draws nothing.
    ///   - colors: The fill color of each instance. When it is shorter than `transforms`,
    ///     the current fill color is used for the shortfall; when it is longer, the excess
    ///     is ignored. The stroke color and the material stay shared.
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4], colors: [Color]) {
        context.drawInstanced(mesh, transforms: transforms, colors: colors)
    }

    /// Draws a dynamic mesh.
    ///
    /// - Note: Affects **3D only** (it is drawn on the 3D canvas. ADR-0005).
    ///
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        context.dynamicMesh(mesh)
    }

    /// Creates a new, empty dynamic mesh.
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``dynamicMesh(_:)``. ADR-0005).
    ///
    /// - Returns: A new ``DynamicMesh`` instance.
    public func createDynamicMesh() -> DynamicMesh {
        context.createDynamicMesh()
    }

    // MARK: - プリミティブメッシュの生成

    /// Creates a box mesh (without drawing it).
    ///
    /// Where ``box(_:_:_:)`` draws, this one returns a ``Mesh`` **as a value**, meant to be
    /// handed to ``mesh(_:)`` or ``drawInstanced(_:transforms:)``.
    ///
    /// ```swift
    /// func setup() {
    ///     cube = createBoxMesh(12)
    /// }
    /// func draw() {
    ///     drawInstanced(cube, transforms: transforms)
    /// }
    /// ```
    ///
    /// Calling it again with the same arguments returns the same instance (the same
    /// behavior as ``loadModel(_:normalize:cache:)``). Calling it with different dimensions
    /// every frame keeps rebuilding the mesh, so create it in `setup()` and express changes
    /// in size with ``scale(_:)`` or on the `transforms` side.
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - width: The width of the box.
    ///   - height: The height of the box.
    ///   - depth: The depth of the box.
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createBoxMesh(_ width: Float, _ height: Float, _ depth: Float) -> Mesh? {
        context.createBoxMesh(width, height, depth)
    }

    /// Creates a cube mesh with equal dimensions (without drawing it).
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameter size: The edge length of the cube.
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createBoxMesh(_ size: Float) -> Mesh? {
        context.createBoxMesh(size)
    }

    /// Creates a sphere mesh (without drawing it).
    ///
    /// `detail` is interpreted the same way as in ``sphere(_:detail:)``, so the same
    /// arguments produce the same geometry.
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the sphere.
    ///   - detail: The subdivision count (24 by default).
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createSphereMesh(_ radius: Float, detail: Int = 24) -> Mesh? {
        context.createSphereMesh(radius, detail: detail)
    }

    /// Creates a plane mesh (without drawing it).
    ///
    /// It is a rectangle on the XY plane, with its normal pointing along +Z.
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - width: The width of the plane.
    ///   - height: The height of the plane.
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createPlaneMesh(_ width: Float, _ height: Float) -> Mesh? {
        context.createPlaneMesh(width, height)
    }

    /// Creates a cylinder mesh (without drawing it).
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the cylinder.
    ///   - height: The height of the cylinder.
    ///   - detail: The subdivision count (24 by default).
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createCylinderMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        context.createCylinderMesh(radius: radius, height: height, detail: detail)
    }

    /// Creates a cone mesh (without drawing it).
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - radius: The radius of the base.
    ///   - height: The height of the cone.
    ///   - detail: The subdivision count (24 by default).
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createConeMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        context.createConeMesh(radius: radius, height: height, detail: detail)
    }

    /// Creates a torus mesh (without drawing it).
    ///
    /// `detail` is interpreted the same way as in ``torus(ringRadius:tubeRadius:detail:)``,
    /// so the same arguments produce the same geometry.
    ///
    /// - Note: The mesh that is created can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The subdivision count (24 by default).
    /// - Returns: The created mesh, or `nil` if the GPU buffer could not be allocated.
    public func createTorusMesh(ringRadius: Float, tubeRadius: Float, detail: Int = 24) -> Mesh? {
        context.createTorusMesh(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Loads a 3D model from a file (OBJ, USDZ, or ABC).
    ///
    /// A path-keyed cache is enabled by default, so reloading the same path with the same
    /// `normalize` returns the same ``Mesh`` instance.
    ///
    /// - Note: The mesh that is loaded can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - path: The file path of the model.
    ///   - normalize: Whether to normalize the bounding box (`true` by default).
    ///     Normalizing centers it on the origin and makes **the longest edge 2 units**
    ///     ([-1, 1]), so drawing it as is on a canvas in pixel coordinates leaves it only a
    ///     few pixels across. Give it a size with ``scale(_:)``. Pass `false` to use the
    ///     coordinates of the model as they are.
    ///   - cache: Whether to use the cache (`true` by default; `false` loads an independent copy).
    /// - Returns: The loaded mesh, or `nil` if loading failed.
    public func loadModel(_ path: String, normalize: Bool = true, cache: Bool = true) -> Mesh? {
        context.loadModel(path, normalize: normalize, cache: cache)
    }

    /// Loads a 3D model asynchronously (the parsing runs off the main thread).
    ///
    /// - Note: The mesh that is loaded can be drawn in **3D only**
    ///   (``mesh(_:)`` / ``drawInstanced(_:transforms:)``. ADR-0005).
    ///
    /// - Parameters:
    ///   - path: The file path of the model.
    ///   - normalize: Whether to normalize the bounding box (`true` by default).
    ///     Normalizing centers it on the origin and makes **the longest edge 2 units**
    ///     ([-1, 1]), so drawing it as is on a canvas in pixel coordinates leaves it only a
    ///     few pixels across. Give it a size with ``scale(_:)``. Pass `false` to use the
    ///     coordinates of the model as they are.
    ///   - cache: Whether to use the cache (`true` by default; the same instance is returned).
    /// - Returns: The loaded mesh.
    /// - Throws: If the model cannot be parsed (no mesh, no vertex positions, an empty
    ///   mesh, and so on), ``MetaphorError/MeshFailure/parseError(_:)`` of
    ///   ``MetaphorError/mesh(_:)``; if the GPU buffer cannot be allocated,
    ///   ``MetaphorError/bufferCreationFailed(size:)``.
    public func loadModelAsync(
        _ path: String, normalize: Bool = true, cache: Bool = true
    ) async throws -> Mesh {
        try await context.loadModelAsync(path, normalize: normalize, cache: cache)
    }
}
