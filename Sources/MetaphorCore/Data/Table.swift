import Foundation

/// テーブルのシリアライズ形式。
public enum TableFormat: String, Sendable {
    /// カンマ区切り（RFC 4180 準拠のクォート処理）
    case csv
    /// タブ区切り
    case tsv

    /// フィールドの区切り文字
    var delimiter: Character {
        switch self {
        case .csv: ","
        case .tsv: "\t"
        }
    }

    /// ファイルパスの拡張子から形式を推定します（`.tsv` 以外は CSV）。
    static func inferred(fromPath path: String) -> TableFormat {
        (path as NSString).pathExtension.lowercased() == "tsv" ? .tsv : .csv
    }
}

/// CSV/TSV の表データ。Processing の `Table` に相当します。
///
/// 参照型のため、``TableRow`` 経由のセル更新はテーブル本体へ反映されます:
///
/// ```swift
/// let table = try loadTable("data.csv")
/// for row in table.rows {
///     let x = row.getFloat("x")
///     let name = row.getString("name")
/// }
/// let row = table.addRow()
/// row.setFloat("x", 120)
/// row.setString("name", "Blah")
/// try saveTable(table, "data/data.csv")
/// ```
public final class Table {
    /// 列タイトル。ヘッダなしで読み込んだ場合は `"0", "1", ...` の連番
    public private(set) var columnTitles: [String]

    /// 全行。この配列の ``TableRow`` はテーブル本体への参照を保持します
    public private(set) var rows: [TableRow]

    /// 行数
    public var rowCount: Int { rows.count }

    /// 列数
    public var columnCount: Int { columnTitles.count }

    /// 空のテーブルを作成します。
    ///
    /// - Parameter columnTitles: 列タイトル（省略時は空）
    public init(columnTitles: [String] = []) {
        self.columnTitles = columnTitles
        self.rows = []
    }

