// MARK: - Image, Text, Recording, Feedback

extension Sketch {

    // MARK: Image

    /// Loads an image from the given file path.
    ///
    /// A path-keyed cache is enabled by default, so reloading the same path returns the same
    /// ``MImage`` instance (calling it inside `draw()` does not re-decode the image every frame).
    /// Pass `cache: false` when an independent copy is needed.
    ///
    /// - Parameters:
    ///   - path: The file path of the image.
    ///   - cache: Whether to use the cache (true by default).
    /// - Returns: The loaded image.
    /// - Throws: ``MetaphorError/image(_:)`` with ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   when the texture cannot be loaded from the given path (missing, unsupported format, or
    ///   an I/O error).
    public func loadImage(_ path: String, cache: Bool = true) throws -> MImage {
        try context.loadImage(path, cache: cache)
    }

    /// Loads an image asynchronously, running the file I/O off the main thread.
    ///
    /// - Parameters:
    ///   - path: The file path of the image.
    ///   - cache: Whether to use the cache (true by default).
    /// - Returns: The loaded image.
    /// - Throws: ``MetaphorError/image(_:)`` with ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   when the texture cannot be loaded from the given path (missing, unsupported format, or
    ///   an I/O error).
    public func loadImageAsync(_ path: String, cache: Bool = true) async throws -> MImage {
        try await context.loadImageAsync(path, cache: cache)
    }

    /// Loads a named image resource asynchronously.
    ///
    /// - Parameter name: The name of the image resource.
    /// - Returns: The loaded image.
    /// - Throws: ``MetaphorError/image(_:)`` with ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   when the named resource cannot be found or loaded.
    public func loadImageAsync(named name: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(named: name)
    }

