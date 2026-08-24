import Foundation
import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - CircleInstance Layout Tests

@Suite("CircleInstance Layout")
struct CircleInstanceLayoutTests {

    @Test("CircleInstance is 32 bytes with 16-byte alignment")
    func layout() {
        #expect(MemoryLayout<CircleInstance>.stride == 32)
        #expect(MemoryLayout<CircleInstance>.alignment == 16)
    }

    /// `circles(_ instances: GPUBuffer<CircleInstance>, count:)` は渡されたバイト列を
    /// そのままインスタンスとして解釈するので、フィールドの offset は
    /// `MetaphorCanvas2DMassive.metal` の `struct CircleInstance` との契約であり、
    /// `CircleInstance` の doc コメントが「そのまま貼れる MSL 定義」として公開している値でもある。
    ///
    /// stride と alignment だけでは守れない: 宣言順を doc の並び（アルファベット順:
    /// color / diameter / position）へ入れ替えても stride 32 / alignment 16 は変わらず、
    /// 上の `layout()` は緑のまま通る。offset を固定して初めて、宣言順が動いた瞬間に赤くなる（#1090）。
    @Test("フィールドの offset が MSL 側の struct と doc コメントの表に一致する")
    func fieldOffsets() {
        #expect(MemoryLayout<CircleInstance>.offset(of: \.position) == 0)
        #expect(MemoryLayout<CircleInstance>.offset(of: \.diameter) == 8)
        #expect(MemoryLayout<CircleInstance>.offset(of: \._padding) == 12)
        #expect(MemoryLayout<CircleInstance>.offset(of: \.color) == 16)
    }

    @Test("CircleInstance stores position, diameter, and color")
    func fields() {
        let inst = CircleInstance(
            position: SIMD2<Float>(10, 20),
            diameter: 8,
            color: SIMD4<Float>(1, 0, 0, 1)
        )
        #expect(inst.position == SIMD2<Float>(10, 20))
        #expect(inst.diameter == 8)
        #expect(inst.color == SIMD4<Float>(1, 0, 0, 1))
    }

    // MARK: - Swift ↔ MSL の一致（#1142）

    /// 実行時に GPU が食べる MSL と、Swift の実レイアウトを突き合わせる。
    ///
    /// 上の `fieldOffsets()` が守るのは**契約の片側だけ**で、相方の `.metal` を並べ替えても
    /// そこは緑のまま通る。#1142 で実測したところ、`.metal` 単独の並べ替えは既存の描画テスト
    /// （`Canvas2DMassiveRenderTests` ほか 6 件）が絵として拾ってはいた。ただしそれは
    /// `.enabled(if: MetalTestHelper.isGPUAvailable)` 配下の**偶発的な**守りで、
    ///
    /// - GPU が見えない環境ではまるごと skip され、契約を見る目が 1 つも残らない
    /// - 落ちたときに出るのは `red.r > 200 → false` が 5 本で、
    ///   「MSL の struct がずれた」とはどこにも書いていない
    ///
    /// ここは GPU を使わずに契約そのものを見るので、どちらも起きない。
    @Test("実行時にコンパイルされる MSL の struct が Swift の実レイアウトと一致する")
    func shaderSourceMatchesSwiftLayout() throws {
        // 読むのは `.metal` ではなく生成物の `.txt`（= 実際に `makeLibrary(source:)` へ渡る
        // 文字列）。`.metal` → `.txt` のバイト一致は generate-shader-sources.py --check が
        // pre-push と CI の両方で守っているので、正典を迂回することにはならない。
        let source = try #require(ShaderLibrary.loadShaderSource("canvas2DMassive"))
        let layouts = try MSLStructReader.layouts(ofStructNamed: "CircleInstance", in: source)

        // 個数の下限は「リーダが何も拾えなくなって常に緑」への保険。
        #expect(
            layouts.count == 1,
            "canvas2DMassive.txt から struct CircleInstance を 1 つ読めるはずが \(layouts.count) 個だった")

