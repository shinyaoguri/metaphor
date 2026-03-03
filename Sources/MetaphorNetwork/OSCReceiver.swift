import Foundation
import Network
import os

// MARK: - OSC Value

/// Represent a value within an OSC message.
public enum OSCValue: Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)
}

// MARK: - OSC Message (internal)

struct OSCMessage: Sendable {
    let address: String
    let values: [OSCValue]
}

// MARK: - Thread-safe Message Queue

private final class OSCMessageQueue: Sendable {
    private struct State {
        var messages: [OSCMessage] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let maxQueueSize = 10_000

    func enqueue(_ message: OSCMessage) {
        state.withLock { s in
            if s.messages.count < maxQueueSize {
                s.messages.append(message)
            } else {
                debugWarning("OSC message queue full, dropping message")
            }
        }
    }

    func dequeueAll() -> [OSCMessage] {
        state.withLock { s in
            let msgs = s.messages
            s.messages.removeAll()
            return msgs
        }
    }
}

// MARK: - Thread-safe Listener State

private final class OSCListenerState: Sendable {
    // State contains non-Sendable NWListener
    // but access is always synchronized via OSAllocatedUnfairLock.
    private struct State: @unchecked Sendable {
        var listener: NWListener?
        var isRunning: Bool = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var listener: NWListener? {
        get { state.withLock { $0.listener } }
        set { state.withLock { $0.listener = newValue } }
    }

    var isRunning: Bool {
        get { state.withLock { $0.isRunning } }
        set { state.withLock { $0.isRunning = newValue } }
    }

    func cancel() {
        state.withLock { s in
            s.listener?.cancel()
            s.listener = nil
            s.isRunning = false
        }
    }
}

// MARK: - OSCReceiver

/// Receive UDP OSC messages using Network.framework.
///
/// Use an NWListener to receive OSC 1.0 messages for external control
/// in VJ and installation scenarios.
///
/// ```swift
/// let osc = createOSCReceiver(port: 9000)
/// osc.on("/note") { values in
///     if case .float(let vel) = values.first {
///         // handle note velocity
///     }
/// }
/// try osc.start()
/// // Call in draw() for automatic dispatch
/// osc.poll()
/// ```
@MainActor
public final class OSCReceiver {

    // MARK: - Public Properties

    /// Return the listening port number.
    public let port: UInt16

    // MARK: - Private

    private let listenerState = OSCListenerState()

    /// Address-to-handler mapping.
    private var handlers: [String: ([OSCValue]) -> Void] = [:]

    /// Wildcard handler that receives all messages.
    private var wildcardHandler: ((String, [OSCValue]) -> Void)?

    /// Thread-safe message queue.
    private let messageQueue = OSCMessageQueue()

    // MARK: - Initialization

    /// Create an OSC receiver.
    /// - Parameter port: UDP port number to listen on.
    public init(port: UInt16) {
        self.port = port
    }

    // MARK: - Public API

    /// Register a handler for a specific OSC address pattern.
    /// - Parameters:
    ///   - address: OSC address pattern to match.
    ///   - handler: Closure invoked with the message values.
    public func on(_ address: String, handler: @escaping ([OSCValue]) -> Void) {
        handlers[address] = handler
    }

    /// Register a wildcard handler that receives all messages.
    /// - Parameter handler: Closure invoked with the address and values.
    public func onAny(handler: @escaping (String, [OSCValue]) -> Void) {
        wildcardHandler = handler
    }

    /// Start listening for incoming OSC messages.
    /// - Throws: `OSCReceiverError.invalidPort` if the port is invalid.
    public func start() throws {
        guard !listenerState.isRunning else { return }

        let params = NWParameters.udp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OSCReceiverError.invalidPort(port)
        }
        let listener = try NWListener(using: params, on: nwPort)

        let queue = messageQueue

        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInteractive))
            Self.receiveLoop(connection: connection, queue: queue)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("[metaphor] OSC listener failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .userInteractive))
        listenerState.listener = listener
        listenerState.isRunning = true
    }

    deinit {
        listenerState.cancel()
    }

    /// Stop listening for OSC messages.
    public func stop() {
        guard listenerState.isRunning else { return }
        listenerState.cancel()
    }

    /// Dispatch queued messages on the main thread (call inside `draw()`).
    public func poll() {
        let messages = messageQueue.dequeueAll()
        for msg in messages {
            wildcardHandler?(msg.address, msg.values)
            if let handler = handlers[msg.address] {
                handler(msg.values)
            }
        }
    }

