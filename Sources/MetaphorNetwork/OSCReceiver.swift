import Foundation
import Network
import os

// MARK: - OSC 値

/// OSC メッセージ内の値を表します。
public enum OSCValue: Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)
}

// MARK: - OSC メッセージ（内部）

public struct OSCMessage: Sendable {
    /// OSC アドレスパターン（例: "/synth/freq"）。
    public let address: String
    /// メッセージに含まれる値のリスト。
    public let values: [OSCValue]
}

// MARK: - スレッドセーフなメッセージキュー

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

// MARK: - スレッドセーフなリスナー状態

private final class OSCListenerState: Sendable {
    // State は非 Sendable の NWListener を含むが、
    // アクセスは常に OSAllocatedUnfairLock で同期される。
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

/// OSC ネットワーク I/O 用の専用シリアルキュー（@MainActor 分離を避けるためファイルスコープ）。
private let oscNetworkQueue = DispatchQueue(label: "metaphor.osc.network", qos: .userInitiated)

// MARK: - OSCReceiver

/// Network.framework を使用して UDP OSC メッセージを受信します。
///
/// NWListener を使って OSC 1.0 メッセージを受信し、
/// VJ やインスタレーションシナリオでの外部コントロールを実現します。
///
/// ```swift
/// let osc = createOSCReceiver(port: 9000)
/// osc.on("/note") { values in
///     if case .float(let vel) = values.first {
///         // ノートベロシティを処理
///     }
/// }
/// try osc.start()
/// // draw() 内で呼び出して自動ディスパッチ
/// osc.poll()
/// ```
@MainActor
public final class OSCReceiver {

    // MARK: - パブリックプロパティ

    /// リスニングポート番号を返します。
    public let port: UInt16

    // MARK: - プライベート

    private let listenerState = OSCListenerState()

    /// アドレスからハンドラーへのマッピング。
    private var handlers: [String: ([OSCValue]) -> Void] = [:]

    /// すべてのメッセージを受信するワイルドカードハンドラー。
    private var wildcardHandler: ((String, [OSCValue]) -> Void)?

    /// スレッドセーフなメッセージキュー。
    private let messageQueue = OSCMessageQueue()

    // MARK: - 初期化

    /// OSC レシーバーを作成します。
    /// - Parameter port: リスニングする UDP ポート番号。
    public init(port: UInt16) {
        self.port = port
    }

    // MARK: - パブリック API

    /// 特定の OSC アドレスパターンに対するハンドラーを登録します。
    /// - Parameters:
    ///   - address: マッチする OSC アドレスパターン。
    ///   - handler: メッセージ値で呼び出されるクロージャ。
    public func on(_ address: String, handler: @escaping ([OSCValue]) -> Void) {
        handlers[address] = handler
    }

    /// すべてのメッセージを受信するワイルドカードハンドラーを登録します。
    /// - Parameter handler: アドレスと値で呼び出されるクロージャ。
    public func onAny(handler: @escaping (String, [OSCValue]) -> Void) {
        wildcardHandler = handler
    }

    /// 受信 OSC メッセージのリスニングを開始します。
    /// - Throws: ポートが無効な場合に `OSCReceiverError.invalidPort` をスローします。
    public func start() throws {
        guard !listenerState.isRunning else { return }

        let params = NWParameters.udp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OSCReceiverError.invalidPort(port)
        }
        let listener = try NWListener(using: params, on: nwPort)

        let queue = messageQueue

        listener.newConnectionHandler = { connection in
            connection.start(queue: oscNetworkQueue)
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

        listener.start(queue: oscNetworkQueue)
        listenerState.listener = listener
        listenerState.isRunning = true
    }

    deinit {
        listenerState.cancel()
    }

    /// OSC メッセージのリスニングを停止します。
    public func stop() {
        guard listenerState.isRunning else { return }
        listenerState.cancel()
    }

    /// キュー内のメッセージをメインスレッドでディスパッチします（`draw()` 内で呼び出してください）。
    /// - Returns: 受信した OSC メッセージの配列。
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
            }
        }
    }
}

// MARK: - OSC パーサー

/// OSC 1.0 バイナリメッセージをパースします。
enum OSCParser {

    /// バイナリデータをパースして OSC メッセージの配列を返します。
    /// - Parameter data: 生の OSC バイナリデータ。
    /// - Returns: パースされた OSC メッセージ。
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

    /// OSC バンドルをパースします。
    private static func parseBundle(data: Data) -> [OSCMessage] {
        var messages: [OSCMessage] = []
        // #bundle\0 (8バイト) + timetag (8バイト) = 16バイトヘッダー
        guard data.count >= 16 else { return [] }

        var offset = 16  // ヘッダー + timetag をスキップ

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

    /// 単一の OSC メッセージをパースします。
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

        // 値をパース（先頭の ',' をスキップ）
        var values: [OSCValue] = []
        for ch in typeTags.dropFirst() {  // ',' をスキップ
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

    // MARK: - バイナリヘルパー

    /// ヌル終端文字列を読み取ります。
    private static func readString(data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }
        guard end > offset else { return "" }
        return String(data: data[offset..<end], encoding: .ascii)
    }

    /// ビッグエンディアンの Int32 を読み取ります。
    private static func readInt32(data: Data, offset: Int) -> Int32 {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            return Int32(bitPattern: UInt32(bigEndian: raw))
        }
    }

    /// ビッグエンディアンの Float32 を読み取ります。
    private static func readFloat32(data: Data, offset: Int) -> Float {
        data.withUnsafeBytes { ptr in
            let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
            let bits = UInt32(bigEndian: raw)
            return Float(bitPattern: bits)
        }
    }

    /// サイズを4バイトアラインメントに切り上げます。
    private static func alignedSize(_ size: Int) -> Int {
        (size + 3) & ~3
    }
}

// MARK: - エラー

/// OSC レシーバー操作中に発生するエラーを表します。
public enum OSCReceiverError: Error, LocalizedError {
    /// 指定されたポートが無効であることを示します。
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p):
            return "[metaphor] Invalid OSC port: \(p)"
        }
    }
}
