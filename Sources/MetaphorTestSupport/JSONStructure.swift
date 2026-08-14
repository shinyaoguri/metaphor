import Foundation
import Testing

// MARK: - Wire-schema conformance helpers
//
// contract/*.schema.json が wire 形式の正典（ADR-0004）。適合テストは
// 「実 Swift 型のエンコード結果」と「committed example」の **構造** が一致すること
// （= examples が実型からドリフトしないこと）を守る。値そのものは比較しない
// （Float の精度差でフレークするため。値域・enum・const はスキーマ側の責務）。

/// JSON 値の「種別」。値そのものではなく形だけを比較するために使う。
public func jsonKind(_ value: Any) -> String {
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
public func assertStructurallyEqual(_ actual: Any, _ expected: Any, path: String) throws {
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

/// `contract/examples/<name>` を読み込みます（リポジトリルートからの相対パス）。
///
/// - Parameter repoRootRelativeTo: 呼び出し元のソースファイルパス（`#filePath`）。
///   `Tests/<TestTarget>/Foo.swift` から 3 段上がるとリポジトリルート。
public func loadContractExample(
    _ name: String, repoRootRelativeTo sourceFile: String = #filePath
) throws -> [String: Any] {
    let repoRoot = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()  // テストターゲット
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = repoRoot
        .appendingPathComponent("contract/examples")
        .appendingPathComponent(name)
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
