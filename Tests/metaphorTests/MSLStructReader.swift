import Foundation

// MSL のレイアウトを読むテスト用ヘルパ。#1142 で `Canvas2DMassiveTests.swift` に置いたが、
// 使う先が 2 か所になったので独立させた（#1146）。同じテストターゲットなので import は要らない。
//
// - `CircleInstanceLayoutTests`（#1142）: `canvas2DMassive.txt` と型 doc の MSL 宣言
// - `ShaderPreludeLayoutTests`（#1146）: カスタムシェーダへ配る前文の 6 構造体

/// MSL の `struct <名前> { ... }` を読み、フィールドの並びから offset と stride を組み立てる。
///
/// 正規表現で 1 行ずつ舐めるのではなく、`{` から対応する `}` までを取って `;` で割るだけ。
/// おかげで `.metal` の複数行の宣言と、doc コメントに 1 行で書かれた宣言を**同じコードで**読める。
///
/// 「検査が壊れた」と「実装が壊れた」を取り違えないため、読めなかったものは黙って
/// 読み飛ばさず ``ReadError`` を投げる（呼び出し側は拾えた個数も下限で固定している）。
enum MSLStructReader {

    /// MSL のスカラー / ベクタ / 行列型 → (サイズ, アライメント)。
    ///
    /// `float3` が 12 ではなく 16 バイトなのは MSL の仕様（12 バイトが要るときは
    /// `packed_float3`）。表に無い型に出会ったら緑を返さず落とす。
    ///
    /// 行列は**実際に前文へ現れるものだけ**を載せている。`float3x3` は 48 / 16、
    /// `float2x2` は 16 / 8 と列ごとに規則が変わるので、当てずっぽうで足すと
    /// 「検査が黙って嘘をつく」側に倒れる。使う型が増えたら、そのとき実測して足すこと
    /// （`float4x4` の 64 / 16 は `MTLCreateSystemDefaultDevice()` 上の
    /// `static_assert(sizeof(float4x4) == 64 && alignof(float4x4) == 16)` で確認済み）。
    static let knownTypes: [String: (size: Int, alignment: Int)] = [
        "half": (2, 2), "half2": (4, 4), "half3": (8, 8), "half4": (8, 8),
        "float": (4, 4), "float2": (8, 8), "float3": (16, 16), "float4": (16, 16),
        "packed_float3": (12, 4),
        "int": (4, 4), "int2": (8, 8), "int3": (16, 16), "int4": (16, 16),
        "uint": (4, 4), "uint2": (8, 8), "uint3": (16, 16), "uint4": (16, 16),
        "float4x4": (64, 16),
    ]

    struct Field: Sendable {
        let type: String
        let name: String
        let offset: Int
        let size: Int
    }

    struct Layout: Sendable {
        let fields: [Field]
        let stride: Int

        func field(named name: String) -> Field? { fields.first { $0.name == name } }

        /// 失敗メッセージに載せる「実際に読めた並び」。
        var summary: String {
            fields.map { "\($0.type) \($0.name) @\($0.offset)" }.joined(separator: ", ")
        }
    }

    enum ReadError: Error, CustomStringConvertible {
        case unknownFieldType(String)
        case malformedField(String)

        var description: String {
            switch self {
            case .unknownFieldType(let type):
                return """
                    MSL の型 '\(type)' が MSLStructReader.knownTypes に無い。\
                    実装が壊れたのではなく検査が追いついていない — \
                    表にサイズとアライメントを足すこと。
                    """
            case .malformedField(let text):
                return "MSL のフィールド宣言として読めない: '\(text)'"
            }
        }
    }

    /// `source` から `struct <名前> { ... }` を全て探し、それぞれのレイアウトを組み立てる。
    static func layouts(ofStructNamed name: String, in source: String) throws -> [Layout] {
        try bodies(ofStructNamed: name, in: source).map(layout(fromBody:))
    }

    /// 宣言の**本文**（`{` と `}` の間）を全て取り出す。
    static func bodies(ofStructNamed name: String, in source: String) -> [String] {
        let text = strippingLineComments(source)
        let needle = "struct \(name)"
        var bodies: [String] = []
        var search = text.startIndex

        while let found = text.range(of: needle, range: search..<text.endIndex) {
            search = found.upperBound
            // 直後の非空白が `{` でなければ別物（`struct CircleInstanceFoo` や散文の中の言及）。
            guard
                let open = text[found.upperBound...].firstIndex(where: { !$0.isWhitespace }),
                text[open] == "{",
                let close = matchingBrace(in: text, openedAt: open)
            else { continue }

            bodies.append(String(text[text.index(after: open)..<close]))
            search = text.index(after: close)
        }
        return bodies
    }

    private static func layout(fromBody body: String) throws -> Layout {
        var fields: [Field] = []
        var cursor = 0
        var maxAlignment = 1

        for chunk in body.split(separator: ";") {
            let declaration = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if declaration.isEmpty { continue }

            let tokens = declaration.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count == 2 else { throw ReadError.malformedField(declaration) }
            guard let metrics = knownTypes[tokens[0]] else {
                throw ReadError.unknownFieldType(tokens[0])
            }

            let offset = roundUp(cursor, to: metrics.alignment)
            fields.append(
                Field(type: tokens[0], name: tokens[1], offset: offset, size: metrics.size))
            cursor = offset + metrics.size
            maxAlignment = max(maxAlignment, metrics.alignment)
        }

        return Layout(fields: fields, stride: roundUp(cursor, to: maxAlignment))
    }

    /// `//` から行末までを落とす。フェンス付き doc の `// offset 0` 注記も、`.metal` の
    /// 日本語コメントも、これで一律に消える（`{` や `}` を含んでいても巻き込まない）。
    private static func strippingLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let marker = line.range(of: "//") else { return line }
                return line[line.startIndex..<marker.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func matchingBrace(in text: String, openedAt open: String.Index) -> String.Index?
    {
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "{" {
                depth += 1
            } else if text[index] == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func roundUp(_ value: Int, to alignment: Int) -> Int {
        alignment <= 1 ? value : (value + alignment - 1) / alignment * alignment
    }
}
