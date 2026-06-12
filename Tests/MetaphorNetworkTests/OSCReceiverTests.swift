import Testing
@testable import MetaphorNetwork
import Foundation

// MARK: - OSC Binary Helpers

/// OSC バイナリメッセージ構築用ヘルパー
private enum OSCBinaryHelper {

    /// 4バイトアラインメントしたサイズ
    static func aligned(_ size: Int) -> Int {
        (size + 3) & ~3
    }

    /// null 終端 + 4バイトアラインメントされた文字列をバイト列に追加
    static func appendOSCString(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
        let paddingCount = aligned(string.utf8.count + 1) - string.utf8.count
        data.append(contentsOf: [UInt8](repeating: 0, count: paddingCount))
    }

    /// Big-endian Int32 をバイト列に追加
    static func appendInt32(_ value: Int32, to data: inout Data) {
        var bigEndian = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &bigEndian) { Array($0) })
    }

    /// Big-endian Float32 をバイト列に追加
    static func appendFloat32(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &bits) { Array($0) })
    }
}

// MARK: - OSC Parser Tests

@Suite("OSC Parser")
struct OSCParserTests {

    // MARK: - Single Message Tests

    @Test("parse int message")
    func parseIntMessage() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/test", to: &data)
        OSCBinaryHelper.appendOSCString(",i", to: &data)
        OSCBinaryHelper.appendInt32(42, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].address == "/test")
        #expect(messages[0].values.count == 1)
        if case .int(let v) = messages[0].values[0] {
            #expect(v == 42)
        } else {
            Issue.record("Expected .int value")
        }
    }

    @Test("parse float message")
    func parseFloatMessage() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/volume", to: &data)
        OSCBinaryHelper.appendOSCString(",f", to: &data)
        OSCBinaryHelper.appendFloat32(0.75, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].address == "/volume")
        if case .float(let v) = messages[0].values[0] {
            #expect(abs(v - 0.75) < 0.001)
        } else {
            Issue.record("Expected .float value")
        }
    }

    @Test("parse string message")
    func parseStringMessage() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/name", to: &data)
        OSCBinaryHelper.appendOSCString(",s", to: &data)
        OSCBinaryHelper.appendOSCString("hello", to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        if case .string(let v) = messages[0].values[0] {
            #expect(v == "hello")
        } else {
            Issue.record("Expected .string value")
        }
    }

    @Test("parse blob message")
    func parseBlobMessage() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/data", to: &data)
        OSCBinaryHelper.appendOSCString(",b", to: &data)
        let blobData: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        OSCBinaryHelper.appendInt32(Int32(blobData.count), to: &data)
        data.append(contentsOf: blobData)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        if case .blob(let v) = messages[0].values[0] {
            #expect(v.count == 4)
            #expect([UInt8](v) == blobData)
        } else {
            Issue.record("Expected .blob value")
        }
    }

    @Test("negative blob size is ignored without trapping")
    func negativeBlobSize() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/data", to: &data)
        OSCBinaryHelper.appendOSCString(",b", to: &data)
        OSCBinaryHelper.appendInt32(-1, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].values.isEmpty)
    }

    @Test("parse multiple values")
    func parseMultipleValues() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/multi", to: &data)
        OSCBinaryHelper.appendOSCString(",ifs", to: &data)
        OSCBinaryHelper.appendInt32(100, to: &data)
        OSCBinaryHelper.appendFloat32(3.14, to: &data)
        OSCBinaryHelper.appendOSCString("world", to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].values.count == 3)

        if case .int(let v) = messages[0].values[0] {
            #expect(v == 100)
        } else { Issue.record("Expected .int") }

        if case .float(let v) = messages[0].values[1] {
            #expect(abs(v - 3.14) < 0.01)
        } else { Issue.record("Expected .float") }

        if case .string(let v) = messages[0].values[2] {
            #expect(v == "world")
        } else { Issue.record("Expected .string") }
    }

    @Test("parse no-arg message")
    func parseNoArgMessage() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/ping", to: &data)
        OSCBinaryHelper.appendOSCString(",", to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].address == "/ping")
        #expect(messages[0].values.count == 0)
    }

    @Test("parse message without type tags")
    func parseMessageWithoutTypeTags() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/bare", to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].address == "/bare")
        #expect(messages[0].values.count == 0)
    }

    // MARK: - Bundle Tests

    @Test("parse bundle with one message")
    func parseBundleWithOneMessage() {
        var bundle = Data()
        bundle.append(contentsOf: "#bundle".utf8)
        bundle.append(0)
        bundle.append(contentsOf: [UInt8](repeating: 0, count: 8))

        var msg = Data()
        OSCBinaryHelper.appendOSCString("/bundled", to: &msg)
        OSCBinaryHelper.appendOSCString(",i", to: &msg)
        OSCBinaryHelper.appendInt32(99, to: &msg)

        OSCBinaryHelper.appendInt32(Int32(msg.count), to: &bundle)
        bundle.append(msg)

        let messages = OSCParser.parse(data: bundle)
        #expect(messages.count == 1)
        #expect(messages[0].address == "/bundled")
        if case .int(let v) = messages[0].values[0] {
            #expect(v == 99)
        } else { Issue.record("Expected .int") }
    }

    @Test("parse bundle with multiple messages")
    func parseBundleWithMultipleMessages() {
        var bundle = Data()
        bundle.append(contentsOf: "#bundle".utf8)
        bundle.append(0)
        bundle.append(contentsOf: [UInt8](repeating: 0, count: 8))

        var msg1 = Data()
        OSCBinaryHelper.appendOSCString("/a", to: &msg1)
        OSCBinaryHelper.appendOSCString(",i", to: &msg1)
        OSCBinaryHelper.appendInt32(1, to: &msg1)
        OSCBinaryHelper.appendInt32(Int32(msg1.count), to: &bundle)
        bundle.append(msg1)

        var msg2 = Data()
        OSCBinaryHelper.appendOSCString("/b", to: &msg2)
        OSCBinaryHelper.appendOSCString(",f", to: &msg2)
        OSCBinaryHelper.appendFloat32(2.5, to: &msg2)
        OSCBinaryHelper.appendInt32(Int32(msg2.count), to: &bundle)
        bundle.append(msg2)

        let messages = OSCParser.parse(data: bundle)
        #expect(messages.count == 2)
        #expect(messages[0].address == "/a")
        #expect(messages[1].address == "/b")
    }

    // MARK: - Edge Cases

    @Test("empty data returns no messages")
    func emptyData() {
        let messages = OSCParser.parse(data: Data())
        #expect(messages.count == 0)
    }

    @Test("malformed bundle size is ignored without trapping")
    func malformedBundleSize() {
        var data = Data()
        data.append(contentsOf: "#bundle".utf8)
        data.append(0)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        OSCBinaryHelper.appendInt32(-1, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.isEmpty)
    }

    @Test("negative int value")
    func negativeInt() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/neg", to: &data)
        OSCBinaryHelper.appendOSCString(",i", to: &data)
        OSCBinaryHelper.appendInt32(-123, to: &data)

        let messages = OSCParser.parse(data: data)
        if case .int(let v) = messages[0].values[0] {
            #expect(v == -123)
        } else { Issue.record("Expected .int") }
    }

    @Test("long address pattern")
    func longAddress() {
        let longAddr = "/this/is/a/very/long/osc/address/pattern"
        var data = Data()
        OSCBinaryHelper.appendOSCString(longAddr, to: &data)
        OSCBinaryHelper.appendOSCString(",f", to: &data)
        OSCBinaryHelper.appendFloat32(1.0, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].address == longAddr)
    }
}