    // MARK: - Private: Network Receive

    private nonisolated static func receiveLoop(connection: NWConnection, queue: OSCMessageQueue) {
        connection.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty {
                let messages = OSCParser.parse(data: data)
                for msg in messages {
                    queue.enqueue(msg)
                }
            }

            if error == nil {
                receiveLoop(connection: connection, queue: queue)
            }
        }
    }
}

// MARK: - OSC Parser

/// Parse OSC 1.0 binary messages.
enum OSCParser {

    /// Parse binary data and return an array of OSC messages.
    /// - Parameter data: Raw OSC binary data.
    /// - Returns: Parsed OSC messages.
    static func parse(data: Data) -> [OSCMessage] {
        if data.count >= 8, String(data: data.prefix(8), encoding: .ascii)?.hasPrefix("#bundle") == true {
            return parseBundle(data: data)
        } else {
            if let msg = parseMessage(data: data, offset: 0) {
                return [msg.message]
            }
            return []
        }
    }

    /// Parse an OSC bundle.
    private static func parseBundle(data: Data) -> [OSCMessage] {
        var messages: [OSCMessage] = []
        // #bundle\0 (8 bytes) + timetag (8 bytes) = 16 bytes header
        guard data.count >= 16 else { return [] }

        var offset = 16  // skip header + timetag

        while offset + 4 <= data.count {
            let size = readInt32(data: data, offset: offset)
            offset += 4

            guard size > 0, offset + Int(size) <= data.count else { break }

            let elementData = data.subdata(in: offset..<(offset + Int(size)))
            messages.append(contentsOf: parse(data: elementData))
            offset += Int(size)
        }

        return messages
    }

    /// Parse a single OSC message.
    private static func parseMessage(data: Data, offset: Int) -> (message: OSCMessage, bytesRead: Int)? {
        var pos = offset

        // Address pattern
        guard let address = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(address.utf8.count + 1)  // +1 for null terminator

        // Type tag string
        guard pos < data.count, data[pos] == 0x2C else {  // ','
            return (OSCMessage(address: address, values: []), pos - offset)
        }

        guard let typeTags = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(typeTags.utf8.count + 1)

        // Parse values (skip the leading ',')
        var values: [OSCValue] = []
        for ch in typeTags.dropFirst() {  // skip ','
            switch ch {
            case "i":
                guard pos + 4 <= data.count else { break }
                values.append(.int(readInt32(data: data, offset: pos)))
                pos += 4

            case "f":
                guard pos + 4 <= data.count else { break }
                values.append(.float(readFloat32(data: data, offset: pos)))
                pos += 4

            case "s":
                guard let str = readString(data: data, offset: pos) else { break }
                values.append(.string(str))
                pos += alignedSize(str.utf8.count + 1)

            case "b":
                guard pos + 4 <= data.count else { break }
                let blobSize = Int(readInt32(data: data, offset: pos))
                pos += 4
                guard pos + blobSize <= data.count else { break }
                let blob = data.subdata(in: pos..<(pos + blobSize))
                values.append(.blob(blob))
                pos += alignedSize(blobSize)

            default:
                break
            }
        }

        return (OSCMessage(address: address, values: values), pos - offset)
    }

    // MARK: - Binary Helpers

    /// Read a null-terminated string.
    private static func readString(data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }
        guard end > offset else { return "" }
        return String(data: data[offset..<end], encoding: .ascii)
    }

    /// Read a big-endian Int32.
    private static func readInt32(data: Data, offset: Int) -> Int32 {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            return Int32(bitPattern: UInt32(bigEndian: raw))
        }
    }

    /// Read a big-endian Float32.
    private static func readFloat32(data: Data, offset: Int) -> Float {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            let bits = UInt32(bigEndian: raw)
            return Float(bitPattern: bits)
        }
    }

    /// Round a size up to 4-byte alignment.
    private static func alignedSize(_ size: Int) -> Int {
        (size + 3) & ~3
    }
}

// MARK: - Error

/// Represent errors that occur during OSC receiver operations.
public enum OSCReceiverError: Error, LocalizedError {
    /// Indicate that the specified port is invalid.
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p):
            return "[metaphor] Invalid OSC port: \(p)"
        }
    }
}
