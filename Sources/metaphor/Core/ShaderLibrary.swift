import Metal
import Foundation

/// Metalシェーダーのコンパイルとキャッシュを管理するライブラリ
///
/// 事前コンパイル済み metallib を優先的にロードし、
/// 見つからない場合は MSL ソース文字列からコンパイルする。
@MainActor
public final class ShaderLibrary {
    private let device: MTLDevice
    private var libraries: [String: MTLLibrary] = [:]
    private var functions: [String: MTLFunction] = [:]

    /// metallib からロードされたかどうか
    public private(set) var usesPrecompiledMetalLib = false

    /// true の場合、metallib より MSL ソース文字列からのコンパイルを優先する
    /// ホットリロード開発時に使用
    public var preferSourceCompilation = false

    // MARK: - Built-in Library Keys

    /// 組み込みライブラリの識別キー
    public enum BuiltinKey {
        public static let blit = "metaphor.blit"
        public static let flatColor = "metaphor.flatColor"
        public static let vertexColor = "metaphor.vertexColor"
        public static let lit = "metaphor.lit"
        public static let canvas2D = "metaphor.canvas2D"
        public static let canvas3D = "metaphor.canvas3D"
        public static let canvas2DTextured = "metaphor.canvas2DTextured"
        public static let canvas3DTextured = "metaphor.canvas3DTextured"
        public static let postProcess = "metaphor.postProcess"
        public static let imageFilter = "metaphor.imageFilter"
        public static let kawaseBlur = "metaphor.kawaseBlur"
        public static let particle = "metaphor.particle"
        public static let merge = "metaphor.merge"
        public static let canvas3DInstanced = "metaphor.canvas3DInstanced"
        public static let canvas2DInstanced = "metaphor.canvas2DInstanced"

        /// 全ビルトインキーのリスト
        static let all: [String] = [
            blit, flatColor, vertexColor, lit,
            canvas2D, canvas3D, canvas2DTextured, canvas3DTextured,
            postProcess, imageFilter, kawaseBlur, particle, merge,
            canvas3DInstanced, canvas2DInstanced,
        ]
    }

    // MARK: - Initialization

    /// 初期化。事前コンパイル済み metallib を優先ロードし、
    /// なければ MSL ソース文字列からコンパイルする。
    /// - Parameter device: MTLDevice
    public init(device: MTLDevice) throws {
        self.device = device
        try loadBuiltins()
    }

    // MARK: - Registration

    /// MSLソース文字列をコンパイルして登録
    public func register(source: String, as key: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        libraries[key] = library
    }

    /// 事前コンパイル済みMTLLibraryを登録
    public func register(library: MTLLibrary, as key: String) {
        libraries[key] = library
    }

    // MARK: - Function Access

    /// 指定したライブラリから関数を取得
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

    /// 登録済みライブラリのキー一覧
    public var registeredKeys: [String] {
        Array(libraries.keys)
    }

    /// 指定したキーのライブラリが登録済みかどうか
    public func hasLibrary(for key: String) -> Bool {
        libraries[key] != nil
    }

    // MARK: - Hot Reload

    /// 外部ファイルからMSLソースを読み込んで登録
    public func registerFromFile(path: String, as key: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try register(source: source, as: key)
    }

    /// 指定キーのライブラリとキャッシュ済み関数を破棄し、再登録する
    public func reload(key: String, source: String) throws {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
        libraries.removeValue(forKey: key)
        try register(source: source, as: key)
    }

    /// 外部ファイルからMSLソースを再読み込みして再登録
    public func reloadFromFile(key: String, path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try reload(key: key, source: source)
    }

    /// 指定キーの関数キャッシュのみをクリア（ライブラリは保持）
    public func invalidateFunctionCache(for key: String) {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
    }

    // MARK: - Private

    private func loadBuiltins() throws {
        // preferSourceCompilation が true の場合は常にソースからコンパイル
        if !preferSourceCompilation,
           let metallib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            for key in BuiltinKey.all {
                libraries[key] = metallib
            }
            usesPrecompiledMetalLib = true
            return
        }

        // フォールバック: MSL ソース文字列からコンパイル
        try registerBuiltinsFromSource()
    }

    private func registerBuiltinsFromSource() throws {
        try register(source: BuiltinShaders.blitSource, as: BuiltinKey.blit)
        try register(source: BuiltinShaders.flatColorSource, as: BuiltinKey.flatColor)
        try register(source: BuiltinShaders.vertexColorSource, as: BuiltinKey.vertexColor)
        try register(source: BuiltinShaders.litSource, as: BuiltinKey.lit)
        try register(source: BuiltinShaders.canvas2DSource, as: BuiltinKey.canvas2D)
        try register(source: BuiltinShaders.canvas3DSource, as: BuiltinKey.canvas3D)
        try register(source: BuiltinShaders.canvas2DTexturedSource, as: BuiltinKey.canvas2DTextured)
        try register(source: BuiltinShaders.canvas3DTexturedSource, as: BuiltinKey.canvas3DTextured)
        try register(source: PostProcessShaders.source, as: BuiltinKey.postProcess)
        try register(source: ImageFilterShaders.source, as: BuiltinKey.imageFilter)
        try register(source: KawaseBlurShaders.source, as: BuiltinKey.kawaseBlur)
        try register(source: ParticleShaders.source, as: BuiltinKey.particle)
        try register(source: MergeShaders.source, as: BuiltinKey.merge)
        try register(source: Canvas3DInstancedShaders.source, as: BuiltinKey.canvas3DInstanced)
        try register(source: Canvas2DInstancedShaders.source, as: BuiltinKey.canvas2DInstanced)
    }
}