// MARK: - OSC Value Tests

@Suite("OSC Value")
struct OSCValueTests {

    @Test("values are Sendable")
    func valueSendable() {
        let values: [OSCValue] = [
            .int(42),
            .float(1.5),
            .string("test"),
            .blob(Data([0x01, 0x02]))
        ]
        let _: [any Sendable] = values
        #expect(values.count == 4)
    }
}

// MARK: - OSC Receiver Functional Tests

@Suite("OSC Receiver")
@MainActor
struct OSCReceiverFunctionalTests {

    @Test("initialization with port")
    func initialization() {
        let osc = OSCReceiver(port: 9000)
        #expect(osc.port == 9000)
    }

    @Test("handler registration does not trigger callback")
    func handlerRegistration() {
        let osc = OSCReceiver(port: 9001)
        var received = false
        osc.on("/test") { _ in received = true }
        #expect(!received)
    }

    @Test("poll with no messages is safe")
    func pollWithNoMessages() {
        let osc = OSCReceiver(port: 9002)
        var callCount = 0
        osc.on("/test") { _ in callCount += 1 }
        osc.poll()
        #expect(callCount == 0)
    }

    @Test("stop without start is safe")
    func stopWithoutStart() {
        let osc = OSCReceiver(port: 9003)
        osc.stop()
    }
}

