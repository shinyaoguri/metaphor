import Metal
import Foundation
import os

/// Manages compilation and caching of Metal shaders.
///
/// `ShaderLibrary` preferentially loads pre-compiled `.metallib` bundles.
/// When unavailable, it falls back to compiling MSL source strings at runtime.
/// Custom shaders can be registered dynamically for hot-reload workflows.
///
/// ```swift
/// let shaders = try ShaderLibrary(device: device)
/// try shaders.register(source: myMSLCode, as: "myEffect")
/// let function = shaders.function(named: "fragment_myEffect", from: "myEffect")
/// ```
@MainActor
public final class ShaderLibrary {
    private let device: MTLDevice
    private var libraries: [String: MTLLibrary] = [:]
    private var functions: [String: MTLFunction] = [:]

    /// Whether the library was loaded from a pre-compiled `.metallib` bundle.
    public private(set) var usesPrecompiledMetalLib = false

    /// When `true`, forces compilation from MSL source strings instead of using `.metallib`.
    ///
    /// Enable this during development for shader hot-reload workflows.
    public var preferSourceCompilation = false

    // MARK: - Built-in Library Keys

    /// Identifiers for built-in shader libraries.
    public enum BuiltinKey {
        /// Blit shader for compositing offscreen texture to screen.
        public static let blit = "metaphor.blit"
        /// Flat color shader (no lighting).
        public static let flatColor = "metaphor.flatColor"
        /// Per-vertex color shader.
        public static let vertexColor = "metaphor.vertexColor"
        /// Lit shader with Blinn-Phong / PBR lighting.
        public static let lit = "metaphor.lit"
        /// 2D canvas shader.
        public static let canvas2D = "metaphor.canvas2D"
        /// 3D canvas shader.
        public static let canvas3D = "metaphor.canvas3D"
        /// 2D canvas textured shader.
        public static let canvas2DTextured = "metaphor.canvas2DTextured"
        /// 3D canvas textured shader.
        public static let canvas3DTextured = "metaphor.canvas3DTextured"
        /// Post-processing effect shaders.
        public static let postProcess = "metaphor.postProcess"
        /// GPU image filter shaders.
        public static let imageFilter = "metaphor.imageFilter"
        /// Kawase blur shaders.
        public static let kawaseBlur = "metaphor.kawaseBlur"
        /// GPU particle system shaders.
        public static let particle = "metaphor.particle"
        /// Render graph merge shaders.
        public static let merge = "metaphor.merge"
        /// 3D instanced rendering shaders.
        public static let canvas3DInstanced = "metaphor.canvas3DInstanced"
        /// 2D instanced rendering shaders.
        public static let canvas2DInstanced = "metaphor.canvas2DInstanced"

        /// All built-in library keys.
        static let all: [String] = [
            blit, flatColor, vertexColor, lit,
            canvas2D, canvas3D, canvas2DTextured, canvas3DTextured,
            postProcess, imageFilter, kawaseBlur, particle, merge,
            canvas3DInstanced, canvas2DInstanced,
        ]
    }

    // MARK: - Initialization

    /// Creates a shader library and loads all built-in shaders.
    ///
    /// Attempts to load from a pre-compiled `.metallib` bundle first.
    /// Falls back to compiling MSL source strings if the bundle is unavailable.
    ///
    /// - Parameter device: The Metal device to use for shader compilation.
    /// - Throws: ``MetaphorError/shaderCompilationFailed(name:underlying:)`` if compilation fails.
    public init(device: MTLDevice) throws {
        self.device = device
        try loadBuiltins()
    }

    // MARK: - Registration

    /// Compiles an MSL source string and registers it under the given key.
    ///
    /// - Parameters:
    ///   - source: The MSL source code to compile.
    ///   - key: The identifier to register the compiled library under.
    /// - Throws: An error if the MSL source fails to compile.
    public func register(source: String, as key: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        libraries[key] = library
    }

    /// Registers a pre-compiled Metal library under the given key.
    ///
    /// - Parameters:
    ///   - library: The pre-compiled `MTLLibrary`.
    ///   - key: The identifier to register the library under.
    public func register(library: MTLLibrary, as key: String) {
        libraries[key] = library
    }

    // MARK: - Function Access

    /// Retrieves a compiled Metal function from the specified library.
    ///
    /// Results are cached for subsequent lookups.
    ///
    /// - Parameters:
    ///   - name: The function name in the Metal shader source.
    ///   - key: The library key to look up.
    /// - Returns: The compiled `MTLFunction`, or `nil` if not found.
    public func function(named name: String, from key: String) -> MTLFunction? {
        let cacheKey = "\(key).\(name)"
        if let cached = functions[cacheKey] {
            return cached
        }

        guard let library = libraries[key],
              let function = library.makeFunction(name: name) else {
            return nil
        }

        functions[cacheKey] = function
        return function
    }

    /// The keys of all currently registered libraries.
    public var registeredKeys: [String] {
        Array(libraries.keys)
    }

