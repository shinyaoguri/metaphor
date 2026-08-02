import Foundation
import Network
import os

// MARK: - OSC 値

/// Represents a value inside an OSC message.
public enum OSCValue: Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)
}

// MARK: - OSC メッセージ（内部）

public struct OSCMessage: Sendable {
    /// The OSC address pattern (e.g. "/synth/freq").
    public let address: String
    /// The list of values included in the message.
    public let values: [OSCValue]

    /// Creates an OSC message (for use with ``OSCSender/sendBundle(_:)``).
    ///
    /// - Parameters:
    ///   - address: The OSC address pattern.
    ///   - values: The list of values to include in the message.
    public init(address: String, values: [OSCValue]) {
        self.address = address
        self.values = values
    }
}

// MARK: - スレッドセーフなメッセージキュー

private final class OSCMessageQueue: Sendable {
    private struct State {
        var messages: [OSCMessage] = []
        /// The number of messages dropped due to a full queue since the last dequeueAll.
        var dropped: Int = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let maxQueueSize = 10_000

    func enqueue(_ message: OSCMessage) {
        // ロック保持中はログを出さない（受信スレッドとメインの poll() を
        // 長くブロックしないよう、ドロップ数だけ記録する）
        state.withLock { s in
            if s.messages.count < maxQueueSize {
                s.messages.append(message)
            } else {
                s.dropped += 1
            }
        }
    }

    func dequeueAll() -> [OSCMessage] {
        let (msgs, dropped) = state.withLock { s -> ([OSCMessage], Int) in
            let msgs = s.messages
            let dropped = s.dropped
            s.messages.removeAll()
            s.dropped = 0
            return (msgs, dropped)
        }
        if dropped > 0 {
            debugWarning("OSC message queue overflowed: dropped \(dropped) message(s) since last poll()")
        }
        return msgs
    }
}

// MARK: - スレッドセーフなエラーボックス

/// Carries errors that occur on the network thread to the main thread's poll-style API.
private final class OSCErrorBox: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (any Error)?.none)

    func store(_ error: any Error) {
        state.withLock { $0 = error }
    }

    var value: (any Error)? {
        state.withLock { $0 }
    }

    func clear() {
        state.withLock { $0 = nil }
    }
}

// MARK: - スレッドセーフなリスナー状態

private final class OSCListenerState: Sendable {
    // State は非 Sendable の NWListener を含むが、
    // アクセスは常に OSAllocatedUnfairLock で同期される。
    private struct State: @unchecked Sendable {
        var listener: NWListener?
        var isRunning: Bool = false
        // 受け付けた UDP フロー。stop() でリスナーだけ cancel しても
        // 確立済みコネクションは受信し続けるため、追跡して一緒に閉じる。
        var connections: [NWConnection] = []
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

    func track(_ connection: NWConnection) {
        state.withLock { s in
            // 終了済みコネクションを掃除してから追加（無限成長の防止）
            s.connections.removeAll { conn in
                if case .cancelled = conn.state { return true }
                if case .failed = conn.state { return true }
                return false
            }
            s.connections.append(connection)
        }
    }

    func cancel() {
        state.withLock { s in
            s.listener?.cancel()
            s.listener = nil
            s.connections.forEach { $0.cancel() }
            s.connections.removeAll()
            s.isRunning = false
        }
    }
}

/// A dedicated serial queue for OSC network I/O (file-scoped to avoid @MainActor isolation).
private let oscNetworkQueue = DispatchQueue(label: "metaphor.osc.network", qos: .userInitiated)

// MARK: - OSCReceiver

/// Receives UDP OSC messages using Network.framework.
///
/// Uses `NWListener` to receive OSC 1.0 messages, enabling external control
/// for VJ and installation scenarios.
///
/// ```swift
/// let osc = createOSCReceiver(port: 9000)
/// osc.on("/note") { values in
///     if case .float(let vel) = values.first {
///         // handle note velocity
///     }
/// }
/// try osc.start()
/// // call in draw() for automatic dispatch
/// osc.poll()
/// ```
@MainActor
public final class OSCReceiver {

    // MARK: - パブリックプロパティ

    /// Returns the listening port number.
    public let port: UInt16

    /// Whether the receiver is currently listening.
    ///
    /// If the listener fails asynchronously (e.g. a port conflict), this
    /// automatically reverts to false and ``lastError`` is set. You can call
    /// ``start()`` again.
    public var isRunning: Bool { listenerState.isRunning }

