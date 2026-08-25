import Metal
import Testing
import simd

@testable import MetaphorCore
@testable import metaphor

/// ``VertexLayout/makeDescriptor()`` が組み立てる `MTLVertexDescriptor` を、**実際にそのバイト列を
/// 書く Swift の頂点構造体**と突き合わせる（#1158）。
///
/// この 2 つはバイト列でだけ結ばれていて、片方だけ動かしてもコンパイルは通り、パイプライン生成も
/// 成功する。`Vertex2D` を `SIMD2` + `SIMD4` のパック構造体へ「読みやすく」直すのは誰でもやる
/// リファクタだが、`SIMD4` のアライメント 16 で color は 8 → 16 へ、stride は 24 → 32 へ動く。
/// デスクリプタが 8 / 24 のままだと **GPU は別のバイトを頂点として読む**。
///
/// 従来の `VertexLayoutTests`（#1158 で削除）は期待値に**実装と同じ式**を書いていたので、
/// 頂点構造体が動いても絶対に赤くならなかった。ここでは
///
/// - offset と stride を `MemoryLayout<構造体>.offset(of:)` / `.stride` から取る（構造体を名指しする）
/// - `format` が読むバイト数が、Swift 側のフィールドが占める幅に収まることを見る
///
/// の 2 本で、実装の算術を写さずに固定する。
///
/// `format` そのものは Swift からは導出できない（`SIMD3<Float>` と `SIMD4<Float>` は stride が
/// 同じ 16 で、「この場は float3 として読む」は型のどこにも書かれていない）ので、下の表が
/// 唯一の表明になる。`float4` → `int4` のようなサイズが同じ取り違えはここで捕まる。
@Suite("VertexLayout ⇄ 頂点構造体")
@MainActor
struct VertexLayoutParityTests {

    // MARK: - 期待の書き方

    /// `MTLVertexFormat` が GPU 側で**実際に読む**バイト数。
    ///
    /// `float3` が 16 ではなく 12 なのは Metal の仕様で、`SIMD3<Float>` の 16 バイトのうち
    /// 先頭 12 バイトだけを読む（残り 4 バイトはアライメントのパディング）。表に無い
    /// フォーマットに出会ったら緑を返さず落とす — 「検査が追いついていない」と
    /// 「実装が壊れた」を取り違えないため。
    static let formatByteSize: [MTLVertexFormat: Int] = [
        .float: 4, .float2: 8, .float3: 12, .float4: 16,
        .half2: 4, .half4: 8,
        .int: 4, .int2: 8, .int3: 12, .int4: 16,
        .uint: 4, .uint2: 8, .uint3: 12, .uint4: 16,
        .uchar4Normalized: 4,
    ]

    /// 1 つの頂点属性に期待するもの。`offset` は Swift 構造体から取った実オフセットを渡す。
    struct Attribute {
        let index: Int
        let format: MTLVertexFormat
        let offset: Int
        /// 失敗メッセージに出す「Swift 側のどのフィールドか」。
        let field: String

        init(_ index: Int, _ format: MTLVertexFormat, _ offset: Int, _ field: String) {
            self.index = index
            self.format = format
            self.offset = offset
            self.field = field
        }
    }

