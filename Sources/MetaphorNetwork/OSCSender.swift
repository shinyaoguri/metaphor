import Foundation
import Network
import os

// MARK: - スレッドセーフなコネクション状態

private final class OSCConnectionState: Sendable {
    // State は非 Sendable の NWConnection を含むが、
    // アクセスは常に OSAllocatedUnfairLock で同期される。
    private struct State: @unchecked Sendable {
        var connection: NWConnection?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var connection: NWConnection? {
        get { state.withLock { $0.connection } }
        set { state.withLock { $0.connection = newValue } }
    }

    func cancel() {
        state.withLock { s in
            s.connection?.cancel()
            s.connection = nil
        }
    }
}

// MARK: - OSCSender

/// Sends UDP OSC messages using Network.framework.
///
/// The sending counterpart to ``OSCReceiver``. Enables bidirectional loops
/// with TouchDesigner / Max / VJ tools (equivalent to Processing's oscP5).
///
/// ```swift
/// let osc = createOSCSender(host: "127.0.0.1", port: 9000)
/// osc?.send("/synth/freq", 440.0)
/// osc?.send("/note", 60, 127, "on")   // int, int, string
/// ```
///
/// `OSCValue` can be constructed from literals (integer → `.int`, decimal →
/// `.float`, string → `.string`). Sending is asynchronous; failures can be
/// observed via ``lastError``.
@MainActor
public final class OSCSender {

    // MARK: - パブリックプロパティ

    /// The destination host (IP address or hostname).
    public let host: String

    /// The destination UDP port number.
    public let port: UInt16

    /// The most recent send/connection error.
    ///
    /// UDP sends are asynchronous, so observe errors through this property.
    public var lastError: (any Error)? { errorBox.value }

    // MARK: - プライベート

    private let connectionState = OSCConnectionState()
    private let errorBox = OSCErrorBox2()

    // MARK: - 初期化

    /// Creates an OSC sender and opens a UDP flow to the destination.
    ///
    /// - Parameters:
    ///   - host: The destination host (e.g. `"127.0.0.1"`).
    ///   - port: The destination UDP port number.
    /// - Throws: ``OSCSenderError/invalidPort(_:)`` if the port is 0.
    public init(host: String, port: UInt16) throws {
        guard port > 0, let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OSCSenderError.invalidPort(port)
        }
        self.host = host
        self.port = port

        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let errors = errorBox
        connection.stateUpdateHandler = { update in
            if case .failed(let error) = update {
                print("[metaphor] OSC sender connection failed: \(error)")
                errors.store(error)
            }
        }
        connection.start(queue: oscSenderQueue)
        connectionState.connection = connection
    }

    deinit {
        connectionState.cancel()
    }

    // MARK: - パブリック API

    /// Sends an OSC message.
    ///
    /// - Parameters:
    ///   - address: The OSC address pattern (e.g. `"/synth/freq"`).
    ///   - values: The list of values to include in the message.
    public func send(_ address: String, _ values: [OSCValue]) {
        transmit(OSCEncoder.encodeMessage(address: address, values: values))
    }

    /// Sends an OSC message (variadic version).
    ///
    /// Literals can be passed directly: `send("/note", 60, 0.5, "on")`.
    ///
    /// - Parameters:
    ///   - address: The OSC address pattern.
    ///   - values: The values to include in the message.
    public func send(_ address: String, _ values: OSCValue...) {
        send(address, values)
    }

    /// Sends multiple messages as a single OSC bundle.
    ///
    /// The timetag is fixed to immediate.
    ///
    /// - Parameter messages: The array of messages to include in the bundle.
    public func sendBundle(_ messages: [OSCMessage]) {
        guard !messages.isEmpty else { return }
        transmit(OSCEncoder.encodeBundle(messages: messages))
    }

    /// Closes the UDP flow to the destination. Subsequent sends are ignored.
    public func stop() {
        connectionState.cancel()
    }

    // MARK: - プライベート

    private func transmit(_ data: Data) {
        guard let connection = connectionState.connection else {
            debugWarning("OSCSender.send: sender is stopped")
            return
        }
        let errors = errorBox
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                errors.store(error)
            }
        })
    }
}

/// A dedicated serial queue for OSC send I/O.
private let oscSenderQueue = DispatchQueue(label: "metaphor.osc.sender", qos: .userInitiated)

// MARK: - スレッドセーフなエラーボックス（送信側）

/// Carries errors that occur on the network thread to the main thread.
private final class OSCErrorBox2: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (any Error)?.none)

    func store(_ error: any Error) {
        state.withLock { $0 = error }
    }

    var value: (any Error)? {
        state.withLock { $0 }
    }
}

// MARK: - OSC エンコーダー

/// Encodes OSC 1.0 binary messages (the inverse of ``OSCParser``).
enum OSCEncoder {

    /// Encodes a single OSC message.
    static func encodeMessage(address: String, values: [OSCValue]) -> Data {
        var data = Data()
        appendString(address, to: &data)

        var typeTags = ","
        for value in values {
            switch value {
            case .int: typeTags += "i"
            case .float: typeTags += "f"
            case .string: typeTags += "s"
            case .blob: typeTags += "b"
            }
        }
        appendString(typeTags, to: &data)

        for value in values {
            switch value {
            case .int(let i):
                appendInt32(i, to: &data)
            case .float(let f):
                appendInt32(Int32(bitPattern: f.bitPattern), to: &data)
            case .string(let s):
                appendString(s, to: &data)
            case .blob(let b):
                appendInt32(Int32(b.count), to: &data)
                data.append(b)
                padToAlignment(&data)
            }
        }
        return data
    }

    /// Encodes multiple messages as an OSC bundle (timetag = immediate).
    static func encodeBundle(messages: [OSCMessage]) -> Data {
        var data = Data()
        appendString("#bundle", to: &data)  // "#bundle\0" = 8 バイト（アライン済み）
        // timetag: immediate（OSC 1.0 仕様の 0x0000000000000001）
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1] as [UInt8])
        for message in messages {
            let encoded = encodeMessage(address: message.address, values: message.values)
            appendInt32(Int32(encoded.count), to: &data)
            data.append(encoded)
        }
        return data
    }

    // MARK: - バイナリヘルパー

    /// Appends a string with a null terminator and 4-byte alignment (UTF-8).
    private static func appendString(_ string: String, to data: inout Data) {
        data.append(contentsOf: Array(string.utf8))
        data.append(0)
        padToAlignment(&data)
    }

    /// Appends a big-endian `Int32`.
    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let raw = UInt32(bitPattern: value)
        data.append(contentsOf: [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ])
    }

    /// Zero-pads the data length to a 4-byte boundary.
    private static func padToAlignment(_ data: inout Data) {
        while data.count % 4 != 0 {
            data.append(0)
        }
    }
}

// MARK: - OSCValue リテラル構築

extension OSCValue: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral
{
    /// Constructs `.int` from an integer literal.
    public init(integerLiteral value: Int32) { self = .int(value) }

    /// Constructs `.float` from a floating-point literal.
    public init(floatLiteral value: Float) { self = .float(value) }

    /// Constructs `.string` from a string literal.
    public init(stringLiteral value: String) { self = .string(value) }
}

// MARK: - エラー

/// Represents errors that can occur during `OSCSender` operations.
public enum OSCSenderError: Error, LocalizedError {
    /// Indicates that the specified port is invalid.
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p):
            return "[metaphor] Invalid OSC port: \(p)"
        }
    }
}