    /// The most recent listener error (e.g. a port conflict).
    ///
    /// Listener failures happen asynchronously, so check this property the
    /// same way you check ``poll()`` inside `draw()`. It is cleared when
    /// ``start()`` is called.
    public var lastError: (any Error)? { errorBox.value }

    // MARK: - プライベート

    private let listenerState = OSCListenerState()
    private let errorBox = OSCErrorBox()

    /// A mapping from address to handler.
    private var handlers: [String: ([OSCValue]) -> Void] = [:]

    /// A wildcard handler that receives all messages.
    private var wildcardHandler: ((String, [OSCValue]) -> Void)?

    /// A thread-safe message queue.
    private let messageQueue = OSCMessageQueue()

    // MARK: - 初期化

    /// Creates an OSC receiver.
    /// - Parameter port: The UDP port number to listen on.
    public init(port: UInt16) {
        self.port = port
    }

    // MARK: - パブリック API

    /// Registers a handler for a specific OSC address pattern.
    /// - Parameters:
    ///   - address: The OSC address pattern to match.
    ///   - handler: A closure called with the message values.
    public func on(_ address: String, handler: @escaping ([OSCValue]) -> Void) {
        handlers[address] = handler
    }

    /// Registers a wildcard handler that receives all messages.
    /// - Parameter handler: A closure called with the address and values.
    public func onAny(handler: @escaping (String, [OSCValue]) -> Void) {
        wildcardHandler = handler
    }

    /// Starts listening for incoming OSC messages.
    /// - Throws: ``OSCReceiverError/invalidPort(_:)`` if the port is invalid, or
    ///   ``OSCReceiverError/listenerCreationFailed(port:detail:)`` if the UDP
    ///   listener cannot be created (for example when the port is already in use).
    public func start() throws {
        guard !listenerState.isRunning else { return }

        let params = NWParameters.udp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OSCReceiverError.invalidPort(port)
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            // Do not let the raw NWError escape: this module's error contract is
            // OSCReceiverError only.
            throw OSCReceiverError.listenerCreationFailed(
                port: port, detail: error.localizedDescription)
        }

        let queue = messageQueue
        let state = listenerState
        let errors = errorBox
        errors.clear()

        listener.newConnectionHandler = { connection in
            state.track(connection)
            connection.start(queue: oscNetworkQueue)
            Self.receiveLoop(connection: connection, queue: queue)
        }

        listener.stateUpdateHandler = { listenerUpdate in
            switch listenerUpdate {
            case .failed(let error):
                print("[metaphor] OSC listener failed: \(error)")
                // 失敗したリスナーを片付けて isRunning を false に戻す
                // （明示的な stop() なしで再 start() できる）。エラーは
                // lastError 経由でメインスレッドから観測できる
                errors.store(error)
                state.cancel()
            default:
                break
            }
        }

        listener.start(queue: oscNetworkQueue)
        listenerState.listener = listener
        listenerState.isRunning = true
    }

    deinit {
        listenerState.cancel()
    }

    /// Stops listening for OSC messages.
    public func stop() {
        guard listenerState.isRunning else { return }
        listenerState.cancel()
    }

    /// Dispatches queued messages on the main thread (call this inside `draw()`).
    /// - Returns: The array of received OSC messages.
    @discardableResult
    public func poll() -> [OSCMessage] {
        let messages = messageQueue.dequeueAll()
        for msg in messages {
            wildcardHandler?(msg.address, msg.values)
            if let handler = handlers[msg.address] {
                handler(msg.values)
            }
        }
        return messages
    }

    // MARK: - プライベート: ネットワーク受信

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
            } else {
                // エラーで受信を打ち切る場合はコネクションを明示的に閉じる
                // （放置するとフローがリークする）
                connection.cancel()
            }
        }
    }
}

// MARK: - OSC パーサー

/// Parses OSC 1.0 binary messages.
enum OSCParser {

    /// Parses binary data and returns an array of OSC messages.
    /// - Parameter data: The raw OSC binary data.
    /// - Returns: The parsed OSC messages.
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

    /// Parses an OSC bundle.
    private static func parseBundle(data: Data) -> [OSCMessage] {
        var messages: [OSCMessage] = []
        // #bundle\0 (8バイト) + timetag (8バイト) = 16バイトヘッダー
        guard data.count >= 16 else { return [] }

        var offset = 16  // ヘッダー + timetag をスキップ

        while offset + 4 <= data.count {
            let size = Int(readInt32(data: data, offset: offset))
            offset += 4

            guard size > 0, size <= data.count - offset else { break }

            let elementData = data.subdata(in: offset..<(offset + size))
            messages.append(contentsOf: parse(data: elementData))
            offset += size
        }

        return messages
    }