    /// `layout` のデスクリプタが `structName` のバイト列を指していることを確かめる。
    ///
    /// - Parameters:
    ///   - stride: `MemoryLayout<構造体>.stride`。
    ///   - attributes: `index` の昇順、かつ `offset` の昇順で渡すこと。
    private func expectParity(
        _ layout: VertexLayout,
        writtenBy structName: String,
        stride: Int,
        _ attributes: [Attribute],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let descriptor = layout.makeDescriptor()

        for (position, attribute) in attributes.enumerated() {
            let actual: MTLVertexAttributeDescriptor = descriptor.attributes[attribute.index]
            let what =
                ".\(layout) の attributes[\(attribute.index)]"
                + "（\(structName).\(attribute.field)）"

            #expect(
                actual.offset == attribute.offset,
                "\(what)の offset が \(structName) とずれている",
                sourceLocation: sourceLocation)
            #expect(
                actual.format == attribute.format,
                "\(what)の format が想定と違う",
                sourceLocation: sourceLocation)
            #expect(
                actual.bufferIndex == 0,
                "\(what)は頂点バッファ（index 0）から読む",
                sourceLocation: sourceLocation)

            // この属性が使える幅 = 次の属性の先頭まで（最後なら stride の終わりまで）。
            // format が読むバイト数がここに収まらなければ、隣のフィールドを食っている。
            let limit =
                position + 1 < attributes.count ? attributes[position + 1].offset : stride
            let size = try #require(
                Self.formatByteSize[attribute.format],
                "\(actual.format) が VertexLayoutParityTests.formatByteSize に無い",
                sourceLocation: sourceLocation)
            #expect(
                attribute.offset + size <= limit,
                """
                \(what)は \(attribute.offset)..<\(attribute.offset + size) を読むが、\
                \(structName) 側で使えるのは \(attribute.offset)..<\(limit) まで
                """,
                sourceLocation: sourceLocation)
        }

        #expect(
            descriptor.layouts[0].stride == stride,
            ".\(layout) の stride が MemoryLayout<\(structName)>.stride と違う",
            sourceLocation: sourceLocation)
    }

    /// `MemoryLayout.offset(of:)` は `Int?`。nil は「検査が読めなかった」なので、
    /// 0 に潰さず落とす。
    private func offset<Root>(
        of keyPath: PartialKeyPath<Root>,
        _ field: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Int {
        try #require(
            MemoryLayout<Root>.offset(of: keyPath),
            "\(Root.self).\(field) の offset を取れない",
            sourceLocation: sourceLocation)
    }

    // MARK: - CPU 側に構造体があるケース

    @Test("positionNormalColor は Vertex3D のバイト列を指す")
    func positionNormalColorMatchesVertex3D() throws {
        try expectParity(
            .positionNormalColor,
            writtenBy: "Vertex3D",
            stride: MemoryLayout<Vertex3D>.stride,
            [
                Attribute(0, .float3, try offset(of: \Vertex3D.position, "position"), "position"),
                Attribute(1, .float3, try offset(of: \Vertex3D.normal, "normal"), "normal"),
                Attribute(2, .float4, try offset(of: \Vertex3D.color, "color"), "color"),
            ])
    }

    @Test("positionNormalUV は Vertex3DTextured のバイト列を指す")
    func positionNormalUVMatchesVertex3DTextured() throws {
        try expectParity(
            .positionNormalUV,
            writtenBy: "Vertex3DTextured",
            stride: MemoryLayout<Vertex3DTextured>.stride,
            [
                Attribute(
                    0, .float3, try offset(of: \Vertex3DTextured.position, "position"), "position"),
                Attribute(1, .float3, try offset(of: \Vertex3DTextured.normal, "normal"), "normal"),
                Attribute(2, .float2, try offset(of: \Vertex3DTextured.uv, "uv"), "uv"),
            ])
    }

    /// `Canvas2D.Vertex2D` は `Float` を 6 本並べたパック構造体で、`SIMD2` も `SIMD4` も
    /// 含まない。color が 8 から始まるのは「前に `Float` が 2 本あるから」であって
    /// `MemoryLayout<SIMD2<Float>>.stride` が 8 だからではない（#1158）。
    @Test("position2DColor は Canvas2D.Vertex2D のバイト列を指す")
    func position2DColorMatchesVertex2D() throws {
        typealias V = Canvas2D.Vertex2D
        try expectParity(
            .position2DColor,
            writtenBy: "Canvas2D.Vertex2D",
            stride: MemoryLayout<V>.stride,
            [
                Attribute(0, .float2, try offset(of: \V.posX, "posX"), "posX"),
                Attribute(1, .float4, try offset(of: \V.r, "r"), "r"),
            ])
    }

    @Test("position2DTexCoordColor は Canvas2D.TexturedVertex2D のバイト列を指す")
    func position2DTexCoordColorMatchesTexturedVertex2D() throws {
        typealias V = Canvas2D.TexturedVertex2D
        try expectParity(
            .position2DTexCoordColor,
            writtenBy: "Canvas2D.TexturedVertex2D",
            stride: MemoryLayout<V>.stride,
            [
                Attribute(0, .float2, try offset(of: \V.posX, "posX"), "posX"),
                Attribute(1, .float2, try offset(of: \V.u, "u"), "u"),
                Attribute(2, .float4, try offset(of: \V.r, "r"), "r"),
            ])
    }

    /// インスタンシングの単位メッシュは構造体を経由せず `[SIMD2<Float>]` をそのまま
    /// `makeBuffer(bytes:)` へ渡す（``UnitMesh2D/createCircle(device:segments:)`` /
    /// ``UnitMesh2D/createRect(device:)``）。相手は要素型そのもの。
    @Test("position2DOnly は UnitMesh2D の SIMD2<Float> 配列と一致する")
    func position2DOnlyMatchesUnitMeshElement() throws {
        try expectParity(
            .position2DOnly,
            writtenBy: "SIMD2<Float>",
            stride: MemoryLayout<SIMD2<Float>>.stride,
            [Attribute(0, .float2, 0, "self")])
    }

    // MARK: - CPU 側に構造体が無いケース

    /// `.position` と `.positionColor` は `Sources/` のどこからも使われておらず、バイト列を
    /// 書く Swift 構造体が存在しない（`PipelineFactory.swift` の `switch` 以外に参照が無い）。
    /// 突き合わせる相手がいないので、**公開契約としてのバイト数**をここで固定する。
    ///
    /// 値は `float3` を 12 バイトにパックしたものではなく `SIMD3<Float>` の stride（16）に
    /// 揃えてある。`.positionNormalColor` 以下の 3D レイアウトと同じ数え方で、
    /// `Vertex3D` を流せば `.position` / `.positionColor` でも位置と色は正しく読める。
    @Test("position は float3 1 本・stride 16 で固定する")
    func positionKeepsItsPublicByteContract() {
        let descriptor = VertexLayout.position.makeDescriptor()
        #expect(descriptor.attributes[0].format == .float3)
        #expect(descriptor.attributes[0].offset == 0)
        #expect(descriptor.attributes[0].bufferIndex == 0)
        #expect(descriptor.layouts[0].stride == 16)
    }

    @Test("positionColor は float3 + float4・stride 32 で固定する")
    func positionColorKeepsItsPublicByteContract() {
        let descriptor = VertexLayout.positionColor.makeDescriptor()
        #expect(descriptor.attributes[0].format == .float3)
        #expect(descriptor.attributes[0].offset == 0)
        #expect(descriptor.attributes[0].bufferIndex == 0)
        // color は 12 ではなく 16 から始まる（`SIMD3<Float>` の stride に合わせてある）。
        #expect(descriptor.attributes[1].format == .float4)
        #expect(descriptor.attributes[1].offset == 16)
        #expect(descriptor.attributes[1].bufferIndex == 0)
        #expect(descriptor.layouts[0].stride == 32)
    }

    // MARK: - 検査の前提

    /// `Vertex3D` と `Vertex3DTextured` の doc は「``VertexLayout`` に一致するメモリレイアウトを
    /// 持ちます」と宣言している。上の 2 テストがその宣言の実体だが、**両方が同じ 48 バイトに
    /// 落ちている**ことは別に見ておく（3D の頂点バッファは片方をもう片方として読ませても
    /// stride だけでは気付けない）。
    @Test("3D の 2 型は同じ stride で、UV 側は末尾にパディングを持つ")
    func threeDVertexStridesAreConsistent() throws {
        #expect(MemoryLayout<Vertex3D>.stride == 48)
        #expect(MemoryLayout<Vertex3DTextured>.stride == 48)
        // uv（8 バイト）の後ろに 8 バイトのパディングが入って 48 になる。
        #expect(MemoryLayout<Vertex3DTextured>.size == 40)
        let uv = try offset(of: \Vertex3DTextured.uv, "uv")
        #expect(uv + MemoryLayout<SIMD2<Float>>.size < MemoryLayout<Vertex3DTextured>.stride)
    }
}
