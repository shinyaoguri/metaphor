import Metal
import Foundation
import os

/// Metal シェーダーのコンパイルとキャッシュを管理します。
///
/// `ShaderLibrary` はプリコンパイル済み `.metallib` バンドルを優先的に読み込みます。
/// 利用できない場合は、ランタイムで MSL ソース文字列をコンパイルするフォールバックを行います。
/// カスタムシェーダーはホットリロードワークフロー向けに動的に登録できます。
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

    /// プリコンパイル済み `.metallib` バンドルから読み込まれたかどうか
    public private(set) var usesPrecompiledMetalLib = false

    /// `true` の場合、`.metallib` の代わりに MSL ソース文字列からのコンパイルを強制します。
    ///
    /// シェーダーホットリロードワークフローの開発中に有効化してください。
    public var preferSourceCompilation = false

    // MARK: - 組み込みライブラリキー

    /// 組み込みシェーダーライブラリの識別子
    public enum BuiltinKey {
        /// オフスクリーンテクスチャを画面にコンポジットするブリットシェーダー
        public static let blit = "metaphor.blit"
        /// フラットカラーシェーダー（ライティングなし）
        public static let flatColor = "metaphor.flatColor"
        /// 頂点カラーシェーダー
        public static let vertexColor = "metaphor.vertexColor"
        /// Blinn-Phong / PBR ライティング付きシェーダー
        public static let lit = "metaphor.lit"
        /// 2D キャンバスシェーダー
        public static let canvas2D = "metaphor.canvas2D"
        /// 3D キャンバスシェーダー
        public static let canvas3D = "metaphor.canvas3D"
        /// 2D キャンバステクスチャ付きシェーダー
        public static let canvas2DTextured = "metaphor.canvas2DTextured"
        /// 3D キャンバステクスチャ付きシェーダー
        public static let canvas3DTextured = "metaphor.canvas3DTextured"
        /// ポストプロセスエフェクトシェーダー
        public static let postProcess = "metaphor.postProcess"
        /// GPU 画像フィルターシェーダー
        public static let imageFilter = "metaphor.imageFilter"
        /// Kawase ブラーシェーダー
        public static let kawaseBlur = "metaphor.kawaseBlur"
        /// GPU パーティクルシステムシェーダー
        public static let particle = "metaphor.particle"
        /// レンダーグラフマージシェーダー
        public static let merge = "metaphor.merge"
        /// 3D インスタンスレンダリングシェーダー
        public static let canvas3DInstanced = "metaphor.canvas3DInstanced"
        /// 2D インスタンスレンダリングシェーダー
        public static let canvas2DInstanced = "metaphor.canvas2DInstanced"

        /// 全組み込みライブラリキー
        static let all: [String] = [
            blit, flatColor, vertexColor, lit,
            canvas2D, canvas3D, canvas2DTextured, canvas3DTextured,
            postProcess, imageFilter, kawaseBlur, particle, merge,
            canvas3DInstanced, canvas2DInstanced,
        ]
    }

    // MARK: - 初期化

    /// シェーダーライブラリを作成し、全組み込みシェーダーを読み込みます。
    ///
    /// まずプリコンパイル済み `.metallib` バンドルからの読み込みを試みます。
    /// バンドルが利用できない場合は MSL ソース文字列のコンパイルにフォールバックします。
    ///
    /// - Parameter device: シェーダーコンパイルに使用する Metal デバイス
    /// - Throws: コンパイルに失敗した場合 ``MetaphorError/shaderCompilationFailed(name:underlying:)``
    public init(device: MTLDevice) throws {
        self.device = device
        try loadBuiltins()
    }

    // MARK: - 登録

    /// MSL ソース文字列をコンパイルし、指定されたキーで登録します。
    ///
    /// - Parameters:
    ///   - source: コンパイルする MSL ソースコード
    ///   - key: コンパイル済みライブラリを登録する識別子
    /// - Throws: MSL ソースのコンパイルに失敗した場合のエラー
    public func register(source: String, as key: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        libraries[key] = library
    }

    /// プリコンパイル済み Metal ライブラリを指定されたキーで登録します。
    ///
    /// - Parameters:
    ///   - library: プリコンパイル済み `MTLLibrary`
    ///   - key: ライブラリを登録する識別子
    public func register(library: MTLLibrary, as key: String) {
        libraries[key] = library
    }

    // MARK: - 関数アクセス

    /// 指定されたライブラリからコンパイル済み Metal 関数を取得します。
    ///
    /// 結果は以降のルックアップ用にキャッシュされます。
    ///
    /// - Parameters:
    ///   - name: Metal シェーダーソース内の関数名
    ///   - key: ルックアップするライブラリキー
    /// - Returns: コンパイル済み `MTLFunction`。見つからない場合は `nil`
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

    /// 現在登録されている全ライブラリのキー
    public var registeredKeys: [String] {
        Array(libraries.keys)
    }

    /// 指定されたキーにライブラリが登録されているかどうかを返します。
    ///
    /// - Parameter key: 確認するライブラリキー
    /// - Returns: キーにライブラリが存在する場合 `true`
    public func hasLibrary(for key: String) -> Bool {
        libraries[key] != nil
    }

    // MARK: - ホットリロード

    /// ディスクから MSL ソースファイルを読み込み、登録します。
    ///
    /// - Parameters:
    ///   - path: `.metal` ソースファイルのファイルパス
    ///   - key: コンパイル済みライブラリを登録する識別子
    /// - Throws: ファイルの読み込みまたはソースのコンパイルに失敗した場合のエラー
    public func registerFromFile(path: String, as key: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try register(source: source, as: key)
    }

    /// MSL ソースから再コンパイルして既存ライブラリを置換し、シェーダーをリロードします。
    ///
    /// 再コンパイル前に指定キーのキャッシュ済み関数をクリアします。
    ///
    /// - Parameters:
    ///   - key: リロードするライブラリキー
    ///   - source: コンパイルする MSL ソースコード
    /// - Throws: MSL ソースのコンパイルに失敗した場合のエラー
    public func reload(key: String, source: String) throws {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
        libraries.removeValue(forKey: key)
        try register(source: source, as: key)
    }

    /// ディスク上のファイルからシェーダーをリロードし、既存ライブラリを置換します。
    ///
    /// - Parameters:
    ///   - key: リロードするライブラリキー
    ///   - path: `.metal` ソースファイルのファイルパス
    /// - Throws: ファイルの読み込みまたはソースのコンパイルに失敗した場合のエラー
    public func reloadFromFile(key: String, path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try reload(key: key, source: source)
    }

    /// ライブラリ自体を削除せずに、指定ライブラリキーのキャッシュ済み関数をクリアします。
    ///
    /// ライブラリが外部で更新されたことがわかっており、次回アクセス時に
    /// 関数の再ルックアップを強制したい場合に呼び出してください。
    ///
    /// - Parameter key: 関数キャッシュをクリアするライブラリキー
    public func invalidateFunctionCache(for key: String) {
        functions = functions.filter { !$0.key.hasPrefix("\(key).") }
    }

    // MARK: - リソース読み込み

    /// バンドルされた .txt リソースファイルから MSL ソース文字列を読み込みます。
    ///
    /// - Parameter name: シェーダーソース名（拡張子なし）
    /// - Returns: MSL ソース文字列。リソースが見つからない場合は `nil`
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
        // preferSourceCompilation が true の場合、常にソースからコンパイル
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

    /// リソースファイル名から組み込みキーへのマッピング
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

        // 並列コンパイル（device.makeLibrary はスレッドセーフ）
        let results = UnsafeMutablePointer<(key: String, lib: MTLLibrary)?>.allocate(capacity: sources.count)
        results.initialize(repeating: nil, count: sources.count)
        defer {
            results.deinitialize(count: sources.count)
            results.deallocate()
        }

        // unsafeResults: 各スレッドが自身のインデックスに書き込み（ロック不要）
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

        // オール・オア・ナッシング: いずれかのシェーダーが失敗した場合、全て登録しない
        let errors = compilationErrors.withLock { $0 }
        if !errors.isEmpty {
            let detail = errors.map { "  \($0.key): \($0.error)" }.joined(separator: "\n")
            throw MetaphorError.shaderCompilationFailed(
                name: "builtins (\(errors.count) failed)",
                underlying: SimpleError(message: "Failed to compile \(errors.count) shader(s):\n\(detail)")
            )
        }

        for i in 0..<sources.count {
            if let result = results[i] {
                libraries[result.key] = result.lib
            }
        }
    }
}