        for layout in layouts {
            Self.expectMatchesSwiftLayout(layout, origin: "canvas2DMassive.txt")
        }
    }

    /// 型 doc が「そのまま貼れる MSL 定義」として公開している宣言も、同じ真実の一部として固定する。
    ///
    /// #1090 で doc に定義を載せた結果、`.metal` を動かすと**公開ドキュメントが黙って嘘になる**
    /// 経路ができた。#1142 の実測では、フェンス付きコードブロックだけをアルファベット順の嘘に
    /// 書き換えても `make ci-check` が exit 0 で通る（`.metal` は無傷なので描画テストは緑、
    /// フェンス付きブロックは llms.txt に出力されないので鮮度検査も緑）。
    /// **ユーザーが実際にコピペするのはそのブロック**なので、ここが一番守られていなかった。
    ///
    /// doc コメント行だけを取り出して読むので、フェンス付きの複数行版と `- Important:` の
    /// 1 行版の**両方**が引っかかる。後者は llms.txt にもそのまま出るため、生成物側の文字列も
    /// 間接的に固定される。
    @Test("型 doc に載せた MSL 定義が Swift の実レイアウトと一致する")
    func documentedMSLDeclarationMatchesSwiftLayout() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/metaphorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // リポジトリルート
            .appendingPathComponent("Sources/MetaphorCore/Drawing/Canvas2DMassive.swift")
        try #require(FileManager.default.fileExists(atPath: file.path))

        // `///` の行だけを残す。Swift 側の `public struct CircleInstance: Sendable, Equatable`
        // 本体を MSL として読み込まないための足切りでもある。
        let docComment = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("///") }
            .map { String($0.dropFirst(3)) }
            .joined(separator: "\n")

        let layouts = try MSLStructReader.layouts(ofStructNamed: "CircleInstance", in: docComment)

        // フェンス付きブロックと `- Important:` の 1 行版で 2 つ。減ったらリーダが
        // 拾えなくなったか、doc から定義が消えたかのどちらかで、どちらも見過ごせない。
        #expect(
            layouts.count >= 2,
            """
            Canvas2DMassive.swift の doc コメントから struct CircleInstance を \
            2 つ以上読めるはずが \(layouts.count) 個だった\
            （フェンス付きブロックと - Important: の 1 行版）
            """)

        for (index, layout) in layouts.enumerated() {
            Self.expectMatchesSwiftLayout(layout, origin: "型 doc の MSL 宣言 #\(index + 1)")
        }
    }

    /// MSL 宣言 1 つ分を `MemoryLayout<CircleInstance>` の実測値と突き合わせる。
    ///
    /// `_pad` は名前で要求しない。doc 自身が「省いてもよい」と書いているとおり、`float4` の
    /// 16 バイト境界があるので `_pad` の有無で公開プロパティの offset は変わらないため。
    /// 代わりに全体の stride を見ることで、余計な穴や末尾の増減は拾える。
    ///
    /// offset と stride だけでは**型の取り違えを拾えない**ので、MSL の型名も突き合わせる。
    /// `float4 color` → `float3 color` は MSL でも 16 バイト（float3 は 12 ではなく 16）なので
    /// offset 16 / stride 32 のまま通ってしまうし、`int4 color` に至ってはバイト幅まで同じで
    /// 解釈だけが変わる。型名を固定して初めてどちらも赤くなる。
    private static func expectMatchesSwiftLayout(
        _ layout: MSLStructReader.Layout, origin: String
    ) {
        #expect(
            layout.stride == MemoryLayout<CircleInstance>.stride,
            """
            \(origin): MSL の stride は \(layout.stride) だが Swift は \
            \(MemoryLayout<CircleInstance>.stride)（読めた並び: \(layout.summary)）
            """)

        let expected: [(name: String, offset: Int?, type: String, size: Int)] = [
            (
                "position", MemoryLayout<CircleInstance>.offset(of: \.position),
                "float2", MemoryLayout<SIMD2<Float>>.size
            ),
            (
                "diameter", MemoryLayout<CircleInstance>.offset(of: \.diameter),
                "float", MemoryLayout<Float>.size
            ),
            (
                "color", MemoryLayout<CircleInstance>.offset(of: \.color),
                "float4", MemoryLayout<SIMD4<Float>>.size
            ),
        ]

        for entry in expected {
            guard let field = layout.field(named: entry.name) else {
                Issue.record(
                    "\(origin): MSL の struct に \(entry.name) が無い（読めた並び: \(layout.summary)）")
                continue
            }
            #expect(
                field.offset == entry.offset,
                """
                \(origin): \(entry.name) は MSL で offset \(field.offset) だが Swift は \
                \(entry.offset.map(String.init) ?? "nil")（読めた並び: \(layout.summary)）
                """)
            #expect(
                field.type == entry.type,
                """
                \(origin): \(entry.name) の MSL の型は \(field.type) だが \
                \(entry.type) であるべき（読めた並び: \(layout.summary)）
                """)
            // 型表と Swift 側のサイズが食い違ったら、それは検査側の取り違え。
            #expect(
                field.size == entry.size,
                """
                \(origin): \(entry.name) は MSL の \(field.type) が \(field.size) バイト、Swift は \
                \(entry.size) バイト — MSLStructReader.knownTypes を疑うこと
                """)
        }
    }
}