    /// Returns whether a library is registered under the given key.
    ///
    /// - Parameter key: The library key to check.
    /// - Returns: `true` if a library exists for the key.
    public func hasLibrary(for key: String) -> Bool {
        libraries[key] != nil
    }

    // MARK: - Hot Reload

    /// Loads and registers an MSL source file from disk.
    ///
    /// - Parameters:
    ///   - path: The file path to the `.metal` source file.
    ///   - key: The identifier to register the compiled library under.
    /// - Throws: An error if the file cannot be read or the source fails to compile.
    public func registerFromFile(path: String, as key: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try register(source: source, as: key)
    }

    /// Reloads a shader by recompiling from MSL source and replacing the existing library.
    ///
    /// Clears cached functions for the specified key before recompiling.
    ///
    /// - Parameters:
    ///   - key: The library key to reload.
    ///   - source: The MSL source code to compile.
    /// - Throws: An error if the MSL source fails to compile.
    public func reload(key: String, source: String) throws {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
        libraries.removeValue(forKey: key)
        try register(source: source, as: key)
    }

    /// Reloads a shader from a file on disk, replacing the existing library.
    ///
    /// - Parameters:
    ///   - key: The library key to reload.
    ///   - path: The file path to the `.metal` source file.
    /// - Throws: An error if the file cannot be read or the source fails to compile.
    public func reloadFromFile(key: String, path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try reload(key: key, source: source)
    }

    /// Clears cached functions for the specified library key without removing the library itself.
    ///
    /// Call this when you know the library has been updated externally and want to
    /// force function re-lookup on the next access.
    ///
    /// - Parameter key: The library key whose function cache should be cleared.
    public func invalidateFunctionCache(for key: String) {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
    }

    // MARK: - Resource Loading

    /// Loads an MSL source string from a bundled .txt resource file.
    ///
    /// - Parameter name: The shader source name (without extension).
    /// - Returns: The MSL source string, or `nil` if the resource is not found.
    public nonisolated static func loadShaderSource(_ name: String) -> String? {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "ShaderSources"
        ) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Private

    private func loadBuiltins() throws {
        // If preferSourceCompilation is true, always compile from source
        if !preferSourceCompilation,
           let metallib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            for key in BuiltinKey.all {
                libraries[key] = metallib
            }
            usesPrecompiledMetalLib = true
            return
        }

        // Fallback: compile from MSL source strings
        try registerBuiltinsFromSource()
    }

    /// Mapping from resource file names to builtin keys.
    private static let shaderResourceNames: [(resource: String, key: String)] = [
        ("blit", BuiltinKey.blit),
        ("flatColor", BuiltinKey.flatColor),
        ("vertexColor", BuiltinKey.vertexColor),
        ("lit", BuiltinKey.lit),
        ("canvas2D", BuiltinKey.canvas2D),
        ("canvas3D", BuiltinKey.canvas3D),
        ("canvas2DTextured", BuiltinKey.canvas2DTextured),
        ("canvas3DTextured", BuiltinKey.canvas3DTextured),
        ("postProcess", BuiltinKey.postProcess),
        ("imageFilter", BuiltinKey.imageFilter),
        ("kawaseBlur", BuiltinKey.kawaseBlur),
        ("particle", BuiltinKey.particle),
        ("merge", BuiltinKey.merge),
        ("canvas3DInstanced", BuiltinKey.canvas3DInstanced),
        ("canvas2DInstanced", BuiltinKey.canvas2DInstanced),
    ]

    private func registerBuiltinsFromSource() throws {
        let sources: [(source: String, key: String)] = Self.shaderResourceNames.compactMap { entry in
            guard let source = Self.loadShaderSource(entry.resource) else {
                return nil
            }
            return (source, entry.key)
        }

        // Parallel compilation (device.makeLibrary is thread-safe)
        let results = UnsafeMutablePointer<(key: String, lib: MTLLibrary)?>.allocate(capacity: sources.count)
        results.initialize(repeating: nil, count: sources.count)
        defer { results.deallocate() }

        // unsafeResults: each thread writes to its own index (no lock needed).
        nonisolated(unsafe) let unsafeResults = results
        let compilationErrors = OSAllocatedUnfairLock(initialState: [(key: String, error: Error)]())
        let dev = device

        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            let (source, key) = sources[index]
            do {
                let lib = try dev.makeLibrary(source: source, options: nil)
                unsafeResults[index] = (key, lib)
            } catch {
                compilationErrors.withLock { $0.append((key: key, error: error)) }
            }
        }

        // All-or-nothing: if any shader failed, register none
        let errors = compilationErrors.withLock { $0 }
        if !errors.isEmpty {
            let detail = errors.map { "  \($0.key): \($0.error)" }.joined(separator: "\n")
            throw MetaphorError.shaderCompilationFailed(
                name: "builtins (\(errors.count) failed)",
                underlying: NSError(
                    domain: "metaphor.ShaderLibrary",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to compile \(errors.count) shader(s):\n\(detail)"]
                )
            )
        }

        for i in 0..<sources.count {
            if let result = results[i] {
                libraries[result.key] = result.lib
            }
        }
    }
}
