import Foundation
import Testing
@testable import metaphor
@testable import MetaphorCore

// MARK: - JSONValue Tests

@Suite("JSONValue")
struct JSONValueTests {

    @Test("parses nested JSON and chains subscripts")
    func parseNested() throws {
        let json = try JSONValue(string: """
            {"bubbles": [{"position": {"x": 160, "y": 103}, "diameter": 43.5, "label": "Happy"}]}
            """)
        #expect(json["bubbles"].count == 1)
        let bubble = json["bubbles"][0]
        #expect(bubble["position"]["x"].intValue == 160)
        #expect(bubble["diameter"].doubleValue == 43.5)
        #expect(bubble["label"].stringValue == "Happy")
    }

    @Test("missing keys and indices fall through to null")
    func nullFallthrough() throws {
        let json = try JSONValue(string: #"{"a": 1}"#)
        #expect(json["missing"].isNull)
        #expect(json["missing"]["deeper"][3].isNull)
        #expect(json["missing"].stringValue == "")
        #expect(json["missing"].intValue == 0)
        #expect(json["missing"].string == nil)
    }

    @Test("parses scalars, booleans and null")
    func parseScalars() throws {
        let json = try JSONValue(string: #"{"t": true, "f": false, "n": null, "s": "x", "i": 42}"#)
        #expect(json["t"].bool == true)
        #expect(json["f"].boolValue == false)
        #expect(json["n"].isNull)
        #expect(json["s"].string == "x")
        #expect(json["i"].int == 42)
        // Bool は number として読めない / number は bool として読めない
        #expect(json["t"].double == nil)
        #expect(json["i"].bool == nil)
    }

    @Test("invalid JSON throws data error")
    func invalidJSON() {
        #expect(throws: MetaphorError.self) {
            try JSONValue(string: "{not json")
        }
    }

    @Test("construction from dynamic values")
    func valueConstruction() {
        #expect(JSONValue(Float(1.5)) == .number(1.5))
        #expect(JSONValue(42) == .number(42))
        #expect(JSONValue("text") == .string("text"))
        #expect(JSONValue(true) == .bool(true))
    }

    @Test("literal construction and mutation")
    func literalsAndMutation() {
        var json: JSONValue = ["bubbles": []]
        var bubble: JSONValue = ["position": ["x": 10, "y": 20], "diameter": 50.5, "label": "New"]
        bubble["label"] = "Renamed"
        json["bubbles"].append(bubble)
        #expect(json["bubbles"].count == 1)
        #expect(json["bubbles"][0]["label"].stringValue == "Renamed")
        #expect(json["bubbles"][0]["position"]["y"].intValue == 20)

        json["bubbles"].remove(at: 0)
        #expect(json["bubbles"].count == 0)
    }

    @Test("append to null creates array, remove out of bounds is a no-op")
    func appendEdgeCases() {
        var value = JSONValue.null
        value.append("first")
        #expect(value.count == 1)

        var array: JSONValue = [1, 2]
        array.remove(at: 5)
        #expect(array.count == 2)

        var scalar: JSONValue = "text"
        scalar.append("x")
        #expect(scalar == "text")
    }

    @Test("serialized output is deterministic and round-trips")
    func serializeRoundTrip() throws {
        let original: JSONValue = ["b": 2, "a": [true, nil, "s"], "c": ["nested": 1.5]]
        let data = original.serialized()
        let reparsed = try JSONValue(data: data)
        #expect(reparsed == original)
        // キーソートにより決定的
        #expect(original.serialized() == original.serialized())
    }

    @Test("Codable round-trip through JSONEncoder")
    func codableRoundTrip() throws {
        let original: JSONValue = ["x": 1, "list": [1, "two", false], "null": nil]
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - Table Tests

@Suite("Table")
struct TableTests {

    @Test("parses CSV with header")
    func parseCSVHeader() throws {
        let table = try Table(string: "x,y,name\n1,2,Happy\n3,4,Sad\n")
        #expect(table.columnTitles == ["x", "y", "name"])
        #expect(table.rowCount == 2)
        #expect(table.columnCount == 3)
        let row = try #require(table.getRow(0))
        #expect(row.getInt("x") == 1)
        #expect(row.getFloat("y") == 2)
        #expect(row.getString("name") == "Happy")
    }

    @Test("parses CSV without header using numbered columns")
    func parseCSVNoHeader() throws {
        let table = try Table(string: "1,2\n3,4\n", header: false)
        #expect(table.columnTitles == ["0", "1"])
        #expect(table.rowCount == 2)
        #expect(table.getRow(1)?.getInt("0") == 3)
        #expect(table.getRow(1)?.getInt(1) == 4)
    }

    @Test("parses TSV")
    func parseTSV() throws {
        let table = try Table(string: "a\tb\n1\ttext with, comma\n", format: .tsv)
        #expect(table.getRow(0)?.getString("b") == "text with, comma")
    }

    @Test("handles RFC 4180 quoting: embedded delimiter, quote, newline")
    func parseQuoted() throws {
        let csv = "name,note\n\"Smith, John\",\"said \"\"hi\"\"\"\n\"multi\nline\",plain\n"
        let table = try Table(string: csv)
        #expect(table.getRow(0)?.getString("name") == "Smith, John")
        #expect(table.getRow(0)?.getString("note") == #"said "hi""#)
        #expect(table.getRow(1)?.getString("name") == "multi\nline")
        #expect(table.getRow(1)?.getString("note") == "plain")
    }

    @Test("handles CRLF line endings and skips blank lines")
    func parseCRLFAndBlankLines() throws {
        let table = try Table(string: "a,b\r\n1,2\r\n\r\n3,4\r\n")
        #expect(table.rowCount == 2)
        #expect(table.getRow(1)?.getInt("a") == 3)
    }

    @Test("ragged rows throw parse error")
    func raggedRows() {
        #expect(throws: MetaphorError.self) {
            try Table(string: "a,b\n1,2,3\n")
        }
    }

    @Test("unterminated quote throws parse error")
    func unterminatedQuote() {
        #expect(throws: MetaphorError.self) {
            try Table(string: "a,b\n\"open,2\n")
        }
    }

    @Test("empty header-only table has zero rows")
    func headerOnly() throws {
        let table = try Table(string: "a,b\n")
        #expect(table.rowCount == 0)
        #expect(table.columnCount == 2)
    }

    @Test("empty input with header throws")
    func emptyInput() {
        #expect(throws: MetaphorError.self) {
            try Table(string: "")
        }
    }

