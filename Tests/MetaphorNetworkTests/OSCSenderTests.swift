import Testing
@testable import MetaphorNetwork
import Foundation

// MARK: - OSC Encoder (#283)

@Suite("OSC Encoder")
struct OSCEncoderTests {

    @Test("encoded int message matches the OSC 1.0 wire format")
    func goldenIntMessage() {
        let data = OSCEncoder.encodeMessage(address: "/ab", values: [.int(1)])
        // "/ab\0" + ",i\0\0" + 00 00 00 01
        let expected: [UInt8] = [
            0x2F, 0x61, 0x62, 0x00,
            0x2C, 0x69, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x01,
        ]
        #expect(Array(data) == expected)
    }

    @Test("message round-trips through the existing parser")
    func messageRoundTrip() throws {
        let values: [OSCValue] = [
            .int(-42), .float(3.5), .string("hello"), .blob(Data([1, 2, 3, 4, 5])),
        ]
        let data = OSCEncoder.encodeMessage(address: "/synth/freq", values: values)
        // 4 バイトアラインが保たれている
        #expect(data.count % 4 == 0)

        let parsed = OSCParser.parse(data: data)
        let message = try #require(parsed.first)
        #expect(parsed.count == 1)
        #expect(message.address == "/synth/freq")
        #expect(message.values.count == 4)
        guard case .int(let i) = message.values[0] else { Issue.record("expected int"); return }
        #expect(i == -42)
        guard case .float(let f) = message.values[1] else { Issue.record("expected float"); return }
        #expect(f == 3.5)
        guard case .string(let s) = message.values[2] else { Issue.record("expected string"); return }
        #expect(s == "hello")
        guard case .blob(let b) = message.values[3] else { Issue.record("expected blob"); return }
        #expect(b == Data([1, 2, 3, 4, 5]))
    }

    @Test("no-arg and non-ASCII messages round-trip")
    func edgeCaseRoundTrip() throws {
        let noArg = OSCParser.parse(data: OSCEncoder.encodeMessage(address: "/ping", values: []))
        #expect(noArg.first?.address == "/ping")
        #expect(noArg.first?.values.isEmpty == true)

        let unicode = OSCParser.parse(
            data: OSCEncoder.encodeMessage(address: "/label", values: [.string("こんにちは")]))
        guard case .string(let s) = unicode.first?.values.first else {
            Issue.record("expected string")
            return
        }
        #expect(s == "こんにちは")
    }

    @Test("bundle with immediate timetag round-trips through the parser")
    func bundleRoundTrip() throws {
        let bundle = OSCEncoder.encodeBundle(messages: [
            OSCMessage(address: "/a", values: [.int(1)]),
            OSCMessage(address: "/b", values: [.float(2.5), .string("x")]),
        ])
        #expect(bundle.count % 4 == 0)

        let parsed = OSCParser.parse(data: bundle)
        #expect(parsed.count == 2)
        #expect(parsed.first?.address == "/a")
        #expect(parsed.last?.address == "/b")
        #expect(parsed.last?.values.count == 2)
    }

    @Test("OSCValue literals map to int/float/string")
    func valueLiterals() {
        let values: [OSCValue] = [60, 0.5, "on"]
        guard case .int(60) = values[0] else { Issue.record("expected .int(60)"); return }
        guard case .float(0.5) = values[1] else { Issue.record("expected .float(0.5)"); return }
        guard case .string("on") = values[2] else { Issue.record("expected .string(on)"); return }
    }
}

// MARK: - OSC Sender

@Suite("OSC Sender")
@MainActor
struct OSCSenderTests {

    @Test("init with port zero throws invalidPort")
    func invalidPort() {
        #expect(throws: OSCSenderError.self) {
            try OSCSender(host: "127.0.0.1", port: 0)
        }
    }

    @Test("send after stop is a safe no-op")
    func sendAfterStop() throws {
        let sender = try OSCSender(host: "127.0.0.1", port: 49999)
        sender.stop()
        sender.send("/x", 1)
        #expect(sender.lastError == nil)
    }

    @Test("send/receive loop over localhost UDP")
    func sendReceiveLoop() async throws {
        // 固定ポートの衝突を避けるため動的ポート域から選ぶ
        let port = UInt16.random(in: 49500...59500)
        let receiver = OSCReceiver(port: port)
        try receiver.start()
        defer { receiver.stop() }

        let sender = try OSCSender(host: "127.0.0.1", port: port)
        defer { sender.stop() }
        sender.send("/note", 60, 0.75, "on")
        sender.sendBundle([
            OSCMessage(address: "/bundle/a", values: [.int(1)]),
            OSCMessage(address: "/bundle/b", values: [.float(2)]),
        ])

        // 受信は非同期のため poll をリトライしながら 3 メッセージ揃うのを待つ
        var received: [OSCMessage] = []
        for _ in 0..<100 {
            received += receiver.poll()
            if received.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(received.count >= 3, "expected 3 messages, got \(received.count)")

        let byAddress = Dictionary(grouping: received, by: \.address)
        let note = try #require(byAddress["/note"]?.first)
        #expect(note.values.count == 3)
        guard case .int(60) = note.values[0] else { Issue.record("expected .int(60)"); return }
        #expect(byAddress["/bundle/a"]?.isEmpty == false)
        #expect(byAddress["/bundle/b"]?.isEmpty == false)
    }
}
