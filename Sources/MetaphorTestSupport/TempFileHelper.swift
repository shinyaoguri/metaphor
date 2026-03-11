import Foundation

/// Scope-based temporary file and directory management for tests.
///
/// Automatically cleans up created files/directories when the closure returns.
///
/// ```swift
/// try TempFileHelper.withTemporaryFile(extension: "mp4") { url in
///     // use url...
/// }
/// // file is automatically deleted
/// ```
public struct TempFileHelper: Sendable {

    /// Execute a closure with a temporary directory that is automatically removed afterward.
    public static func withTemporaryDirectory<T>(
        prefix: String = "metaphor_test_",
        body: (URL) throws -> T
    ) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + ProcessInfo.processInfo.globallyUniqueString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Execute a closure with a temporary file path that is automatically removed afterward.
    public static func withTemporaryFile<T>(
        extension ext: String,
        body: (URL) throws -> T
    ) rethrows -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor_test_\(ProcessInfo.processInfo.globallyUniqueString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    /// Execute an async closure with a temporary file path that is automatically removed afterward.
    public static func withTemporaryFile<T>(
        extension ext: String,
        body: (URL) async throws -> T
    ) async rethrows -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor_test_\(ProcessInfo.processInfo.globallyUniqueString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }
}
