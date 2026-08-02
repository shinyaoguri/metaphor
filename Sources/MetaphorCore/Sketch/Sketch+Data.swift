// MARK: - Data IO (JSON / Table / Strings)

extension Sketch {

    // MARK: Strings

    /// テキストファイル/URL を行の配列として読み込みます。
    ///
    /// パスは絶対パスまたは現在ディレクトリ相対。`http://` / `https://` で始まる場合は
    /// リモート URL として取得します（応答までブロックするため、`draw()` 内では
    /// ``loadStringsAsync(_:)`` を推奨）。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列。
    /// - Returns: 各行の配列（改行は含まない）。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合・内容が UTF-8 でない場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``。
    public func loadStrings(_ source: String) throws -> [String] {
        try DataIO.loadStrings(source)
    }

    /// テキストファイル/URL を行の配列として非同期で読み込みます。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列。
    /// - Returns: 各行の配列（改行は含まない）。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合・内容が UTF-8 でない場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``。
    public func loadStringsAsync(_ source: String) async throws -> [String] {
        try await DataIO.loadStringsAsync(source)
    }

    /// 行の配列をテキストファイルへ書き込みます（UTF-8・各行に改行を付与）。
    ///
    /// 親ディレクトリがなければ作成します。
    ///
    /// - Parameters:
    ///   - lines: 書き込む行。
    ///   - path: 出力ファイルパス。
    /// - Throws: ``MetaphorError/data(_:)`` の ``MetaphorError/DataFailure/writeFailed(path:detail:)``
    ///   書き込みに失敗した場合。
    public func saveStrings(_ lines: [String], _ path: String) throws {
        try DataIO.saveStrings(lines, toPath: path)
    }

    // MARK: JSON

    /// JSON ファイル/URL を動的な ``JSONValue`` として読み込みます。
    ///
    /// Processing の `loadJSONObject()` / `loadJSONArray()` に相当します。
    /// スキーマが既知の場合は `Codable` 版 ``loadJSON(_:as:)`` を推奨します。
    ///
    /// ```swift
    /// let json = try loadJSON("data/data.json")
    /// for bubble in json["bubbles"].arrayValue {
    ///     let x = bubble["position"]["x"].doubleValue
    /// }
    /// ```
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列。
    /// - Returns: パースされた JSON 値。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、JSON のパースに
    ///   失敗した場合は ``MetaphorError/DataFailure/parseFailed(detail:)``。
    public func loadJSON(_ source: String) throws -> JSONValue {
        try DataIO.loadJSON(source)
    }

    /// JSON ファイル/URL を動的な ``JSONValue`` として非同期で読み込みます。
    ///
    /// - Parameter source: ファイルパスまたは URL 文字列。
    /// - Returns: パースされた JSON 値。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、JSON のパースに
    ///   失敗した場合は ``MetaphorError/DataFailure/parseFailed(detail:)``。
    public func loadJSONAsync(_ source: String) async throws -> JSONValue {
        try await DataIO.loadJSONAsync(source)
    }

    /// JSON ファイル/URL を `Decodable` な型として読み込みます。
    ///
    /// ```swift
    /// struct Config: Codable { var width: Int; var title: String }
    /// let config = try loadJSON("config.json", as: Config.self)
    /// ```
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列。
    ///   - type: デコード先の型。
    /// - Returns: デコードされた値。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、デコードに
    ///   失敗した場合は ``MetaphorError/DataFailure/decodeFailed(type:detail:)``。
    public func loadJSON<T: Decodable>(_ source: String, as type: T.Type) throws -> T {
        try DataIO.loadJSON(source, as: type)
    }

    /// JSON ファイル/URL を `Decodable` な型として非同期で読み込みます。
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列。
    ///   - type: デコード先の型。
    /// - Returns: デコードされた値。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、デコードに
    ///   失敗した場合は ``MetaphorError/DataFailure/decodeFailed(type:detail:)``。
    public func loadJSONAsync<T: Decodable>(_ source: String, as type: T.Type) async throws -> T {
        // メタタイプ `T.Type` は `T: Sendable` のときしか Sendable にならない。
        // `DataIO.loadJSONAsync(_:as:)` へそのまま渡すと @MainActor から
        // nonisolated へ `type` を送ることになり警告になる（`T: Sendable` を足すのは
        // 公開 API の制約強化なので採らない）。読み込みだけを await し、デコードは
        // 呼び出し側の隔離ドメインに留めることで送信そのものを無くす。
        let data = try await DataIO.readDataAsync(source)
        return try DataIO.decodeJSON(data, as: type)
    }