// MARK: - MSL Struct Reader

/// MSL の `struct <名前> { ... }` を読み、フィールドの並びから offset と stride を組み立てる。
///
/// 正規表現で 1 行ずつ舐めるのではなく、`{` から対応する `}` までを取って `;` で割るだけ。
/// おかげで `.metal` の複数行の宣言と、doc コメントに 1 行で書かれた宣言を**同じコードで**読める。
///
/// 「検査が壊れた」と「実装が壊れた」を取り違えないため、読めなかったものは黙って
/// 読み飛ばさず ``ReadError`` を投げる（呼び出し側は拾えた個数も下限で固定している）。
enum MSLStructReader {

    /// MSL のスカラー / ベクタ型 → (サイズ, アライメント)。
    ///
    /// `float3` が 12 ではなく 16 バイトなのは MSL の仕様（12 バイトが要るときは
    /// `packed_float3`）。表に無い型に出会ったら緑を返さず落とす。
    static let knownTypes: [String: (size: Int, alignment: Int)] = [
        "half": (2, 2), "half2": (4, 4), "half3": (8, 8), "half4": (8, 8),
        "float": (4, 4), "float2": (8, 8), "float3": (16, 16), "float4": (16, 16),
        "packed_float3": (12, 4),
        "int": (4, 4), "int2": (8, 8), "int3": (16, 16), "int4": (16, 16),
        "uint": (4, 4), "uint2": (8, 8), "uint3": (16, 16), "uint4": (16, 16),
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

// MARK: - Shader Registration

@Suite("Canvas2D Massive Shaders", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas2DMassiveShaderTests {

    @Test("source shader compiles and exposes expected functions")
    func sourceShaderCompiles() throws {
        let device = MetalTestHelper.device!
        let source = try #require(ShaderLibrary.loadShaderSource("canvas2DMassive"))
        let lib = try device.makeLibrary(source: source, options: nil)

        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.circleVertexFunctionName) != nil)
        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.fragmentFunctionName) != nil)
        #expect(
            lib.makeFunction(name: Canvas2DMassiveShaders.differenceFragmentFunctionName) != nil)
        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.exclusionFragmentFunctionName) != nil)
    }

    @Test("ShaderLibrary registers canvas2DMassive")
    func shaderLibraryRegistration() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()

        #expect(shaderLib.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2DMassive))
        #expect(
            shaderLib.function(
                named: Canvas2DMassiveShaders.circleVertexFunctionName,
                from: ShaderLibrary.BuiltinKey.canvas2DMassive
            ) != nil)
        #expect(
            shaderLib.function(
                named: Canvas2DMassiveShaders.fragmentFunctionName,
                from: ShaderLibrary.BuiltinKey.canvas2DMassive
            ) != nil)
    }

    @Test("Canvas2D initializes massive circle pipelines")
    func canvasInitializesPipelines() throws {
        let canvas = try MetalTestHelper.canvas2D(width: 64, height: 64)
        // massive 系パイプラインは全ブレンドモード分そろっている（#646 で store へ移譲）。
        #expect(
            BlendMode.allCases.allSatisfy {
                canvas.pipelineStore.state(for: Canvas2DPipelineKey(.massiveCircle, $0)) != nil
            })
    }
}

