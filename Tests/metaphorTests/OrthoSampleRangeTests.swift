import Foundation
import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - サンプルコードが渡す ortho() の範囲 (#903)

/// `ortho()` に `bottom > top` を渡すと絵が上下反転する。実装（#777 で直した省略時の
/// 範囲）は ``OrthoDefaultBoundsTests`` が守っているが、**範囲を明示するサンプルコードは
/// そこを通らない**。実際、リファレンスのスニペットとチュートリアルの example が
/// 反転したまま残っていた（どちらも上下対称に近い題材で気付きにくい）。
///
/// ここでは反転する書き方が `Sources/` と `Examples/` に残っていないことを機械的に見る。
@Suite("ortho() のサンプルが渡す範囲")
struct OrthoSampleRangeTests {

    /// `ortho(...)` 1 回ぶんの `bottom:` / `top:` の式。
    struct Range: Equatable {
        var bottom: String
        var top: String
    }

    @Test("Sources / Examples のサンプルが ortho() に bottom > top を渡していない (regression #903)")
    func samplesDoNotFlipTheVerticalRange() throws {
        // テストリソース経由ではなくソースツリーを直接見る（LogConventionTests と同じ方針）。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/metaphorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // リポジトリルート

        var inspected = 0
        var offenders: [String] = []
        for directory in ["Sources", "Examples"] {
            let base = root.appendingPathComponent(directory, isDirectory: true)
            try #require(FileManager.default.fileExists(atPath: base.path))
            let files = try #require(
                FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension == "swift" {
                guard !url.path.contains("/.build/") else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      text.contains("ortho(") else { continue }
                for range in Self.orthoRanges(in: text) {
                    inspected += 1
                    guard Self.isFlipped(range) else { continue }
                    let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                    offenders.append("\(path): bottom: \(range.bottom), top: \(range.top)")
                }
            }
        }

        // 拾えた件数も見る（パーサが壊れて 0 件になると、上の判定が黙って素通りするため）。
        #expect(inspected >= 3, "bottom/top を明示した呼び出しを拾えていない: \(inspected) 件")
        #expect(offenders.isEmpty, """
            上下が反転する範囲（bottom > top）を渡している。符号を入れ替えるか、省略時の
            範囲でよければ ortho() だけにする(#903):
            \(offenders.joined(separator: "\n"))
            """)
    }

    // 境界: doc コメントの中・行をまたぐ呼び出しからも拾えること、
    // シンボルリンク（``ortho(left:right:bottom:top:near:far:)``）や宣言そのものを
    // 範囲として数えないこと。パーサが本体なので、ここを外すと上の検査が意味を失う。
    @Test("パーサは doc コメントと複数行の呼び出しから範囲だけを拾う")
    func parserPicksUpOnlyRealRanges() {
        let sample = """
            /// ``ortho(left:right:bottom:top:near:far:)`` と同じ配置です。
            ///
            ///       ortho(
            ///           left: -width / 2,
            ///           right: width / 2,
            ///           bottom: height / 2,
            ///           top: -height / 2
            ///       )
            public func ortho(
                left: Float? = nil, right: Float? = nil,
                bottom: Float? = nil, top: Float? = nil
            ) {
                context.ortho(left: left, right: right, bottom: bottom, top: top)
            }
            ortho(left: -w, right: w, bottom: -h, top: h)
            """
        let ranges = Self.orthoRanges(in: sample)
        #expect(ranges == [
            Range(bottom: "height / 2", top: "-height / 2"),
            Range(bottom: "-h", top: "h"),
        ], "実測 \(ranges)")
        #expect(ranges.map(Self.isFlipped) == [true, false])
    }

    // MARK: - パーサ

    /// `ortho(` の呼び出しから、値を明示している `bottom:` / `top:` の組を取り出す。
    ///
    /// doc コメントのスニペットも対象なので、行頭の `///` を落としてから見る。
    /// 引数が行をまたぐため、`ortho(` から対応する `)` までを 1 本の文字列として扱う。
    static func orthoRanges(in text: String) -> [Range] {
        let stripped = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                return trimmed.hasPrefix("///") ? String(trimmed.dropFirst(3)) : String(line)
            }
            .joined(separator: "\n")

        var ranges: [Range] = []
        var cursor = stripped.startIndex
        while let call = stripped.range(of: "ortho(", range: cursor..<stripped.endIndex) {
            cursor = call.upperBound
            guard let close = matchingParenthesis(in: stripped, after: call.upperBound) else { break }
            let arguments = String(stripped[call.upperBound..<close])
            cursor = stripped.index(after: close)
            guard let bottom = argument("bottom", in: arguments),
                  let top = argument("top", in: arguments),
                  isValueExpression(bottom), isValueExpression(top)
            else { continue }
            ranges.append(Range(bottom: bottom, top: top))
        }
        return ranges
    }

    /// 開き括弧の次から数えて、対応する閉じ括弧の位置。
    private static func matchingParenthesis(
        in text: String, after start: String.Index
    ) -> String.Index? {
        var depth = 1
        var index = start
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// `name:` に続く 1 引数ぶんの式（次のカンマか閉じ括弧まで）。
    private static func argument(_ name: String, in arguments: String) -> String? {
        guard let label = arguments.range(of: "\(name):") else { return nil }
        let value = arguments[label.upperBound...].prefix { $0 != "," && $0 != ")" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 値として書かれた式か（シンボルリンクの断片・宣言・素通しの転送を除く）。
    private static func isValueExpression(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(":") && !value.contains("Float")
            && value != "bottom" && value != "top"
    }

    /// 上下が反転する組み合わせ（`top` だけが負 = `bottom > top`）。
    static func isFlipped(_ range: Range) -> Bool {
        range.top.hasPrefix("-") && !range.bottom.hasPrefix("-")
    }
}

// MARK: - 明示範囲と y の向き (#903)

/// 上の検査が「反転」と呼んでいるものが実際に絵の上下を反転させることを、
/// 投影の実測で裏付ける（#777 のコメントで測った値と同じ形）。
@Suite("ortho() の明示範囲と y の向き", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct OrthoExplicitRangeDirectionTests {

    /// 既定カメラは `begin()` で入るので、必ず 1 フレーム開始しておく。
    private func makeCanvas() throws -> Canvas3D {
        let renderer = try MetaphorRenderer(width: 1280, height: 720)
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.begin(encoder: nil, time: 0)
        return canvas3D
    }

    /// ワールドの y を +160 動かしたときの、画面 y の変化。
    private func yShift(_ canvas3D: Canvas3D) -> Float {
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2
        return canvas3D.screenPosition(cx, cy + 80, 0).y
            - canvas3D.screenPosition(cx, cy - 80, 0).y
    }

    @Test("bottom < top は透視投影と同じ向き、bottom > top はちょうど反転する (#903)")
    func explicitRangeDecidesTheDirection() throws {
        let canvas3D = try makeCanvas()
        let w = canvas3D.width
        let h = canvas3D.height

        let perspective = yShift(canvas3D)   // 既定は透視投影
        canvas3D.ortho(left: -w / 2, right: w / 2, bottom: -h / 2, top: h / 2)
        let upright = yShift(canvas3D)
        canvas3D.ortho(left: -w / 2, right: w / 2, bottom: h / 2, top: -h / 2)
        let flipped = yShift(canvas3D)

        #expect(perspective > 0, "透視投影ではワールド +y が画面下向き (実測 \(perspective))")
        #expect(abs(upright - perspective) < 0.01,
                "bottom < top は透視投影と同じ向き (実測 \(upright) / 基準 \(perspective))")
        #expect(abs(flipped + perspective) < 0.01,
                "bottom > top は符号だけが逆になる (実測 \(flipped) / 基準 \(perspective))")
    }
}
