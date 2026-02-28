import Metal

/// Metalシェーダーのコンパイルとキャッシュを管理するライブラリ
///
/// MSLソース文字列からMTLLibrary/MTLFunctionをコンパイルし、
/// 同じソースの再コンパイルを避けるためにキャッシュする。
/// metaphorの組み込みシェーダーは自動的に登録される。
@MainActor
public final class ShaderLibrary {
    private let device: MTLDevice
    private var libraries: [String: MTLLibrary] = [:]
    private var functions: [String: MTLFunction] = [:]

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
    }

    // MARK: - Initialization

    /// 初期化。組み込みシェーダーを自動的に登録する。
    /// - Parameter device: MTLDevice
    public init(device: MTLDevice) throws {
        self.device = device
        try registerBuiltins()
    }

    // MARK: - Registration

    /// MSLソース文字列をコンパイルして登録
    /// - Parameters:
    ///   - source: MSLソースコード
    ///   - key: ライブラリの識別キー
    /// - Throws: シェーダーコンパイルエラー
    public func register(source: String, as key: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        libraries[key] = library
    }

    /// 事前コンパイル済みMTLLibraryを登録
    /// - Parameters:
    ///   - library: MTLLibrary
    ///   - key: ライブラリの識別キー
    public func register(library: MTLLibrary, as key: String) {
        libraries[key] = library
    }

    // MARK: - Function Access

    /// 指定したライブラリから関数を取得
    /// - Parameters:
    ///   - name: 関数名
    ///   - key: ライブラリの識別キー
    /// - Returns: MTLFunction（見つからない場合はnil）
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

    // MARK: - Private

    private func registerBuiltins() throws {
        try register(source: BuiltinShaders.blitSource, as: BuiltinKey.blit)
        try register(source: BuiltinShaders.flatColorSource, as: BuiltinKey.flatColor)
        try register(source: BuiltinShaders.vertexColorSource, as: BuiltinKey.vertexColor)
        try register(source: BuiltinShaders.litSource, as: BuiltinKey.lit)
        try register(source: BuiltinShaders.canvas2DSource, as: BuiltinKey.canvas2D)
        try register(source: BuiltinShaders.canvas3DSource, as: BuiltinKey.canvas3D)
        try register(source: BuiltinShaders.canvas2DTexturedSource, as: BuiltinKey.canvas2DTextured)
        try register(source: BuiltinShaders.canvas3DTexturedSource, as: BuiltinKey.canvas3DTextured)
    }
}