    /// Returns the glyph outlines of a text as closed polylines, one per contour.
    ///
    /// The current ``textSize(_:)``, ``textFont(_:)-(String)``, and ``textAlign(_:_:)`` are
    /// interpreted the same way `text()` interprets them, so calling it with the same arguments
    /// yields outlines at the same position as the drawn result. Holes in a glyph, such as the
    /// inside of an `o`, also come back as contours of their own.
    ///
    /// A string containing newlines is laid out line by line just as ``text(_:_:_:)`` does, and the
    /// line height follows ``textLeading(_:)``.
    ///
    /// - Parameters:
    ///   - string: The text to take the outlines from.
    ///   - x: The x coordinate of the text (the same meaning as in `text()`).
    ///   - y: The y coordinate of the text (the same meaning as in `text()`).
    ///   - sampleFactor: How finely curves are subdivided into line segments. Larger values produce
    ///     more points.
    /// - Returns: One polyline per contour.
    public func textToContours(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [[Vec2]] {
        context.textToContours(string, x, y, sampleFactor: sampleFactor)
    }

    /// Returns the points along the glyph outlines of a text as a single flat array (the equivalent
    /// of p5's `textToPoints`).
    ///
    /// The contour boundaries are lost. It suits using the letters as the source positions for
    /// particles or shapes.
    ///
    /// ```swift
    /// for p in textToPoints("metaphor", 40, 200) {
    ///     circle(p.x, p.y, 4)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - string: The text to take the outlines from.
    ///   - x: The x coordinate of the text (the same meaning as in `text()`).
    ///   - y: The y coordinate of the text (the same meaning as in `text()`).
    ///   - sampleFactor: How finely curves are subdivided into line segments. Larger values produce
    ///     more points.
    /// - Returns: The points along the outlines.
    public func textToPoints(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [Vec2] {
        context.textToPoints(string, x, y, sampleFactor: sampleFactor)
    }

    /// Converts the outlines of a text into a retained shape that can be drawn with its holes.
    ///
    /// The result is a group shape with one child per outer contour. Holes such as the inside of an
    /// `o` ride on the child as contours, so ``shape(_:_:_:)`` fills them correctly as they are.
    ///
    /// - Parameters:
    ///   - string: The text to take the outlines from.
    ///   - x: The x coordinate of the text (the same meaning as in `text()`).
    ///   - y: The y coordinate of the text (the same meaning as in `text()`).
    ///   - sampleFactor: How finely curves are subdivided into line segments. Larger values produce
    ///     more points.
    /// - Returns: A group shape that captured the current style.
    public func textToShape(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> MShape {
        context.textToShape(string, x, y, sampleFactor: sampleFactor)
    }

    /// Loads a font from the given file path.
    ///
    /// The font is registered with the current process only; it does not change the system font
    /// settings. Passing the returned ``MFont`` to ``textFont(_:)-(MFont)`` makes subsequent text
    /// drawing and measurement use that font. A path-keyed cache is enabled by default, so calling
    /// it inside `draw()` does not re-register the font every frame.
    ///
    /// ```swift
    /// func setup() {
    ///     guard let path = Bundle.module.path(
    ///         forResource: "SpaceMono-Regular", ofType: "ttf", inDirectory: "Resources")
    ///     else { return }
    ///     textFont(try! loadFont(path))
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: The path of the font file (`.ttf` / `.otf` / `.ttc` / `.otc` / `.dfont`).
    ///   - cache: Whether to use the cache (true by default).
    /// - Returns: The loaded font.
    /// - Throws: ``MetaphorError/font(_:)``. A missing file raises
    ///   ``MetaphorError/FontFailure/fileNotFound(path:)``, a file that cannot be read as a font
    ///   raises ``MetaphorError/FontFailure/noFontsInFile(path:)``, and a failed registration
    ///   raises ``MetaphorError/FontFailure/registrationFailed(path:detail:)``.
    public func loadFont(_ path: String, cache: Bool = true) throws -> MFont {
        try context.loadFont(path, cache: cache)
    }

    /// Creates a blank image of the given size.
    ///
    /// - Parameters:
    ///   - width: The image width in pixels. 1 or greater.
    ///   - height: The image height in pixels. 1 or greater.
    /// - Returns: The new blank image, or `nil` when creation fails (including a width or height
    ///   below 1).
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        context.createImage(width, height)
    }

    /// Applies a GPU image filter to an image, in place.
    ///
    /// It runs on the renderer's compute pipeline, which makes it faster than the CPU version,
    /// ``MImage/filter(_:)``. Which one to use:
    ///
    /// - **The GPU version (this method)**: use it while the sketch is running, in a context where
    ///   the renderer is alive. This is the one for applying a filter every frame.
    /// - **The CPU version, ``MImage/filter(_:)``**: it does not need the renderer, so it can be
    ///   used outside a sketch or to batch-process standalone images. It runs
    ///   `loadPixels()` → processing → `updatePixels()` in one go.
    ///
    /// - Parameters:
    ///   - image: The target image (its contents are overwritten).
    ///   - type: The filter type to apply.
    public func filter(_ image: MImage, _ type: FilterType) {
        context.filter(image, type)
    }

    /// Copies a rectangular region of the canvas into another rectangular region (compatible with
    /// Processing's `copy()`).
    ///
    /// The source is the current contents of the offscreen render target, which is everything drawn
    /// up to the previous frame. It is scaled when the sizes differ. It is drawn in absolute
    /// coordinates, unaffected by `imageMode` and `tint`.
    ///
    /// - Parameters:
    ///   - sx: The x of the source rectangle, in pixels.
    ///   - sy: The y of the source rectangle, in pixels.
    ///   - sw: The width of the source rectangle, in pixels.
    ///   - sh: The height of the source rectangle, in pixels.
    ///   - dx: The x of the destination rectangle, in pixels.
    ///   - dy: The y of the destination rectangle, in pixels.
    ///   - dw: The width of the destination rectangle, in pixels.
    ///   - dh: The height of the destination rectangle, in pixels.
    public func copy(
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float
    ) {
        context.copy(sx, sy, sw, sh, dx, dy, dw, dh)
    }

    /// Creates a 2D offscreen graphics buffer that starts out transparent.
    ///
    /// The buffer begins fully transparent (alpha 0), so placing it over the main canvas with
    /// `image()` — or in the foreground of a `MergePass(.alpha)` — leaves whatever is underneath
    /// visible. Call `background()` between `beginDraw()` and `endDraw()` for an opaque
    /// backdrop (#914).
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels. 1 or greater.
    ///   - h: The buffer height in pixels. 1 or greater.
    /// - Returns: The new ``Graphics`` instance, or `nil` when creation fails (including a width or
    ///   height below 1).
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        context.createGraphics(w, h)
    }

    /// Creates a 3D offscreen graphics buffer that starts out transparent.
    ///
    /// As with ``createGraphics(_:_:)``, the buffer begins fully transparent (alpha 0) so it can be
    /// layered. Call `background()` between `beginDraw()` and `endDraw()` for an opaque
    /// backdrop (#914).
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels. 1 or greater.
    ///   - h: The buffer height in pixels. 1 or greater.
    /// - Returns: The new ``Graphics3D`` instance, or `nil` when creation fails (including a width
    ///   or height below 1).
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        context.createGraphics3D(w, h)
    }

