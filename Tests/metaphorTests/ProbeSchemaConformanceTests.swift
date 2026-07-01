import Foundation
import Testing
@testable import MetaphorCore

// MARK: - Wire-schema conformance (producer side)
//
// contract/*.schema.json が Probe wire 形式の正典 (案C+、ADR-0004)。CI の
// check-contract-schema.sh が contract/examples/*.json を各スキーマで検証する。
//
// このテストは相補的な半分——「examples が実 Swift 型からドリフトしないこと」を
// 守る番人。実型を構築 → ProbeWriter と同じ encoder 設定でエンコード → 得た JSON の
// **構造**（キー集合と各値の JSON 種別）が対応する example と一致することを assert する。
// 値そのものは比較しない（Float の精度差でフレークするため。値域・enum・const は
// スキーマ側が担う）。GPU 不要（型を直接構築する）。
//
// 二段構成:  実型 ⊨ 構造 ⊨ examples/*.json  (このテスト)
//            examples/*.json ⊨ schema ⊨ *.schema.json  (check-contract-schema.sh)
//            ∴ 推移的に 実エンコーダ出力 ⊨ schema

@Suite("Probe wire-schema conformance")
struct ProbeSchemaConformanceTests {

    // ProbeWriter.writeNamed と同一の encoder 設定。
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func loadExample(_ name: String) throws -> [String: Any] {
        // #filePath = .../metaphor/Tests/metaphorTests/ProbeSchemaConformanceTests.swift
        // → 3 段上がるとリポジトリルート。
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // metaphorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let url = repoRoot
            .appendingPathComponent("contract/examples")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: frame.json

    @Test("frame.json (full) は実 ProbeFrameMetadata と構造一致する")
    func frameFullMatchesExample() throws {
        let metadata = ProbeFrameMetadata(
            schemaVersion: 4,
            id: "01HXYZABCDEF0123456789",
            label: "baseline",
            sourceStamp: "build-abc123",
            frame: 42,
            time: 1.234,
            size: .init(width: 1280, height: 720),
            custom: [
                "particles.count": .int(128),
                "camera.position": .vec3(1.5, 2.0, 3.5),
                "phase": .string("initialization"),
                "enabled": .bool(true),
                "momentum": .double(0.95),
            ],
            customTypes: [
                "particles.count": "int",
                "camera.position": "vec3",
                "phase": "string",
                "enabled": "bool",
                "momentum": "double",
            ],
            warnings: [],
            stats: .init(
                meanColor: [0.5, 0.5, 0.5],
                meanLuminance: 0.5,
                contentFraction: 0.75,
                contentBounds: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.6),
                sampleGrid: 32
            )
        )
        try assertStructurallyEqual(encode(metadata), loadExample("frame.json"), path: "frame")
    }

    @Test("frame.json (minimal) は optional 省略時の構造と一致する")
    func frameMinimalMatchesExample() throws {
        // label / sourceStamp / stats を nil にすると JSONEncoder はキー自体を省略する。
        let metadata = ProbeFrameMetadata(
            schemaVersion: 4,
            id: "01HXYZABCDEF0123456789",
            label: nil,
            sourceStamp: nil,
            frame: 0,
            time: 0.0,
            size: .init(width: 640, height: 480),
            custom: [:],
            customTypes: [:],
            warnings: ["frame appears nearly blank (variance=0.000001)"],
            stats: nil
        )
        try assertStructurallyEqual(encode(metadata), loadExample("frame-minimal.json"), path: "frame-minimal")
    }

    // MARK: request.json

    @Test("request.json (full) は実 ProbeRequest と構造一致する")
    func requestFullMatchesExample() throws {
        let request = ProbeRequest(id: "01HXYZABCDEF0123456789", label: "baseline", scale: 1.0, frames: 8, every: 2)
        try assertStructurallyEqual(encode(request), loadExample("request.json"), path: "request")
    }

    @Test("request.json (minimal) は id のみの構造と一致する")
    func requestMinimalMatchesExample() throws {
        let request = ProbeRequest(id: "01HXYZABCDEF0123456789", label: nil, scale: nil, frames: nil, every: nil)
        try assertStructurallyEqual(encode(request), loadExample("request-minimal.json"), path: "request-minimal")
    }

    // MARK: sequence.json

    @Test("sequence.json は実 ProbeSequenceManifest と構造一致する")
    func sequenceMatchesExample() throws {
        let manifest = ProbeSequenceManifest(
            schemaVersion: 1,
            id: "01HXYZABCDEF0123456789",
            label: "motion",
            frameCount: 2,
            requestedFrames: 8,
            every: 2,
            size: .init(width: 640, height: 480),
            contactSheet: "contact_sheet.png",
            warnings: ["frames clamped from 8 to 2"],
            frames: [
                .init(index: 0, file: "frame.0000.png", metadata: "frame.0000.json", frame: 100, time: 0.0),
                .init(index: 1, file: "frame.0001.png", metadata: "frame.0001.json", frame: 102, time: 0.033),
            ]
        )
        try assertStructurallyEqual(encode(manifest), loadExample("sequence.json"), path: "sequence")
    }
}

// MARK: - Structural comparison

/// JSON 値の「種別」。値そのものではなく形だけを比較するために使う。
private func jsonKind(_ value: Any) -> String {
    if value is NSNull { return "null" }
    if let number = value as? NSNumber {
        // JSONSerialization は Bool を NSNumber(CFBoolean) として返すため区別する。
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return "bool" }
        return "number"
    }
    if value is String { return "string" }
    if value is [Any] { return "array" }
    if value is [String: Any] { return "object" }
    return "unknown(\(type(of: value)))"
}

/// `actual`（実エンコーダ出力）と `expected`（committed example）が **構造的に**
/// 一致する（同じキー集合・同じ JSON 種別）ことを再帰的に検証する。値は比較しない。
private func assertStructurallyEqual(_ actual: Any, _ expected: Any, path: String) throws {
    let ak = jsonKind(actual)
    let ek = jsonKind(expected)
    #expect(ak == ek, "\(path): JSON 種別が不一致 (encoder=\(ak) example=\(ek))")
    guard ak == ek else { return }

    switch ak {
    case "object":
        let a = actual as! [String: Any]
        let e = expected as! [String: Any]
        let aKeys = Set(a.keys)
        let eKeys = Set(e.keys)
        #expect(aKeys == eKeys,
                "\(path): キー集合が不一致 — encoder のみ=\(aKeys.subtracting(eKeys).sorted()) example のみ=\(eKeys.subtracting(aKeys).sorted())")
        for key in aKeys.intersection(eKeys).sorted() {
            try assertStructurallyEqual(a[key]!, e[key]!, path: "\(path).\(key)")
        }
    case "array":
        let a = actual as! [Any]
        let e = expected as! [Any]
        // 配列は要素の種別だけを代表要素で確認する（長さは値域なのでスキーマ側の責務）。
        if let af = a.first, let ef = e.first {
            try assertStructurallyEqual(af, ef, path: "\(path)[0]")
        }
    default:
        break
    }
}