    @Test("row mutation via reference reflects into table")
    func rowMutation() throws {
        let table = try Table(string: "x,name\n1,old\n")
        let row = table.addRow()
        row.setFloat("x", 12.5)
        row.setString("name", "Blah")
        #expect(table.rowCount == 2)
        #expect(table.getRow(1)?.getFloat("x") == 12.5)
        #expect(table.getRow(1)?.getString("name") == "Blah")

        table.removeRow(0)
        #expect(table.rowCount == 1)
        #expect(table.getRow(0)?.getString("name") == "Blah")
        // 範囲外 removeRow は no-op
        table.removeRow(10)
        #expect(table.rowCount == 1)
    }

    @Test("addRow pads missing values and drops extras")
    func addRowPadding() throws {
        let table = try Table(string: "a,b,c\n")
        table.addRow(["1"])
        #expect(table.getRow(0)?.values == ["1", "", ""])
        table.addRow(["1", "2", "3", "4"])
        #expect(table.getRow(1)?.values == ["1", "2", "3"])
    }

    @Test("unknown column returns defaults")
    func unknownColumn() throws {
        let table = try Table(string: "a\n1\n")
        let row = try #require(table.getRow(0))
        #expect(row.getString("missing") == "")
        #expect(row.getInt("missing") == 0)
        #expect(row.getFloat("missing") == 0)
        #expect(row.getString(9) == "")
    }

    @Test("serialization quotes special fields and round-trips")
    func serializeRoundTrip() throws {
        let table = Table(columnTitles: ["name", "note"])
        table.addRow(["Smith, John", #"said "hi""#])
        table.addRow(["multi\nline", "plain"])
        table.addRow(["crlf\r\nfield", "plain"])
        let csv = table.serialized()
        let reparsed = try Table(string: csv)
        #expect(reparsed.columnTitles == table.columnTitles)
        #expect(reparsed.getRow(0)?.getString("name") == "Smith, John")
        #expect(reparsed.getRow(0)?.getString("note") == #"said "hi""#)
        #expect(reparsed.getRow(1)?.getString("name") == "multi\nline")
        #expect(reparsed.getRow(2)?.getString("name") == "crlf\r\nfield")
    }

    @Test("addColumn extends existing rows")
    func addColumn() throws {
        let table = try Table(string: "a\n1\n")
        table.addColumn("b")
        #expect(table.columnCount == 2)
        #expect(table.getRow(0)?.values == ["1", ""])
        table.getRow(0)?.setInt("b", 7)
        #expect(table.getRow(0)?.getInt("b") == 7)
    }

    @Test("format inference from path extension")
    func formatInference() {
        #expect(TableFormat.inferred(fromPath: "data/file.tsv") == .tsv)
        #expect(TableFormat.inferred(fromPath: "data/file.TSV") == .tsv)
        #expect(TableFormat.inferred(fromPath: "data/file.csv") == .csv)
        #expect(TableFormat.inferred(fromPath: "no-extension") == .csv)
    }
}

// MARK: - DataIO File Round-Trip Tests

@Suite("DataIO file operations")
struct DataIOFileTests {

    /// テストごとの一時ディレクトリを作り、終了時に削除して実行する
    private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-dataio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("saveStrings/loadStrings round-trip")
    func stringsRoundTrip() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("lines.txt").path
            let lines = ["first", "", "third with spaces", "四行目"]
            try DataIO.saveStrings(lines, toPath: path)
            #expect(try DataIO.loadStrings(path) == lines)
        }
    }