    /// Lists the connected cameras.
    ///
    /// Built-in cameras, external (USB) cameras, Continuity Camera, and Desk View cameras are all
    /// covered. Passing the ``CaptureDeviceInfo`` you obtain to
    /// ``createCapture(width:height:device:)`` selects explicitly which camera to use in a
    /// multi-camera setup.
    ///
    /// ```swift
    /// for cam in listCaptureDevices() {
    ///     print(cam.name, cam.kind)
    /// }
    /// ```
    ///
    /// - Returns: The list of connected cameras (an empty array when none are connected).
    public func listCaptureDevices() -> [CaptureDeviceInfo] {
        context.listCaptureDevices()
    }

    /// Creates a camera capture device and **starts capturing automatically**
    /// (there is no need to call `start()`; call `stop()` to stop).
    ///
    /// - Note: A device with `isAvailable == false` is returned when camera permission has been
    ///   denied. Disconnection of the camera in use can be detected with
    ///   ``CaptureDevice/onDisconnect``.
    ///
    /// - Parameters:
    ///   - width: The requested capture width (1280 by default). The closest supported resolution
    ///     is selected, and the actual value can be checked with ``CaptureDevice/actualWidth``.
    ///   - height: The requested capture height (720 by default).
    ///   - position: The camera position to use. When `nil` (the default), the user's or system's
    ///     preferred camera is used. Most cameras on macOS carry no position information, so use
    ///     ``createCapture(width:height:device:)`` to select a specific camera.
    /// - Returns: The started capture device.
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition? = nil)
        -> CaptureDevice
    {
        context.createCapture(width: width, height: height, position: position)
    }

    /// Creates a capture device for the given camera and **starts capturing automatically**.
    ///
    /// ```swift
    /// if let external = listCaptureDevices().first(where: { $0.kind == .external }) {
    ///     capture = createCapture(device: external)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - width: The requested capture width (1280 by default). The closest supported resolution
    ///     is selected, and the actual value can be checked with ``CaptureDevice/actualWidth``.
    ///   - height: The requested capture height (720 by default).
    ///   - device: The device information obtained from ``listCaptureDevices()``.
    ///     A device with `isAvailable == false` is returned when it has already been disconnected.
    /// - Returns: The started capture device.
    public func createCapture(width: Int = 1280, height: Int = 720, device: CaptureDeviceInfo)
        -> CaptureDevice
    {
        context.createCapture(width: width, height: height, device: device)
    }

    /// Creates a capture device by selecting a camera by name and **starts capturing
    /// automatically**.
    ///
    /// A case-insensitive exact match takes priority; failing that, a partial match is used.
    ///
    /// ```swift
    /// capture = createCapture(deviceName: "FaceTime")
    /// ```
    ///
    /// - Parameters:
    ///   - width: The requested capture width (1280 by default). The closest supported resolution
    ///     is selected, and the actual value can be checked with ``CaptureDevice/actualWidth``.
    ///   - height: The requested capture height (720 by default).
    ///   - deviceName: The name of the camera to select. A device with `isAvailable == false` is
    ///     returned when no camera matches.
    /// - Returns: The started capture device.
    public func createCapture(width: Int = 1280, height: Int = 720, deviceName: String)
        -> CaptureDevice
    {
        context.createCapture(width: width, height: height, deviceName: deviceName)
    }

    /// Draws the latest frame of a capture device at the given position.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        context.image(capture, x, y)
    }

    /// Draws the latest frame of a capture device at the given position and size.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(capture, x, y, w, h)
    }

    /// Draws a 2D offscreen graphics buffer at the given position.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// Draws a 2D offscreen graphics buffer at the given position and size.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// Draws a 3D offscreen graphics buffer at the given position.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// Draws a 3D offscreen graphics buffer at the given position and size.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// Draws an image at the given position.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        context.image(img, x, y)
    }

    /// Draws an image at the given position and size.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x coordinate of the drawing position.
    ///   - y: The y coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(img, x, y, w, h)
    }

    /// Draws a subregion of an image, for sprite sheets and tile maps.
    ///
    /// - Parameters:
    ///   - img: The source image.
    ///   - dx: The x coordinate of the destination.
    ///   - dy: The y coordinate of the destination.
    ///   - dw: The width of the destination.
    ///   - dh: The height of the destination.
    ///   - sx: The x coordinate of the source region.
    ///   - sy: The y coordinate of the source region.
    ///   - sw: The width of the source region.
    ///   - sh: The height of the source region.
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        context.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: Text

    /// Sets the text size for subsequent text drawing.
    ///
    /// As in Processing, the leading (``textLeading(_:)``) returns to the default derived from the
    /// font. Call ``textLeading(_:)`` after this one when you want to specify the leading.
    ///
    /// - Parameter size: The font size, in points.
    public func textSize(_ size: Float) {
        context.textSize(size)
    }

    /// Sets the font family for subsequent text drawing.
    ///
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) {
        context.textFont(family)
    }

    /// Sets the font used for subsequent text drawing from the result of ``loadFont(_:cache:)``.
    ///
    /// - Parameter font: The loaded font.
    public func textFont(_ font: MFont) {
        context.textFont(font)
    }

    /// Sets the text alignment.
    ///
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        context.textAlign(horizontal, vertical)
    }

    /// Sets the leading (line height) for multi-line text.
    ///
    /// It is the distance between the baselines of adjacent lines. Calling ``textSize(_:)`` or
    /// ``textFont(_:)-(String)`` returns it to the default, so call this one afterwards.
    ///
    /// - Parameter leading: The line height, in pixels.
    public func textLeading(_ leading: Float) {
        context.textLeading(leading)
    }

    /// Draws a text string at the given position.
    ///
    /// A string containing newlines (`\n`) is drawn as multiple lines, with the line height taken
    /// from ``textLeading(_:)``.
    ///
    /// Glyphs are always filled with the current `fill()` color. ``noFill()`` applies to shapes
    /// only and **has no effect on text** (in Processing `noFill()` makes the glyphs disappear, but
    /// metaphor's text has no stroke path, so the two were deliberately left out of step — the
    /// decision in [#519]). To keep the glyphs from appearing, either drop the call itself or use a
    /// fill with alpha 0 such as `fill(255, 0)` (alpha does reach the glyphs). `tint()` is for
    /// images and has no effect on the text color.
    ///
    /// [#519]: https://github.com/shinyaoguri/metaphor/issues/519
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        context.text(string, x, y)
    }

    /// Draws a text string inside a bounding box.
    ///
    /// It wraps automatically at the width of the box. Lines that do not fit within the height of
    /// the box are not drawn.
    ///
    /// Color is handled exactly as in ``text(_:_:_:)``, so ``noFill()`` has no effect on text.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x coordinate of the bounding box.
    ///   - y: The y coordinate of the bounding box.
    ///   - w: The width of the bounding box.
    ///   - h: The height of the bounding box.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.text(string, x, y, w, h)
    }

    /// Computes the width of a text string with the current font settings.
    ///
    /// It returns the sum of the per-character advances, which matches both the width
    /// ``text(_:_:_:)`` actually lays the glyphs out in and the width ``textAlign(_:_:)`` aligns
    /// against. It is additive (`textWidth("ab") == textWidth("a") + textWidth("b")`), so lines can
    /// be composed by measuring word by word. Whitespace at either end counts, and, as in
    /// Processing, no kerning is applied.
    ///
    /// For a string containing newlines it returns the width of the longest line.
    ///
    /// - Parameter string: The text to measure.
    /// - Returns: The width of the text, in pixels.
    public func textWidth(_ string: String) -> Float {
        context.textWidth(string)
    }

    /// Returns the ascent of the current font.
    ///
    /// - Returns: The ascent, in pixels.
    public func textAscent() -> Float {
        context.textAscent()
    }

    /// Returns the descent of the current font.
    ///
    /// - Returns: The descent, in pixels.
    public func textDescent() -> Float {
        context.textDescent()
    }

    // MARK: Screenshot & Recording

    /// Saves the current frame to the given file path.
    ///
    /// A relative path is resolved from **the project root** (the package root under `swift run`,
    /// or that project under `metaphor run` / `watch`). Absolute paths and paths starting with `~`
    /// are used as they are.
    ///
    /// As with ``saveFrame(_:)``, calling it several times within the same frame writes the same
    /// image — the final output of that frame — to every destination.
    ///
    /// - Parameter path: The output file path.
    public func save(_ path: String) {
        context.save(path)
    }

    /// Saves the current frame to `output/metaphor_<timestamp>.png`.
    public func save() {
        context.save()
    }

    // MARK: SVG Export

    /// Starts SVG recording (the equivalent of Processing's `beginRecord(SVG, path)`).
    ///
    /// The 2D drawing calls up to ``endSVGRecord()`` are recorded as true vectors (`<circle>`,
    /// `<path>`, and so on) in parallel with the rasterization to the screen. It suits output aimed
    /// at plotters (AxiDraw and the like) or at print. Unsupported features (`image()`, `text()`,
    /// and so on) emit a warning and are skipped.
    ///
    /// ```swift
    /// func draw() {
    ///     if wantExport { beginSVGRecord("output/sketch.svg") }
    ///     background(255)
    ///     circle(width / 2, height / 2, 200)
    ///     if wantExport { endSVGRecord(); wantExport = false }
    /// }
    /// ```
    ///
    /// - Parameter path: The path of the SVG file to write.
    public func beginSVGRecord(_ path: String) {
        context.beginSVGRecord(path)
    }

    /// Ends SVG recording and writes the result to the path given to ``beginSVGRecord(_:)``.
    public func endSVGRecord() {
        context.endSVGRecord()
    }

    /// Starts recording as a numbered sequence of image files.
    ///
    /// Until ``endFrameRecord()`` is called, every frame is written to `directory` under a
    /// sequential file name that follows `pattern`.
    ///
    /// - Parameters:
    ///   - directory: The output directory (`output/metaphor_frames_<timestamp>/` when `nil`).
    ///     A relative path is resolved from the project root.
    ///   - pattern: The file name pattern, including the frame-number placeholder.
    public func beginFrameRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        context.beginFrameRecord(directory: directory, pattern: pattern)
    }

    /// Stops the numbered frame recording.
    public func endFrameRecord() {
        context.endFrameRecord()
    }

    /// Saves a single frame to an image file.
    ///
    /// The destination is decided by the following rules.
    ///
    /// - `saveFrame()` — `output/screen-<frame number>.png` (inside the project)
    /// - `saveFrame("shots/a.png")` — relative to the project root
    /// - `saveFrame("/tmp/a.png")` / `saveFrame("~/Pictures/a.png")` — used as it is
    ///
    /// Calling it several times within the same frame writes that frame to every destination (a
    /// fixed path to keep updated plus a numbered sequence for history, for example). What gets
    /// saved is **the final output of that frame**, not the work in progress at the moment of the
    /// call, so the contents of every destination are identical.
    ///
    /// - Parameter filename: The output file name (generated automatically when `nil`).
    public func saveFrame(_ filename: String? = nil) {
        context.saveFrame(filename)
    }

    // MARK: Video Recording

    /// Starts recording the video output.
    ///
    /// - Parameters:
    ///   - path: The output file path (`output/metaphor_<timestamp>.<extension>` when `nil`).
    ///     A relative path is resolved from the project root.
    ///   - config: The video export settings.
    public func beginVideoRecord(
        _ path: String? = nil, config: VideoExportConfig = VideoExportConfig()
    ) {
        context.beginVideoRecord(path, config: config)
    }

    /// Stops the video recording and finalizes the file.
    ///
    /// - Parameter completion: An optional callback invoked when writing completes.
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        context.endVideoRecord(completion: completion)
    }

    /// Stops the video recording asynchronously and finalizes the file.
    ///
    /// The async/await version of ``endVideoRecord(completion:)``.
    public func endVideoRecordAsync() async {
        await context.endVideoRecordAsync()
    }

    // MARK: Offline Rendering

    /// A Boolean value indicating whether offline rendering mode is active.
    public var isOfflineRendering: Bool {
        context.isOfflineRendering
    }

    /// Enables offline rendering mode with deterministic timing.
    ///
    /// - Parameter fps: The virtual frame rate used for time calculations.
    public func beginOfflineRender(fps: Double = 60) {
        context.beginOfflineRender(fps: fps)
    }

    /// Disables offline rendering mode and returns to real-time timing.
    public func endOfflineRender() {
        context.endOfflineRender()
    }

    // MARK: FBO Feedback

    /// Enables framebuffer feedback, giving access to the previous frame.
    public func enableFeedback() {
        context.enableFeedback()
    }

    /// Disables framebuffer feedback.
    public func disableFeedback() {
        context.disableFeedback()
    }

    /// Returns the rendering result of the previous frame.
    ///
    /// - Returns: The previous frame as an ``MImage``, or `nil` when feedback is disabled.
    public func previousFrame() -> MImage? {
        context.previousFrame()
    }
}
