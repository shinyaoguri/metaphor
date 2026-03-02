import Foundation
import Network

// MARK: - OSC Value

/// OSC メッセージの値
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
    private let lock = NSLock()
    private nonisolated(unsafe) var _messages: [OSCMessage] = []
    private let maxQueueSize = 10_000

    func enqueue(_ message: OSCMessage) {
        lock.lock()
        if _messages.count < maxQueueSize {
            _messages.append(message)
        }
        lock.unlock()
    }

    func dequeueAll() -> [OSCMessage] {
        lock.lock()
        let msgs = _messages
        _messages.removeAll()
        lock.unlock()
        return msgs
    }
}

// MARK: - OSCReceiver

/// UDP OSC メッセージレシーバー
///
/// Network.framework の NWListener を使って OSC 1.0 メッセージを受信する。
/// VJ やインスタレーションでの外部制御に使用する。
///
/// ```swift
/// let osc = createOSCReceiver(port: 9000)
/// osc.on("/note") { values in
///     if case .float(let vel) = values.first {
///         // handle note velocity
///     }
/// }
/// try osc.start()
/// // draw() 内で自動ディスパッチ
/// osc.poll()
/// ```
@MainActor
public final class OSCReceiver {

    // MARK: - Public Properties

    /// リッスンポート
    public let port: UInt16

    // MARK: - Private

    private var listener: NWListener?
    private var isRunning = false

    /// アドレス → ハンドラーマッピング
    private var handlers: [String: ([OSCValue]) -> Void] = [:]

    /// ワイルドカードハンドラー（全メッセージ受信）
    private var wildcardHandler: ((String, [OSCValue]) -> Void)?

    /// スレッド安全なメッセージキュー
    private let messageQueue = OSCMessageQueue()

    // MARK: - Initialization

    /// OSCReceiver を作成
    /// - Parameter port: UDP ポート番号
    public init(port: UInt16) {
        self.port = port
    }

    // MARK: - Public API

    /// 指定アドレスパターンのハンドラーを登録
    public func on(_ address: String, handler: @escaping ([OSCValue]) -> Void) {
        handlers[address] = handler
    }

    /// 全メッセージを受け取るワイルドカードハンドラーを登録
    public func onAny(handler: @escaping (String, [OSCValue]) -> Void) {
        wildcardHandler = handler
    }

    /// 受信開始
    public func start() throws {
        guard !isRunning else { return }

        let params = NWParameters.udp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

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
        self.listener = listener
        self.isRunning = true
    }

    /// 受信停止
    public func stop() {
        guard isRunning else { return }
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// メインスレッドでキューされたメッセージをディスパッチ（draw() 内で呼ぶ）
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

/// OSC 1.0 バイナリパーサー
enum OSCParser {

    /// データをパースして OSCMessage の配列を返す
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

    /// バンドルをパース
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

    /// 単一メッセージをパース
    private static func parseMessage(data: Data, offset: Int) -> (message: OSCMessage, bytesRead: Int)? {
        var pos = offset

        // アドレスパターン
        guard let address = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(address.utf8.count + 1)  // +1 for null terminator

        // タイプタグ文字列
        guard pos < data.count, data[pos] == 0x2C else {  // ','
            return (OSCMessage(address: address, values: []), pos - offset)
        }

        guard let typeTags = readString(data: data, offset: pos) else { return nil }
        pos += alignedSize(typeTags.utf8.count + 1)

        // 値をパース（先頭の ',' をスキップ）
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

    /// null終端文字列を読む
    private static func readString(data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }
        guard end > offset else { return "" }
        return String(data: data[offset..<end], encoding: .ascii)
    }

    /// Big-endian Int32 を読む
    private static func readInt32(data: Data, offset: Int) -> Int32 {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            return Int32(bitPattern: UInt32(bigEndian: raw))
        }
    }

    /// Big-endian Float32 を読む
    private static func readFloat32(data: Data, offset: Int) -> Float {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            let bits = UInt32(bigEndian: raw)
            return Float(bitPattern: bits)
        }
    }

    /// 4バイトアラインメント
    private static func alignedSize(_ size: Int) -> Int {
        (size + 3) & ~3
    }
}
