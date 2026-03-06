// MARK: - Image, Text, Recording, Feedback

extension Sketch {

    // MARK: Image

    /// Load an image from the specified file path.
    ///
    /// - Parameter path: The file path to the image.
    /// - Returns: The loaded image.
    public func loadImage(_ path: String) throws -> MImage {
        try context.loadImage(path)
    }

    /// Load an image asynchronously (file I/O off the main thread).
    ///
    /// - Parameter path: The file path to the image.
    /// - Returns: The loaded image.
    public func loadImageAsync(_ path: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(path: path)
    }

    /// Load a named image resource asynchronously.
    ///
    /// - Parameter name: The name of the image resource.
    /// - Returns: The loaded image.
    public func loadImageAsync(named name: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(named: name)
    }

    /// Create a blank image with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    /// - Returns: A new blank image, or `nil` if creation fails.
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        context.createImage(width, height)
    }

    /// Create a 2D offscreen graphics buffer.
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new ``Graphics`` instance, or `nil` if creation fails.
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        context.createGraphics(w, h)
    }

    /// Create a 3D offscreen graphics buffer.
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new ``Graphics3D`` instance, or `nil` if creation fails.
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        context.createGraphics3D(w, h)
    }

    /// Create a camera capture device.
    ///
    /// - Parameters:
    ///   - width: The capture width in pixels.
    ///   - height: The capture height in pixels.
    ///   - position: The camera position (front or back).
    /// - Returns: A new ``CaptureDevice`` instance, or `nil` if creation fails.
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice? {
        context.createCapture(width: width, height: height, position: position)
    }

    /// Draw the latest frame from a capture device at the specified position.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        context.image(capture, x, y)
    }

    /// Draw the latest frame from a capture device at the specified position and size.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(capture, x, y, w, h)
    }

    /// Draw a 2D offscreen graphics buffer at the specified position.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// Draw a 2D offscreen graphics buffer at the specified position and size.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// Draw a 3D offscreen graphics buffer at the specified position.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// Draw a 3D offscreen graphics buffer at the specified position and size.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// Draw an image at the specified position.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        context.image(img, x, y)
    }

    /// Draw an image at the specified position and size.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(img, x, y, w, h)
    }

    /// Draw a sub-region of an image (for sprite sheets and tile maps).
    ///
    /// - Parameters:
    ///   - img: The source image.
    ///   - dx: The destination x-coordinate.
    ///   - dy: The destination y-coordinate.
    ///   - dw: The destination width.
    ///   - dh: The destination height.
    ///   - sx: The source region x-coordinate.
    ///   - sy: The source region y-coordinate.
    ///   - sw: The source region width.
    ///   - sh: The source region height.
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        context.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: Text

    /// Set the text size for subsequent text drawing.
    ///
    /// - Parameter size: The font size in points.
    public func textSize(_ size: Float) {
        context.textSize(size)
    }

    /// Set the font family for subsequent text drawing.
    ///
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) {
        context.textFont(family)
    }

    /// Set the text alignment.
    ///
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        context.textAlign(horizontal, vertical)
    }

    /// Set the line spacing for multiline text.
    ///
    /// - Parameter leading: The line height in pixels.
    public func textLeading(_ leading: Float) {
        context.textLeading(leading)
    }

    /// Draw a text string at the specified position.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        context.text(string, x, y)
    }

    /// Draw a text string within a bounding box.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate of the bounding box.
    ///   - y: The y-coordinate of the bounding box.
    ///   - w: The width of the bounding box.
    ///   - h: The height of the bounding box.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.text(string, x, y, w, h)
    }

    /// Calculate the width of a text string using the current font settings.
    ///
    /// - Parameter string: The text to measure.
    /// - Returns: The width of the text in pixels.
    public func textWidth(_ string: String) -> Float {
        context.textWidth(string)
    }

    /// Return the ascent of the current font.
    ///
    /// - Returns: The ascent value in pixels.
    public func textAscent() -> Float {
        context.textAscent()
    }

    /// Return the descent of the current font.
    ///
    /// - Returns: The descent value in pixels.
    public func textDescent() -> Float {
        context.textDescent()
    }

    // MARK: Screenshot & Recording

    /// Save the current frame to the specified file path.
    ///
    /// - Parameter path: The output file path.
    public func save(_ path: String) {
        context.save(path)
    }

    /// Save the current frame to the default location.
    public func save() {
        context.save()
    }

    /// Begin recording a sequence of frames as image files.
    ///
    /// - Parameters:
    ///   - directory: The output directory (uses a default if `nil`).
    ///   - pattern: The filename pattern with a frame number placeholder.
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        context.beginRecord(directory: directory, pattern: pattern)
    }

    /// Stop recording the frame sequence.
    public func endRecord() {
        context.endRecord()
    }

    /// Save a single frame to an image file.
    ///
    /// - Parameter filename: The output filename (auto-generated if `nil`).
    public func saveFrame(_ filename: String? = nil) {
        context.saveFrame(filename)
    }

    // MARK: Video Recording

    /// Begin recording video output.
    ///
    /// - Parameters:
    ///   - path: The output file path (auto-generated if `nil`).
    ///   - config: The video export configuration.
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        context.beginVideoRecord(path, config: config)
    }

    /// Stop recording video and finalize the file.
    ///
    /// - Parameter completion: An optional callback invoked when writing finishes.
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        context.endVideoRecord(completion: completion)
    }

    /// Stop recording video and finalize the file asynchronously.
    public func endVideoRecord() async {
        await context.endVideoRecord()
    }

    // MARK: Offline Rendering

    /// Indicate whether offline rendering mode is active.
    public var isOfflineRendering: Bool {
        context.isOfflineRendering
    }

    /// Enable offline rendering mode with deterministic timing.
    ///
    /// - Parameter fps: The virtual frame rate used for time calculation.
    public func beginOfflineRender(fps: Double = 60) {
        context.beginOfflineRender(fps: fps)
    }

    /// Disable offline rendering mode and return to real-time timing.
    public func endOfflineRender() {
        context.endOfflineRender()
    }

    // MARK: FBO Feedback

    /// Enable framebuffer feedback (previous frame access).
    public func enableFeedback() {
        context.enableFeedback()
    }

    /// Disable framebuffer feedback.
    public func disableFeedback() {
        context.disableFeedback()
    }

    /// Retrieve the previous frame's rendered image.
    ///
    /// - Returns: The previous frame as an ``MImage``, or `nil` if feedback is disabled.
    public func previousFrame() -> MImage? {
        context.previousFrame()
    }
}
