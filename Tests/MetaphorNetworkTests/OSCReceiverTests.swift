import XCTest
@testable import MetaphorNetwork
import Foundation

// MARK: - OSC Parser Tests

final class OSCParserTests: XCTestCase {

    // MARK: - Helper: OSC メッセージ構築

    /// 4バイトアラインメントしたサイズ
    private func aligned(_ size: Int) -> Int {
        (size + 3) & ~3
    }

    /// null 終端 + 4バイトアラインメントされた文字列をバイト列に追加
    private func appendOSCString(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
        // null 終端 + パディング（4バイト境界まで）
        let paddingCount = aligned(string.utf8.count + 1) - string.utf8.count
        data.append(contentsOf: [UInt8](repeating: 0, count: paddingCount))
    }

    /// Big-endian Int32 をバイト列に追加
    private func appendInt32(_ value: Int32, to data: inout Data) {
        var bigEndian = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &bigEndian) { Array($0) })
    }

    /// Big-endian Float32 をバイト列に追加
    private func appendFloat32(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &bits) { Array($0) })
    }

    // MARK: - Single Message Tests

    func testParseIntMessage() {
        var data = Data()
        appendOSCString("/test", to: &data)
        appendOSCString(",i", to: &data)
        appendInt32(42, to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/test")
        XCTAssertEqual(messages[0].values.count, 1)
        if case .int(let v) = messages[0].values[0] {
            XCTAssertEqual(v, 42)
        } else {
            XCTFail("Expected .int value")
        }
    }

    func testParseFloatMessage() {
        var data = Data()
        appendOSCString("/volume", to: &data)
        appendOSCString(",f", to: &data)
        appendFloat32(0.75, to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/volume")
        if case .float(let v) = messages[0].values[0] {
            XCTAssertEqual(v, 0.75, accuracy: 0.001)
        } else {
            XCTFail("Expected .float value")
        }
    }

    func testParseStringMessage() {
        var data = Data()
        appendOSCString("/name", to: &data)
        appendOSCString(",s", to: &data)
        appendOSCString("hello", to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        if case .string(let v) = messages[0].values[0] {
            XCTAssertEqual(v, "hello")
        } else {
            XCTFail("Expected .string value")
        }
    }

    func testParseBlobMessage() {
        var data = Data()
        appendOSCString("/data", to: &data)
        appendOSCString(",b", to: &data)
        let blobData: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        appendInt32(Int32(blobData.count), to: &data)
        data.append(contentsOf: blobData)  // 4 bytes, already aligned

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        if case .blob(let v) = messages[0].values[0] {
            XCTAssertEqual(v.count, 4)
            XCTAssertEqual([UInt8](v), blobData)
        } else {
            XCTFail("Expected .blob value")
        }
    }

    func testParseMultipleValues() {
        var data = Data()
        appendOSCString("/multi", to: &data)
        appendOSCString(",ifs", to: &data)
        appendInt32(100, to: &data)
        appendFloat32(3.14, to: &data)
        appendOSCString("world", to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].values.count, 3)

        if case .int(let v) = messages[0].values[0] {
            XCTAssertEqual(v, 100)
        } else { XCTFail("Expected .int") }

        if case .float(let v) = messages[0].values[1] {
            XCTAssertEqual(v, 3.14, accuracy: 0.01)
        } else { XCTFail("Expected .float") }

        if case .string(let v) = messages[0].values[2] {
            XCTAssertEqual(v, "world")
        } else { XCTFail("Expected .string") }
    }

    func testParseNoArgMessage() {
        var data = Data()
        appendOSCString("/ping", to: &data)
        appendOSCString(",", to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/ping")
        XCTAssertEqual(messages[0].values.count, 0)
    }

    func testParseMessageWithoutTypeTags() {
        // アドレスのみ、タイプタグなし
        var data = Data()
        appendOSCString("/bare", to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/bare")
        XCTAssertEqual(messages[0].values.count, 0)
    }

    // MARK: - Bundle Tests

    func testParseBundleWithOneMessage() {
        var bundle = Data()
        // #bundle ヘッダー
        bundle.append(contentsOf: "#bundle".utf8)
        bundle.append(0)  // null terminator (total 8 bytes)
        // timetag (8 bytes, all zeros = immediate)
        bundle.append(contentsOf: [UInt8](repeating: 0, count: 8))

        // 内部メッセージ構築
        var msg = Data()
        appendOSCString("/bundled", to: &msg)
        appendOSCString(",i", to: &msg)
        appendInt32(99, to: &msg)

        // サイズプレフィックス + メッセージ
        appendInt32(Int32(msg.count), to: &bundle)
        bundle.append(msg)

        let messages = OSCParser.parse(data: bundle)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/bundled")
        if case .int(let v) = messages[0].values[0] {
            XCTAssertEqual(v, 99)
        } else { XCTFail("Expected .int") }
    }

    func testParseBundleWithMultipleMessages() {
        var bundle = Data()
        bundle.append(contentsOf: "#bundle".utf8)
        bundle.append(0)
        bundle.append(contentsOf: [UInt8](repeating: 0, count: 8))

        // メッセージ 1
        var msg1 = Data()
        appendOSCString("/a", to: &msg1)
        appendOSCString(",i", to: &msg1)
        appendInt32(1, to: &msg1)
        appendInt32(Int32(msg1.count), to: &bundle)
        bundle.append(msg1)

        // メッセージ 2
        var msg2 = Data()
        appendOSCString("/b", to: &msg2)
        appendOSCString(",f", to: &msg2)
        appendFloat32(2.5, to: &msg2)
        appendInt32(Int32(msg2.count), to: &bundle)
        bundle.append(msg2)

        let messages = OSCParser.parse(data: bundle)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].address, "/a")
        XCTAssertEqual(messages[1].address, "/b")
    }

    // MARK: - Edge Cases

    func testEmptyData() {
        let messages = OSCParser.parse(data: Data())
        XCTAssertEqual(messages.count, 0)
    }

    func testNegativeInt() {
        var data = Data()
        appendOSCString("/neg", to: &data)
        appendOSCString(",i", to: &data)
        appendInt32(-123, to: &data)

        let messages = OSCParser.parse(data: data)
        if case .int(let v) = messages[0].values[0] {
            XCTAssertEqual(v, -123)
        } else { XCTFail("Expected .int") }
    }

    func testLongAddress() {
        let longAddr = "/this/is/a/very/long/osc/address/pattern"
        var data = Data()
        appendOSCString(longAddr, to: &data)
        appendOSCString(",f", to: &data)
        appendFloat32(1.0, to: &data)

        let messages = OSCParser.parse(data: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, longAddr)
    }
}

// MARK: - OSC Value Tests

final class OSCValueTests: XCTestCase {

    func testValueIsSendable() {
        // Sendable 準拠を確認（コンパイル時チェック）
        let values: [OSCValue] = [
            .int(42),
            .float(1.5),
            .string("test"),
            .blob(Data([0x01, 0x02]))
        ]
        // Sendable プロトコルに準拠しているのでタスクに渡せる
        let _: [any Sendable] = values
        XCTAssertEqual(values.count, 4)
    }
}

// MARK: - OSC Receiver Tests

@MainActor
final class OSCReceiverFunctionalTests: XCTestCase {

    func testInitialization() {
        let osc = OSCReceiver(port: 9000)
        XCTAssertEqual(osc.port, 9000)
    }

    func testHandlerRegistration() {
        let osc = OSCReceiver(port: 9001)
        var received = false
        osc.on("/test") { _ in received = true }
        // ハンドラーが登録されただけで、まだ呼ばれない
        XCTAssertFalse(received)
    }

    func testPollWithNoMessages() {
        let osc = OSCReceiver(port: 9002)
        var callCount = 0
        osc.on("/test") { _ in callCount += 1 }
        // メッセージなしで poll しても安全
        osc.poll()
        XCTAssertEqual(callCount, 0)
    }

    func testStopWithoutStart() {
        let osc = OSCReceiver(port: 9003)
        // start() せずに stop() しても安全
        osc.stop()
    }
}