    /// CSV/TSV テキスト（UTF-8 データ）をパースします。
    ///
    /// - Parameters:
    ///   - data: CSV/TSV のバイト列
    ///   - format: 区切り形式
    ///   - header: 先頭行を列タイトルとして扱うか
    /// - Throws: ``MetaphorError/data(_:)`` UTF-8 でない・行の列数が不揃いの場合
    public convenience init(data: Data, format: TableFormat = .csv, header: Bool = true) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MetaphorError.data(.parseFailed(detail: "table data is not valid UTF-8"))
        }
        try self.init(string: text, format: format, header: header)
    }

    /// CSV/TSV テキストをパースします。
    ///
    /// - Parameters:
    ///   - string: CSV/TSV 文字列
    ///   - format: 区切り形式
    ///   - header: 先頭行を列タイトルとして扱うか
    /// - Throws: ``MetaphorError/data(_:)`` 行の列数がヘッダと一致しない場合
    public convenience init(string: String, format: TableFormat = .csv, header: Bool = true) throws {
        var records = try Self.parseRecords(string, delimiter: format.delimiter)
        let titles: [String]
        if header {
            guard !records.isEmpty else {
                throw MetaphorError.data(.parseFailed(detail: "table has no header row"))
            }
            titles = records.removeFirst()
        } else {
            titles = (0..<(records.first?.count ?? 0)).map(String.init)
        }
        for (index, record) in records.enumerated() where record.count != titles.count {
            throw MetaphorError.data(.parseFailed(
                detail: "row \(index) has \(record.count) fields, expected \(titles.count)"))
        }
        self.init(columnTitles: titles)
        for record in records {
            addRow(record)
        }
    }

    // MARK: - 行操作

    /// 空の行を末尾に追加します。
    ///
    /// - Returns: 追加された行（セルはすべて空文字列）
    @discardableResult
    public func addRow() -> TableRow {
        addRow(Array(repeating: "", count: columnCount))
    }

    /// 値を指定して行を末尾に追加します。
    ///
    /// - Parameter values: セル値。列数に満たない分は空文字列で埋め、超過分は警告して切り捨て
    /// - Returns: 追加された行
    @discardableResult
    public func addRow(_ values: [String]) -> TableRow {
        var cells = values
        if cells.count > columnCount {
            metaphorWarning("Table.addRow: \(cells.count) values exceed \(columnCount) columns; extra values dropped")
            cells = Array(cells.prefix(columnCount))
        } else if cells.count < columnCount {
            cells += Array(repeating: "", count: columnCount - cells.count)
        }
        let row = TableRow(table: self, cells: cells)
        rows.append(row)
        return row
    }

    /// 指定インデックスの行を削除します。範囲外は警告のみ。
    public func removeRow(_ index: Int) {
        guard rows.indices.contains(index) else {
            metaphorWarning("Table.removeRow: index \(index) out of bounds (rowCount: \(rowCount))")
            return
        }
        rows.remove(at: index)
    }

    /// 指定インデックスの行を返します。範囲外は nil。
    public func getRow(_ index: Int) -> TableRow? {
        guard rows.indices.contains(index) else { return nil }
        return rows[index]
    }

    /// 列を末尾に追加します。既存行には空文字列のセルが足されます。
    public func addColumn(_ title: String) {
        columnTitles.append(title)
        for row in rows {
            row.cells.append("")
        }
    }

    /// 列タイトルから列インデックスを返します。存在しなければ nil。
    public func columnIndex(of title: String) -> Int? {
        columnTitles.firstIndex(of: title)
    }

    // MARK: - シリアライズ

    /// CSV/TSV テキストとしてシリアライズします。
    ///
    /// 区切り文字・引用符・改行を含むフィールドは RFC 4180 に従いクォートされます。
    /// ヘッダなし（連番タイトル）で読み込んだ場合もタイトル行は出力されます。
    ///
    /// - Parameters:
    ///   - format: 区切り形式
    ///   - header: 列タイトル行を出力するか
    /// - Returns: シリアライズされたテキスト（末尾改行つき）
    public func serialized(format: TableFormat = .csv, header: Bool = true) -> String {
        var lines: [String] = []
        if header {
            lines.append(Self.serializeRecord(columnTitles, delimiter: format.delimiter))
        }
        for row in rows {
            lines.append(Self.serializeRecord(row.cells, delimiter: format.delimiter))
        }
        return lines.map { $0 + "\n" }.joined()
    }

    // MARK: - CSV パーサ（RFC 4180）

    /// クォート（埋め込み区切り文字・改行・`""` エスケープ）に対応したレコード分割。
    ///
    /// 注意: Swift の `Character` は書記素クラスタ単位のため、CRLF は 1 文字 `"\r\n"` として現れる。
    private static func parseRecords(_ text: String, delimiter: Character) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        func advance() -> Character? {
            defer { pending = iterator.next() }
            return pending
        }

        while let char = advance() {
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        _ = advance()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case delimiter:
                    record.append(field)
                    field = ""
                case "\r\n", "\n", "\r":
                    record.append(field)
                    field = ""
                    records.append(record)
                    record = []
                default:
                    field.append(char)
                }
            }
        }
        if inQuotes {
            throw MetaphorError.data(.parseFailed(detail: "unterminated quoted field"))
        }
        // 最終行（末尾改行なし）
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        // 空行（フィールドが 1 つも無い行）は Processing 同様スキップ
        return records.filter { $0 != [""] }
    }

    private static func serializeRecord(_ fields: [String], delimiter: Character) -> String {
        fields.map { field in
            // CRLF は 1 Character のため "\n"/"\r" の contains にかからない — 明示的に含める
            let needsQuoting = field.contains(delimiter) || field.contains("\"")
                || field.contains("\n") || field.contains("\r") || field.contains("\r\n")
            return if needsQuoting {
                "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            } else {
                field
            }
        }.joined(separator: String(delimiter))
    }
}

/// ``Table`` の 1 行。Processing の `TableRow` に相当します。
///
/// テーブル本体への参照を持つため、setter による変更はテーブルに反映されます。
public final class TableRow {
    /// 所属テーブル（列タイトルの解決に使用）
    private weak var table: Table?

    /// セル値（列順）
    fileprivate(set) var cells: [String]

    init(table: Table, cells: [String]) {
        self.table = table
        self.cells = cells
    }

    /// この行のセル値の配列（列順）
    public var values: [String] { cells }

    private func index(of column: String) -> Int? {
        guard let table else {
            metaphorWarning("TableRow: owning Table no longer exists")
            return nil
        }
        guard let index = table.columnIndex(of: column) else {
            metaphorWarning("TableRow: column '\(column)' not found (columns: \(table.columnTitles))")
            return nil
        }
        return index
    }

    // MARK: - 取得

    /// 列名でセル値を取得します。列が存在しなければ空文字列（警告つき）。
    public func getString(_ column: String) -> String {
        guard let index = index(of: column) else { return "" }
        return cells[index]
    }

    /// 列インデックスでセル値を取得します。範囲外は空文字列。
    public func getString(_ index: Int) -> String {
        guard cells.indices.contains(index) else { return "" }
        return cells[index]
    }

    /// 列名でセル値を Int として取得します。Int として表現できなければ 0。
    ///
    /// 小数は 0 方向へ切り捨てます。数値でない文字列に加え、`nan` / `inf` などの
    /// 非有限値と Int の範囲を超える値も 0 になります。
    public func getInt(_ column: String) -> Int { Self.int(from: getString(column)) }

