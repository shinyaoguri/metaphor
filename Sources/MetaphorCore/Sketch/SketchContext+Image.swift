import AppKit

extension SketchContext {

    // MARK: - Image

    /// Loads an image from the specified file path.
    /// - Parameter path: The file path to the image.
    /// - Returns: The loaded image.
    public func loadImage(_ path: String) throws -> MImage {
        try MImage(path: path, device: renderer.device)
    }

    /// Creates an empty image for pixel manipulation.
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    /// - Returns: A new blank image, or nil on failure.
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        MImage.createImage(width, height, device: renderer.device)
    }

    /// Applies a GPU image filter to an image.
    /// - Parameters:
    ///   - image: The target image.
    ///   - type: The filter type to apply.
    public func filter(_ image: MImage, _ type: FilterType) {
        renderer.imageFilterGPU.apply(type, to: image)
    }

    /// Creates an offscreen 2D drawing buffer.
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new Graphics instance, or nil on failure.
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        try? Graphics(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    /// Creates an offscreen 3D drawing buffer.
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new Graphics3D instance, or nil on failure.
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        try? Graphics3D(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    // MARK: - Camera Capture

    /// Creates a camera capture device and starts capturing automatically.
    /// - Parameters:
    ///   - width: The capture width in pixels (default 1280).
    ///   - height: The capture height in pixels (default 720).
    ///   - position: The camera position (default `.front`).
    /// - Returns: A started `CaptureDevice` instance.
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, position: position)
        capture.start()
        return capture
    }

    /// Draws the latest frame from a capture device at the given position.
    /// - Parameters:
    ///   - capture: The capture device.
    ///   - x: The x-coordinate of the top-left corner.
    ///   - y: The y-coordinate of the top-left corner.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y)
        }
    }

    /// Draws the latest frame from a capture device with explicit size.
    /// - Parameters:
    ///   - capture: The capture device.
    ///   - x: The x-coordinate of the top-left corner.
    ///   - y: The y-coordinate of the top-left corner.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y, w, h)
        }
    }

    /// Draws an image at the specified position.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        canvas.image(img, x, y)
    }

    /// Draws a Graphics buffer at the specified position.
    /// - Parameters:
    ///   - pg: The offscreen graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Draws a Graphics buffer with explicit size.
    /// - Parameters:
    ///   - pg: The offscreen graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Draws a Graphics3D buffer at the specified position.
    /// - Parameters:
    ///   - pg: The offscreen 3D graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Draws a Graphics3D buffer with explicit size.
    /// - Parameters:
    ///   - pg: The offscreen 3D graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Draws an image with explicit size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
    }

    /// Draws a sub-region of an image (for sprite sheets and tile maps).
    /// - Parameters:
    ///   - img: The source image.
    ///   - dx: The destination x-coordinate.
    ///   - dy: The destination y-coordinate.
    ///   - dw: The destination width.
    ///   - dh: The destination height.
    ///   - sx: The source x-coordinate.
    ///   - sy: The source y-coordinate.
    ///   - sw: The source width.
    ///   - sh: The source height.
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        canvas.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: - Text

    /// Sets the text rendering size.
    /// - Parameter size: The font size in points.
    public func textSize(_ size: Float) {
        canvas.textSize(size)
    }

    /// Sets the font family for text rendering.
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) {
        canvas.textFont(family)
    }

    /// Sets the text alignment.
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment (default `.baseline`).
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// Sets the line spacing for multi-line text.
    /// - Parameter leading: The line height in pixels.
    public func textLeading(_ leading: Float) {
        canvas.textLeading(leading)
    }

    /// Calculates the rendered width of a string.
    /// - Parameter string: The text to measure.
    /// - Returns: The width in pixels.
    public func textWidth(_ string: String) -> Float {
        canvas.textWidth(string)
    }

    /// Returns the font ascent for the current text settings.
    /// - Returns: The ascent value in pixels.
    public func textAscent() -> Float {
        canvas.textAscent()
    }

    /// Returns the font descent for the current text settings.
    /// - Returns: The descent value in pixels.
    public func textDescent() -> Float {
        canvas.textDescent()
    }

    /// Draws text at the specified position.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        canvas.text(string, x, y)
    }

    /// Draws text within a bounding box with automatic word wrapping.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate of the box.
    ///   - y: The y-coordinate of the box.
    ///   - w: The box width.
    ///   - h: The box height.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.text(string, x, y, w, h)
    }

    // MARK: - Screenshot

    /// Saves a screenshot to the specified file path.
    /// - Parameter path: The output file path.
    public func save(_ path: String) {
        renderer.saveScreenshot(to: path)
    }

    /// Begins sequential frame export.
    /// - Parameters:
    ///   - directory: The output directory (nil creates one on the Desktop automatically).
    ///   - pattern: The filename pattern with a frame number placeholder.
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        let dir: String
        if let directory {
            dir = directory
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            dir = NSHomeDirectory() + "/Desktop/metaphor_frames_\(formatter.string(from: Date()))"
        }
        renderer.frameExporter.beginSequence(directory: dir, pattern: pattern)
    }

    /// Stops sequential frame export.
    public func endRecord() {
        renderer.frameExporter.endSequence()
    }

    /// Begins video recording.
    /// - Parameters:
    ///   - path: The output file path (nil generates one on the Desktop automatically).
    ///   - config: The video export configuration.
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).\(config.format.fileExtension)"
        }
        try? renderer.videoExporter.beginRecord(
            path: actualPath,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height,
            config: config
        )
    }

    /// Ends video recording.
    /// - Parameter completion: A callback invoked when writing finishes.
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        renderer.videoExporter.endRecord(completion: completion)
    }

    /// Ends video recording asynchronously.
    public func endVideoRecord() async {
        await renderer.videoExporter.endRecord()
    }

    /// Saves the current frame as a single image file (Processing-compatible).
    /// - Parameter filename: The output filename (nil auto-generates a numbered name).
    public func saveFrame(_ filename: String? = nil) {
        let name: String
        if let filename {
            name = filename
        } else {
            name = "screen-\(String(format: "%04d", frameCount)).png"
        }
        let path = NSHomeDirectory() + "/Desktop/" + name
        renderer.saveScreenshot(to: path)
    }

    /// Saves a timestamped screenshot to the Desktop.
    public func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "metaphor_\(formatter.string(from: Date())).png"
        let path = NSHomeDirectory() + "/Desktop/" + name
        save(path)
    }

    // MARK: - Offline Rendering

    /// Indicates whether offline rendering mode is active.
    public var isOfflineRendering: Bool {
        renderer.isOfflineRendering
    }

    /// Begins offline rendering mode.
    ///
    /// Elapsed time becomes deterministic, enabling high-quality video rendering
    /// without frame drops.
    /// - Parameter fps: The target frame rate (default 60).
    public func beginOfflineRender(fps: Double = 60) {
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = fps
        renderer.resetOfflineRendering()
    }

    /// Ends offline rendering mode.
    public func endOfflineRender() {
        renderer.isOfflineRendering = false
    }

    // MARK: - FBO Feedback

    /// Enables frame buffer feedback.
    ///
    /// When enabled, the previous frame's color texture is copied at the start
    /// of each frame and can be retrieved as an `MImage` via ``previousFrame()``.
    public func enableFeedback() {
        renderer.feedbackEnabled = true
    }

    /// Disables frame buffer feedback.
    public func disableFeedback() {
        renderer.feedbackEnabled = false
    }

    /// Returns the previous frame's rendering result as an image.
    ///
    /// Call ``enableFeedback()`` before using this method. Returns nil when
    /// feedback is disabled or on the very first frame.
    /// - Returns: The previous frame as an `MImage`, or nil.
    public func previousFrame() -> MImage? {
        guard let tex = renderer.previousFrameTexture else { return nil }
        return MImage(texture: tex)
    }
}