    /// `Encodable` な値（``JSONValue`` を含む）を JSON ファイルへ書き込みます。
    ///
    /// Processing の `saveJSONObject()` に相当します。キーはソートされ出力は決定的です。
    /// 親ディレクトリがなければ作成します。
    ///
    /// - Parameters:
    ///   - value: 書き込む値。
    ///   - path: 出力ファイルパス。
    ///   - pretty: インデント付きで整形するか（既定 true）。
    /// - Throws: ``MetaphorError/data(_:)``。エンコードに失敗した場合は
    ///   ``MetaphorError/DataFailure/encodeFailed(detail:)``、書き込みに
    ///   失敗した場合は ``MetaphorError/DataFailure/writeFailed(path:detail:)``。
    public func saveJSON(_ value: some Encodable, _ path: String, pretty: Bool = true) throws {
        try DataIO.saveJSON(value, toPath: path, pretty: pretty)
    }

    // MARK: Table

    /// CSV/TSV ファイル/URL を ``Table`` として読み込みます。
    ///
    /// Processing の `loadTable(path, "header")` に相当します（ヘッダは既定で有効。
    /// ヘッダなしファイルは `header: false` を指定すると列名が `"0", "1", ...` になります）。
    ///
    /// ```swift
    /// let table = try loadTable("data/data.csv")
    /// for row in table.rows {
    ///     let x = row.getFloat("x")
    ///     let name = row.getString("name")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列。
    ///   - format: 区切り形式。省略時は拡張子から推定（`.tsv` 以外は CSV）。
    ///   - header: 先頭行を列タイトルとして扱うか（既定 true）。
    /// - Returns: パースされたテーブル。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、CSV/TSV のパースに
    ///   失敗した場合は ``MetaphorError/DataFailure/parseFailed(detail:)``。
    public func loadTable(
        _ source: String, format: TableFormat? = nil, header: Bool = true
    ) throws -> Table {
        try DataIO.loadTable(source, format: format, header: header)
    }

    /// CSV/TSV ファイル/URL を ``Table`` として非同期で読み込みます。
    ///
    /// - Parameters:
    ///   - source: ファイルパスまたは URL 文字列。
    ///   - format: 区切り形式。省略時は拡張子から推定（`.tsv` 以外は CSV）。
    ///   - header: 先頭行を列タイトルとして扱うか（既定 true）。
    /// - Returns: パースされたテーブル。
    /// - Throws: ``MetaphorError/data(_:)``。読み込みに失敗した場合は
    ///   ``MetaphorError/DataFailure/loadFailed(source:detail:)``、CSV/TSV のパースに
    ///   失敗した場合は ``MetaphorError/DataFailure/parseFailed(detail:)``。
    public func loadTableAsync(
        _ source: String, format: TableFormat? = nil, header: Bool = true
    ) async throws -> Table {
        // `Table` は非 Sendable な class なので、nonisolated な
        // `DataIO.loadTableAsync` の戻り値を @MainActor へ跨がせると警告になる
        //（Swift 5.10）。読み込みだけ await し、`Table` の生成は呼び出し側の
        // 隔離ドメインで行う（loadJSONAsync と同じ方針。公開 API は不変）。
        let data = try await DataIO.readDataAsync(source)
        return try Table(
            data: data, format: format ?? .inferred(fromPath: source), header: header)
    }

    /// ``Table`` を CSV/TSV ファイルへ書き込みます。
    ///
    /// Processing の `saveTable()` に相当します。親ディレクトリがなければ作成します。
    ///
    /// - Parameters:
    ///   - table: 書き込むテーブル。
    ///   - path: 出力ファイルパス。
    ///   - format: 区切り形式。省略時は拡張子から推定（`.tsv` 以外は CSV）。
    ///   - header: 列タイトル行を出力するか（既定 true）。
    /// - Throws: ``MetaphorError/data(_:)`` の ``MetaphorError/DataFailure/writeFailed(path:detail:)``
    ///   書き込みに失敗した場合。
    public func saveTable(
        _ table: Table, _ path: String, format: TableFormat? = nil, header: Bool = true
    ) throws {
        try DataIO.saveTable(table, toPath: path, format: format, header: header)
    }
}