    /// 列インデックスでセル値を Int として取得します。Int として表現できなければ 0。
    public func getInt(_ index: Int) -> Int { Self.int(from: getString(index)) }

    /// 列名でセル値を Float として取得します。有限な数値でなければ 0。
    public func getFloat(_ column: String) -> Float { Self.float(from: getString(column)) }

    /// 列インデックスでセル値を Float として取得します。有限な数値でなければ 0。
    public func getFloat(_ index: Int) -> Float { Self.float(from: getString(index)) }

    /// 列名でセル値を Double として取得します。有限な数値でなければ 0。
    public func getDouble(_ column: String) -> Double { Self.double(from: getString(column)) }

    /// 列インデックスでセル値を Double として取得します。有限な数値でなければ 0。
    public func getDouble(_ index: Int) -> Double { Self.double(from: getString(index)) }

    // MARK: - 数値変換

    /// `Int` が表現できる範囲の上限（排他）。`2^63` は Double で正確に表せる。
    private static let intUpperExclusive = 9_223_372_036_854_775_808.0
    /// `Int` が表現できる範囲の下限（包含）。`-2^63` は Double で正確に表せる。
    private static let intLowerInclusive = -9_223_372_036_854_775_808.0

    /// セル文字列を `Int` へ変換します。表現できない値は 0（Issue #580）。
    ///
    /// 従来は `Int(Double(cell) ?? 0)` を素通ししていたため、`nan` / `inf` や
    /// `Int` の範囲を超える有限値で「Double value cannot be converted to Int」の
    /// トラップが起き、CSV を読むだけでスケッチが終了していた。欠損列・非数値
    /// 文字列が 0 になるのは正常系なので、警告は「数値には見えるが Int として
    /// 表現できない」ケースだけに絞る。
    private static func int(from cell: String) -> Int {
        guard let value = Double(cell) else { return 0 }
        guard value.isFinite else {
            metaphorWarning("TableRow.getInt: '\(cell)' is not a finite number; using 0")
            return 0
        }
        let truncated = value.rounded(.towardZero)
        guard truncated >= intLowerInclusive, truncated < intUpperExclusive else {
            metaphorWarning("TableRow.getInt: '\(cell)' is outside the Int range; using 0")
            return 0
        }
        return Int(truncated)
    }

    /// セル文字列を有限な `Float` へ変換します。非有限値は 0（Issue #580）。
    ///
    /// NaN は以降の演算を黙って汚染するため、`getInt` と同じく 0 へ寄せて
    /// 「数値でなければ 0」の意味を 3 つの getter で揃える。
    private static func float(from cell: String) -> Float {
        guard let value = Float(cell) else { return 0 }
        guard value.isFinite else {
            metaphorWarning("TableRow.getFloat: '\(cell)' is not a finite Float; using 0")
            return 0
        }
        return value
    }

    /// セル文字列を有限な `Double` へ変換します。非有限値は 0（Issue #580）。
    private static func double(from cell: String) -> Double {
        guard let value = Double(cell) else { return 0 }
        guard value.isFinite else {
            metaphorWarning("TableRow.getDouble: '\(cell)' is not a finite Double; using 0")
            return 0
        }
        return value
    }

    // MARK: - 設定

    /// 列名でセル値を設定します。列が存在しなければ警告のみ。
    public func setString(_ column: String, _ value: String) {
        guard let index = index(of: column) else { return }
        cells[index] = value
    }

    /// 列インデックスでセル値を設定します。範囲外は警告のみ。
    public func setString(_ index: Int, _ value: String) {
        guard cells.indices.contains(index) else {
            metaphorWarning("TableRow.setString: index \(index) out of bounds")
            return
        }
        cells[index] = value
    }

    /// 列名でセル値を Int として設定します。
    public func setInt(_ column: String, _ value: Int) { setString(column, String(value)) }

    /// 列インデックスでセル値を Int として設定します。
    public func setInt(_ index: Int, _ value: Int) { setString(index, String(value)) }

    /// 列名でセル値を Float として設定します。
    public func setFloat(_ column: String, _ value: Float) { setString(column, String(value)) }

    /// 列インデックスでセル値を Float として設定します。
    public func setFloat(_ index: Int, _ value: Float) { setString(index, String(value)) }

    /// 列名でセル値を Double として設定します。
    public func setDouble(_ column: String, _ value: Double) { setString(column, String(value)) }

    /// 列インデックスでセル値を Double として設定します。
    public func setDouble(_ index: Int, _ value: Double) { setString(index, String(value)) }
}
