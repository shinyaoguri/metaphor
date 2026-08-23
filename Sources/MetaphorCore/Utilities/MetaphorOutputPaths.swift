import Foundation

/// Resolves the **destination** for the files a sketch writes out (screenshots, frame
/// sequences, video, and GIF) (Issue #757).
///
/// Previously the given name was unconditionally prefixed with `~/Desktop/`. Besides
/// leaving no way to choose the destination, passing an absolute path dropped the file
/// somewhere else entirely, such as `~/Desktop/tmp/shots/a.png`, and because the parent
/// directory was created along the way **the failure went unnoticed**.
///
/// There are three rules.
///
/// - **The default** (when the argument is omitted) is `output/` inside the project
/// - **A relative path** is relative to the project root (the equivalent of Processing's sketch folder)
/// - **An absolute path**, or one starting with `~`, is used as is
///
/// The project here (the base directory) is ``MetaphorPaths/baseDirectory``:
/// `METAPHOR_STATE_DIR` when it is set, otherwise the process's cwd (the package root for
/// `swift build && swift run`, or the project handed to the child process of
/// `metaphor run` / `watch`).
enum MetaphorOutputPaths {
    /// The default output directory name.
    static let directoryName = "output"

    /// The default output directory (`<base>/output`).
    static func defaultDirectory(base: String = MetaphorPaths.baseDirectory) -> String {
        MetaphorPaths.resolve(directoryName, base: base)
    }

    /// The destination for ``SketchContext/saveFrame(_:)``.
    ///
    /// - Parameters:
    ///   - filename: The path the caller specified (`output/screen-<frameCount>.png` when `nil`).
    ///   - frameCount: The frame number used in the default name (zero-padded to four digits).
    static func screenshot(
        filename: String?, frameCount: Int, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let filename else {
            let name = "screen-\(String(format: "%04d", frameCount)).png"
            return MetaphorPaths.resolve(name, base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(filename, base: base)
    }

    /// The destination for ``SketchContext/save()`` (`output/metaphor_<timestamp>.png`).
    static func timestampedScreenshot(
        timestamp: String, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        MetaphorPaths.resolve("metaphor_\(timestamp).png", base: defaultDirectory(base: base))
    }

    /// The output directory for ``SketchContext/beginFrameRecord(directory:pattern:)``.
    static func frameSequenceDirectory(
        _ directory: String?, timestamp: String, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let directory else {
            return MetaphorPaths.resolve(
                "metaphor_frames_\(timestamp)", base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(directory, base: base)
    }

    /// The destination for video / GIF export (`output/metaphor_<timestamp>.<fileExtension>`).
    static func recording(
        _ path: String?, fileExtension: String, timestamp: String,
        base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let path else {
            return MetaphorPaths.resolve(
                "metaphor_\(timestamp).\(fileExtension)", base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(path, base: base)
    }

    /// The timestamp used in default file names (`yyyyMMdd_HHmmss`).
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