// MARK: - OSC Parser truncation/robustness

@Suite("OSC Parser truncated data")
struct OSCParserTruncationTests {

    /// タイプタグが3つあるのにペイロードが1つ分しかない —
    /// 最初の値だけパースして打ち切ること（以前は switch 内の break が
    /// ループを抜けず、ずれたオフセットから残りを読み続けた）。
    @Test("truncated payload stops at the first missing value")
    func truncatedPayloadStops() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/t", to: &data)
        OSCBinaryHelper.appendOSCString(",iii", to: &data)
        OSCBinaryHelper.appendInt32(7, to: &data)
        // 2 つ目・3 つ目の int は欠落

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].values.count == 1)
        if case .int(let v) = messages[0].values.first {
            #expect(v == 7)
        } else {
            Issue.record("Expected .int value")
        }
    }

    /// blob のサイズフィールドだけあってペイロードが欠けている場合、
    /// 以前は pos がサイズフィールド分進んだ後に打ち切られ、後続の値が
    /// 4 バイトずれた位置から「静かに間違った値」として読まれていた。
    @Test("truncated blob does not shift subsequent reads")
    func truncatedBlobStops() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/b", to: &data)
        OSCBinaryHelper.appendOSCString(",bi", to: &data)
        OSCBinaryHelper.appendInt32(1024, to: &data)  // ペイロードのない blob サイズ
        OSCBinaryHelper.appendInt32(99, to: &data)    // 後続の int（blob 欠落により到達不能）

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        // blob が壊れている時点で打ち切り。ずれた位置から int を拾わないこと。
        #expect(messages[0].values.isEmpty,
                "Parsing must stop at the malformed blob (got \(messages[0].values))")
    }

    /// 未知のタイプタグはペイロード長が不明なため、それ以降は打ち切ること。
    @Test("unknown type tag stops value parsing")
    func unknownTagStops() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/u", to: &data)
        OSCBinaryHelper.appendOSCString(",ixi", to: &data)  // 'x' は未知
        OSCBinaryHelper.appendInt32(1, to: &data)
        OSCBinaryHelper.appendInt32(2, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].values.count == 1, "Only the value before the unknown tag should parse")
    }

    /// ゼロ長の標準タグ（T/F/N/I）は値の読み出し位置をずらさず読み飛ばすこと。
    @Test("zero-size standard tags are skipped without consuming payload")
    func zeroSizeTagsSkipped() {
        var data = Data()
        OSCBinaryHelper.appendOSCString("/z", to: &data)
        OSCBinaryHelper.appendOSCString(",TiF", to: &data)
        OSCBinaryHelper.appendInt32(5, to: &data)

        let messages = OSCParser.parse(data: data)
        #expect(messages.count == 1)
        #expect(messages[0].values.count == 1)
        if case .int(let v) = messages[0].values.first {
            #expect(v == 5)
        } else {
            Issue.record("Expected .int value")
        }
    }
}
