import MetaphorCore
import MetaphorVideo

// MARK: - ビデオ再生ブリッジ

extension Sketch {
    /// Loads a video file for playback.
    ///
    /// - Parameter path: The file path of the video file.
    /// - Returns: A new ``MetaphorVideo/VideoPlayer`` instance.
    /// - Throws: An error when the file does not exist.
    public func loadVideo(_ path: String) throws -> VideoPlayer {
        try VideoPlayer(path: path, device: context.renderer.device)
    }

    /// Draws the video player's current frame at the given position.
    ///
    /// - Parameters:
    ///   - video: The video player to draw from.
    ///   - x: The x coordinate to draw at.
    ///   - y: The y coordinate to draw at.
    public func image(_ video: VideoPlayer, _ x: Float, _ y: Float) {
        guard let tex = video.texture else { return }
        let img = MImage(texture: tex)
        context.canvas.image(img, x, y)
    }

    /// Draws the video player's current frame at the given position and size.
    ///
    /// - Parameters:
    ///   - video: The video player to draw from.
    ///   - x: The x coordinate to draw at.
    ///   - y: The y coordinate to draw at.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ video: VideoPlayer, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        guard let tex = video.texture else { return }
        let img = MImage(texture: tex)
        context.canvas.image(img, x, y, w, h)
    }
}