    @Test("loadStrings handles CRLF and no trailing newline")
    func stringsLineEndings() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("crlf.txt").path
            try Data("a\r\nb\r\nc".utf8).write(to: URL(fileURLWithPath: path))
            #expect(try DataIO.loadStrings(path) == ["a", "b", "c"])
        }
    }

    @Test("loadStrings on non-UTF8 data throws")
    func stringsNonUTF8() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("binary.bin").path
            try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: URL(fileURLWithPath: path))
            #expect(throws: MetaphorError.self) {
                try DataIO.loadStrings(path)
            }
        }
    }

    @Test("saveJSON/loadJSON round-trip with JSONValue")
    func jsonRoundTrip() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("data.json").path
            let original: JSONValue = ["bubbles": [["diameter": 43.5, "label": "Happy"]]]
            try DataIO.saveJSON(original, toPath: path)
            let loaded = try DataIO.loadJSON(path)
            #expect(loaded == original)
        }
    }

    @Test("saveJSON/loadJSON round-trip with Codable type")
    func jsonCodableRoundTrip() throws {
        struct Config: Codable, Equatable {
            var width: Int
            var title: String
        }
        try withTempDir { dir in
            let path = dir.appendingPathComponent("config.json").path
            let original = Config(width: 640, title: "sketch")
            try DataIO.saveJSON(original, toPath: path)
            #expect(try DataIO.loadJSON(path, as: Config.self) == original)
        }
    }

    @Test("loadJSON with mismatched Codable type throws decode error")
    func jsonDecodeMismatch() throws {
        struct Expected: Codable {
            var missingField: Int
        }
        try withTempDir { dir in
            let path = dir.appendingPathComponent("data.json").path
            try DataIO.saveJSON(["other": 1] as JSONValue, toPath: path)
            #expect(throws: MetaphorError.self) {
                try DataIO.loadJSON(path, as: Expected.self)
            }
        }
    }

    @Test("saveTable/loadTable round-trip with format inference")
    func tableRoundTrip() throws {
        try withTempDir { dir in
            let csvPath = dir.appendingPathComponent("data.csv").path
            let tsvPath = dir.appendingPathComponent("data.tsv").path
            let table = Table(columnTitles: ["x", "name"])
            table.addRow(["1", "Happy, very"])
            try DataIO.saveTable(table, toPath: csvPath)
            try DataIO.saveTable(table, toPath: tsvPath)

            let csvLoaded = try DataIO.loadTable(csvPath)
            #expect(csvLoaded.getRow(0)?.getString("name") == "Happy, very")

            let tsvLoaded = try DataIO.loadTable(tsvPath)
            #expect(tsvLoaded.getRow(0)?.getString("name") == "Happy, very")
            // TSV 出力にカンマのクォートは不要（生の内容が保たれる）
            let rawTSV = try String(contentsOfFile: tsvPath, encoding: .utf8)
            #expect(rawTSV.contains("Happy, very"))
        }
    }

    @Test("writes create missing parent directories")
    func writeCreatesParents() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("nested/deep/out.txt").path
            try DataIO.saveStrings(["x"], toPath: path)
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("loading nonexistent path throws load error")
    func nonexistentPath() {
        let path = "/nonexistent-\(UUID().uuidString)/missing.json"
        #expect(throws: MetaphorError.self) { try DataIO.loadJSON(path) }
        #expect(throws: MetaphorError.self) { try DataIO.loadStrings(path) }
        #expect(throws: MetaphorError.self) { try DataIO.loadTable(path) }
    }

    @Test("async file load matches sync result")
    func asyncFileLoad() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-dataio-async-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let path = dir.appendingPathComponent("data.json").path
        try DataIO.saveJSON(["k": [1, 2, 3]] as JSONValue, toPath: path)
        let loaded = try await DataIO.loadJSONAsync(path)
        #expect(loaded["k"].count == 3)

        let tablePath = dir.appendingPathComponent("t.csv").path
        try DataIO.saveTable({ let t = Table(columnTitles: ["a"]); t.addRow(["1"]); return t }(), toPath: tablePath)
        let table = try await DataIO.loadTableAsync(tablePath)
        #expect(table.rowCount == 1)

        let strings = try await DataIO.loadStringsAsync(tablePath)
        #expect(strings == ["a", "1"])
    }

    @Test("remote URL detection")
    func remoteURLDetection() {
        #expect(DataIO.remoteURL("https://example.com/data.json") != nil)
        #expect(DataIO.remoteURL("HTTP://example.com/x") != nil)
        #expect(DataIO.remoteURL("data/data.json") == nil)
        #expect(DataIO.remoteURL("/absolute/path.csv") == nil)
    }
}