// MARK: - Render Tests

@Suite("Canvas2D Massive Circles Rendering", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas2DMassiveRenderTests {

    @Test("array circles render per-instance colors")
    func arrayCirclesRender() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.circles([
                CircleInstance(x: 16, y: 32, diameter: 18, color: .red),
                CircleInstance(x: 48, y: 32, diameter: 18, color: .green),
            ])
        }

        let red = helper.readPixel(x: 16, y: 32)
        #expect(
            red.r > 200 && red.g < 50 && red.b < 50,
            "Expected red circle: R=\(red.r) G=\(red.g) B=\(red.b)")

        let green = helper.readPixel(x: 48, y: 32)
        #expect(
            green.g > 200 && green.r < 50 && green.b < 50,
            "Expected green circle: R=\(green.r) G=\(green.g) B=\(green.b)")
    }

    @Test("GPUBuffer circles render without CPU staging copy")
    func gpuBufferCirclesRender() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        let buffer = try #require(
            GPUBuffer<CircleInstance>(
                device: helper.device,
                data: [
                    CircleInstance(x: 32, y: 32, diameter: 24, color: .blue)
                ]))

        try helper.render { canvas in
            canvas.noStroke()
            canvas.circles(buffer)
        }

        let center = helper.readPixel(x: 32, y: 32)
        #expect(
            center.b > 200 && center.r < 50 && center.g < 50,
            "Expected blue circle: R=\(center.r) G=\(center.g) B=\(center.b)")
    }

    @Test("circles preserve order with regular Canvas2D batches")
    func preservesOrderWithRegularBatches() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.fill(.white)
            canvas.rect(24, 24, 16, 16)
            canvas.circles([
                CircleInstance(x: 32, y: 32, diameter: 28, color: .red)
            ])
            canvas.fill(.green)
            canvas.rect(30, 30, 4, 4)
        }

        let center = helper.readPixel(x: 32, y: 32)
        #expect(
            center.g > 200 && center.r < 50 && center.b < 50,
            "Last rect should cover circles: R=\(center.r) G=\(center.g) B=\(center.b)")

        let ring = helper.readPixel(x: 32, y: 22)
        #expect(
            ring.r > 200 && ring.g < 50 && ring.b < 50,
            "Circle should cover earlier rect outside final rect: R=\(ring.r) G=\(ring.g) B=\(ring.b)"
        )
    }

    @Test("circles respect current transform")
    func respectsTransform() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.translate(10, 0)
            canvas.circles([
                CircleInstance(x: 22, y: 32, diameter: 16, color: .white)
            ])
        }

        let translatedCenter = helper.readPixel(x: 32, y: 32)
        #expect(translatedCenter.r > 200 && translatedCenter.g > 200 && translatedCenter.b > 200)

        let originalCenter = helper.readPixel(x: 22, y: 32)
        #expect(originalCenter.r < 50 && originalCenter.g < 50 && originalCenter.b < 50)
    }
}
