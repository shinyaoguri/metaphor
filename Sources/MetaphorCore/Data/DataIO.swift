import Foundation

/// データ IO（JSON / Table / Strings）のコア実装。
///
/// Sketch 層の ``Sketch/loadJSON(_:)`` / ``Sketch/loadTable(_:format:header:)`` /
/// ``Sketch/loadStrings(_:)`` などはここへの薄い転送です。スケッチ外
/// （テスト・バックグラウンド処理）からはこの名前空間を直接利用できます。
///
/// ソース文字列は `http://` / `https://` で始まる場合はリモート URL、
/// それ以外はファイルパス（絶対または現在ディレクトリ相対）として解決します。
public enum DataIO {

    // MARK: - ソース解決

    /// リモート URL なら URL を、ファイルパスなら nil を返します。
    static func remoteURL(_ source: String) -> URL? {
        let lowered = source.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }

    // MARK: - 低レベル読み書き

    /// ソース（ファイルパスまたは http(s) URL）からバイト列を同期で読み込みます。
    ///
    /// リモート URL の場合は応答が返るまで呼び出しスレッドをブロックします。
    /// `draw()` 内などフレームを止めたくない文脈では async 版を使ってください。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列
    /// - Throws: ``MetaphorError/data(_:)`` 読み込みに失敗した場合
    public static func readData(_ source: String) throws -> Data {
        if let url = remoteURL(source) {
            return try fetchSync(url)
        }
        let url = URL(fileURLWithPath: source)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw MetaphorError.data(.loadFailed(source: source, detail: error.localizedDescription))
        }
    }

    /// ソースからバイト列を非同期で読み込みます（ファイル I/O・通信をメインスレッド外で実行）。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列
    /// - Throws: ``MetaphorError/data(_:)`` 読み込みに失敗した場合
    public static func readDataAsync(_ source: String) async throws -> Data {
        if let url = remoteURL(source) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try validate(response: response, source: source)
                return data
            } catch let error as MetaphorError {
                throw error
            } catch {
                throw MetaphorError.data(.loadFailed(source: source, detail: error.localizedDescription))
            }
        }
        let path = source
        return try await Task.detached { try readData(path) }.value
    }

    /// バイト列をファイルへ書き込みます。親ディレクトリがなければ作成します。
    ///
    /// - Parameters:
    ///   - data: 書き込むバイト列
    ///   - path: 出力ファイルパス
    /// - Throws: ``MetaphorError/data(_:)`` 書き込みに失敗した場合
    public static func writeData(_ data: Data, toPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw MetaphorError.data(.writeFailed(path: path, detail: error.localizedDescription))
        }
    }

    private static func fetchSync(_ url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<(Data, URLResponse), Error>?
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        switch result {
        case .success(let (data, response)):
            try validate(response: response, source: url.absoluteString)
            return data
        case .failure(let error):
            throw MetaphorError.data(.loadFailed(source: url.absoluteString, detail: error.localizedDescription))
        case nil:
            throw MetaphorError.data(.loadFailed(source: url.absoluteString, detail: "no response"))
        }
    }

    private static func validate(response: URLResponse, source: String) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MetaphorError.data(.loadFailed(source: source, detail: "HTTP \(http.statusCode)"))
        }
    }

    // MARK: - Strings

    /// テキストファイル/URL を行の配列として読み込みます。
    ///
    /// 改行コード（LF/CRLF）を区切りとし、末尾改行は空行を生みません。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列
    /// - Throws: ``MetaphorError/data(_:)`` 読み込み失敗・UTF-8 でない場合
    public static func loadStrings(_ source: String) throws -> [String] {
        try splitLines(readData(source), source: source)
    }

    /// ``loadStrings(_:)`` の非同期版。
    public static func loadStringsAsync(_ source: String) async throws -> [String] {
        try splitLines(await readDataAsync(source), source: source)
    }

    /// 行の配列をテキストファイルへ書き込みます（各行に改行を付与、UTF-8）。
    ///
    /// - Parameters:
    ///   - lines: 書き込む行
    ///   - path: 出力ファイルパス
    /// - Throws: ``MetaphorError/data(_:)`` 書き込みに失敗した場合
    public static func saveStrings(_ lines: [String], toPath path: String) throws {
        let text = lines.map { $0 + "\n" }.joined()
        try writeData(Data(text.utf8), toPath: path)
    }

    private static func splitLines(_ data: Data, source: String) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MetaphorError.data(.loadFailed(source: source, detail: "not valid UTF-8 text"))
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: - JSON

    /// JSON ファイル/URL を動的な ``JSONValue`` として読み込みます。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列
    /// - Throws: ``MetaphorError/data(_:)`` 読み込み・パースに失敗した場合
    public static func loadJSON(_ source: String) throws -> JSONValue {
        try JSONValue(data: readData(source))
    }

    /// ``loadJSON(_:)`` の非同期版。
    public static func loadJSONAsync(_ source: String) async throws -> JSONValue {
        try JSONValue(data: await readDataAsync(source))
    }

    /// JSON ファイル/URL を `Decodable` な型として読み込みます。
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列
    ///   - type: デコード先の型
    /// - Throws: ``MetaphorError/data(_:)`` 読み込み・デコードに失敗した場合
    public static func loadJSON<T: Decodable>(_ source: String, as type: T.Type) throws -> T {
        try decodeJSON(readData(source), as: type)
    }

    /// ``loadJSON(_:as:)`` の非同期版。
    public static func loadJSONAsync<T: Decodable>(_ source: String, as type: T.Type) async throws -> T {
        try decodeJSON(await readDataAsync(source), as: type)
    }

    /// `Encodable` な値（``JSONValue`` を含む）を JSON ファイルへ書き込みます。
    ///
    /// - Parameters:
    ///   - value: 書き込む値
    ///   - path: 出力ファイルパス
    ///   - pretty: インデント付きで整形するか（キーは常にソートされ決定的）
    /// - Throws: ``MetaphorError/data(_:)`` エンコード・書き込みに失敗した場合
    public static func saveJSON(_ value: some Encodable, toPath path: String, pretty: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw MetaphorError.data(.encodeFailed(detail: error.localizedDescription))
        }
        try writeData(data, toPath: path)
    }

    private static func decodeJSON<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MetaphorError.data(.decodeFailed(type: String(describing: type), detail: "\(error)"))
        }
    }

    // MARK: - Table

    /// CSV/TSV ファイル/URL を ``Table`` として読み込みます。
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列
    ///   - format: 区切り形式。nil の場合は拡張子から推定（`.tsv` 以外は CSV）
    ///   - header: 先頭行を列タイトルとして扱うか
    /// - Throws: ``MetaphorError/data(_:)`` 読み込み・パースに失敗した場合
    public static func loadTable(
        _ source: String, format: TableFormat? = nil, header: Bool = true
    ) throws -> Table {
        try Table(
            data: readData(source),
            format: format ?? .inferred(fromPath: source),
            header: header)
    }

    /// ``loadTable(_:format:header:)`` の非同期版。
    public static func loadTableAsync(
        _ source: String, format: TableFormat? = nil, header: Bool = true
    ) async throws -> Table {
        try Table(
            data: await readDataAsync(source),
            format: format ?? .inferred(fromPath: source),
            header: header)
    }

    /// ``Table`` を CSV/TSV ファイルへ書き込みます。
    ///
    /// - Parameters:
    ///   - table: 書き込むテーブル
    ///   - path: 出力ファイルパス
    ///   - format: 区切り形式。nil の場合は拡張子から推定（`.tsv` 以外は CSV）
    ///   - header: 列タイトル行を出力するか
    /// - Throws: ``MetaphorError/data(_:)`` 書き込みに失敗した場合
    public static func saveTable(
        _ table: Table, toPath path: String, format: TableFormat? = nil, header: Bool = true
    ) throws {
        let text = table.serialized(format: format ?? .inferred(fromPath: path), header: header)
        try writeData(Data(text.utf8), toPath: path)
    }
}
