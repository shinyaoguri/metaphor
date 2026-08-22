import Foundation
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// viewer frame IPC の wire 型（CONTRACT.md 契約点 5）。
//
// 二段構成:  実型 ⊨ 構造 ⊨ contract/examples/viewer-*.json   (このテスト)
//            examples ⊨ schema ⊨ contract/viewer-*.schema.json (scripts/check-contract-schema.sh)
// 推移的に、実エンコーダ出力がスキーマに適合する（contract/README.md「二段検証」）。

@Suite("Viewer frame IPC wire-schema conformance")
struct ViewerFrameIPCConformanceTests {

    private func encodeLine<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try ViewerFrameIPC.encodeLine(value)
        #expect(data.last == 0x0A, "JSON Lines: 末尾は改行")
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private let layout = ViewerFrameLayout(width: 1920, height: 1080, linearAlignment: 256, pageSize: 16384)

    @Test("hello は contract/examples/viewer-hello.json と構造一致し、固定値は仕様どおり")
    func helloMatchesExample() throws {
        let hello = ViewerFrameIPC.Hello(pid: 48213, metaphor: Metaphor.version, layout: layout)
        let encoded = try encodeLine(hello)
        try assertStructurallyEqual(encoded, try loadContractExample("viewer-hello.json"), path: "hello")

        #expect(encoded["t"] as? String == "hello")
        #expect(encoded["protocolVersion"] as? Int == 1)
        #expect(encoded["pixelFormat"] as? String == "bgra8Unorm")
        #expect(encoded["alpha"] as? String == "premultiplied")
        #expect(encoded["colorSpace"] as? String == "sRGB")
        #expect(encoded["orientation"] as? String == "topLeft")
        #expect(encoded["backing"] as? String == "posix-shm")
        #expect(encoded["slots"] as? Int == 3)
        #expect(encoded["bytesPerRow"] as? Int == layout.bytesPerRow)
        #expect(encoded["slotBytes"] as? Int == layout.slotBytes)
        #expect(encoded["width"] as? Int == 1920)
        #expect(encoded["height"] as? Int == 1080)
    }

    @Test("frame は contract/examples/viewer-frame.json と構造一致する")
    func frameMatchesExample() throws {
        let frame = ViewerFrameIPC.Frame(slot: 2, seq: 41, frameCount: 120, time: 2.0166)
        let encoded = try encodeLine(frame)
        try assertStructurallyEqual(encoded, try loadContractExample("viewer-frame.json"), path: "frame")
        #expect(encoded["t"] as? String == "frame")
    }

    @Test("release は contract/examples/viewer-release.json と構造一致する")
    func releaseMatchesExample() throws {
        let encoded = try encodeLine(ViewerFrameIPC.Release(slot: 2))
        try assertStructurallyEqual(encoded, try loadContractExample("viewer-release.json"), path: "release")
        #expect(encoded["t"] as? String == "release")
    }

    @Test("protocolVersion は 1（scripts/check-contract.sh が同じ値を検査する）")
    func protocolVersion() {
        #expect(ViewerFrameIPC.protocolVersion == 1)
    }
}

@Suite("Viewer frame IPC: 受信行の解釈")
struct ViewerFrameIPCDecodingTests {

    @Test("release は slot を取り出す")
    func decodeRelease() {
        #expect(ViewerFrameIPC.decodeIncoming(#"{"t":"release","slot":1}"#) == .release(slot: 1))
    }

    @Test("未知の t は unknown（読み飛ばす側の判断に委ねる）、未知フィールドは無視")
    func forwardCompatibility() {
        #expect(ViewerFrameIPC.decodeIncoming(#"{"t":"pause"}"#) == .unknown("pause"))
        #expect(ViewerFrameIPC.decodeIncoming(#"{"t":"release","slot":2,"extra":true}"#) == .release(slot: 2))
    }

    @Test("不正な行・t 欠落・slot 欠落の release は nil")
    func malformed() {
        #expect(ViewerFrameIPC.decodeIncoming("not json") == nil)
        #expect(ViewerFrameIPC.decodeIncoming(#"{"slot":1}"#) == nil)
        #expect(ViewerFrameIPC.decodeIncoming(#"{"t":"release"}"#) == nil)
    }
}