    /// Parses a single OSC message.
    private static func parseMessage(data: Data, offset: Int) -> (message: OSCMessage, bytesRead: Int)? {
        var pos = offset

        // アドレスパターン
        guard let address = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(address.utf8.count + 1)  // ヌル終端子用に +1

        // タイプタグ文字列
        guard pos < data.count, data[pos] == 0x2C else {  // ','
            return (OSCMessage(address: address, values: []), pos - offset)
        }

        guard let typeTags = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(typeTags.utf8.count + 1)

        // 値をパース（先頭の ',' をスキップ）。
        // 注意: switch 内の `break` は switch を抜けるだけでループは継続する。
        // 切り詰められたデータで残りのタイプタグを読み続けるとオフセットが
        // ずれて「静かに間違った値」を量産するため、異常を見つけたら
        // ラベル付き break でループ全体を打ち切る。
        var values: [OSCValue] = []
        parseLoop: for ch in typeTags.dropFirst() {  // ',' をスキップ
            switch ch {
            case "i":
                guard pos + 4 <= data.count else { break parseLoop }
                values.append(.int(readInt32(data: data, offset: pos)))
                pos += 4

            case "f":
                guard pos + 4 <= data.count else { break parseLoop }
                values.append(.float(readFloat32(data: data, offset: pos)))
                pos += 4

            case "s":
                guard let str = readString(data: data, offset: pos) else { break parseLoop }
                values.append(.string(str))
                pos += alignedSize(str.utf8.count + 1)

            case "b":
                // サイズフィールドとペイロードの両方が揃っているのを確認して
                // から pos を進める（途中で諦めると以降の読み出しがずれる）
                guard pos + 4 <= data.count else { break parseLoop }
                let blobSize = Int(readInt32(data: data, offset: pos))
                guard blobSize >= 0, blobSize <= data.count - pos - 4 else { break parseLoop }
                pos += 4
                let blob = data.subdata(in: pos..<(pos + blobSize))
                values.append(.blob(blob))
                pos += alignedSize(blobSize)

            // ゼロ長の標準タグは読み飛ばせる（値は持たない）
            case "T", "F", "N", "I":
                continue

            default:
                // 未知のタイプタグはペイロード長が分からないため、
                // 以降のオフセットを信頼できない。ここで打ち切る。
                break parseLoop
            }
        }

        return (OSCMessage(address: address, values: values), pos - offset)
    }

    // MARK: - バイナリヘルパー

    /// Reads a null-terminated string.
    ///
    /// OSC 1.0 strings are ASCII per spec, but UTF-8 is widely used across
    /// implementations in practice. Decoding as `.ascii` would discard the
    /// entire address or string value for any message containing non-ASCII
    /// characters, so this decodes as the backward-compatible UTF-8 instead.
    private static func readString(data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }
        guard end > offset else { return "" }
        return String(data: data[offset..<end], encoding: .utf8)
    }

    /// Reads a big-endian `Int32`.
    private static func readInt32(data: Data, offset: Int) -> Int32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let raw =
            (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
        return Int32(bitPattern: raw)
    }

    /// Reads a big-endian `Float32`.
    private static func readFloat32(data: Data, offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let bits =
            (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
        return Float(bitPattern: bits)
    }

    /// Rounds a size up to 4-byte alignment.
    private static func alignedSize(_ size: Int) -> Int {
        (size + 3) & ~3
    }
}

// MARK: - エラー

/// Represents errors that can occur during `OSCReceiver` operations.
///
/// Throwing `OSCReceiver` APIs only ever throw this type: failures coming from the
/// Network framework are wrapped into ``listenerCreationFailed(port:detail:)``
/// rather than being re-thrown as raw `NWError`.
public enum OSCReceiverError: Error, LocalizedError, Sendable {
    /// Indicates that the specified port is invalid.
    case invalidPort(UInt16)
    /// Indicates that the UDP listener could not be created (for example, the port
    /// is already bound by another process).
    case listenerCreationFailed(port: UInt16, detail: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p):
            return "[metaphor] Invalid OSC port: \(p)"
        case .listenerCreationFailed(let p, let detail):
            return "[metaphor] Failed to listen on OSC port \(p): \(detail)"
        }
    }
}
