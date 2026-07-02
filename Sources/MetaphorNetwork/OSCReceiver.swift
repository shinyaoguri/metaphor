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
        /// 直近の dequeueAll 以降にキュー満杯で捨てたメッセージ数。
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

/// ネットワークスレッドで発生したエラーをメインスレッドの poll 系 API へ渡します。
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

    /// レシーバーが現在リッスン中かどうか。
    ///
    /// リスナーが非同期に失敗した場合（ポート競合等）は自動的に false へ戻り、
    /// ``lastError`` にエラーが入ります。再度 ``start()`` を呼べます。
    public var isRunning: Bool { listenerState.isRunning }

    /// 直近のリスナーエラー（ポート競合等）。
    ///
    /// リスナーの失敗は非同期に起きるため、`draw()` 内の ``poll()`` と同じ要領で
    /// このプロパティを確認してください。``start()`` を呼ぶとクリアされます。
    public var lastError: (any Error)? { errorBox.value }

    // MARK: - プライベート

    private let listenerState = OSCListenerState()
    private let errorBox = OSCErrorBox()

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
            } else {
                // エラーで受信を打ち切る場合はコネクションを明示的に閉じる
                // （放置するとフローがリークする）
                connection.cancel()
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
            let size = Int(readInt32(data: data, offset: offset))
            offset += 4

            guard size > 0, size <= data.count - offset else { break }

            let elementData = data.subdata(in: offset..<(offset + size))
            messages.append(contentsOf: parse(data: elementData))
            offset += size
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

    /// ヌル終端文字列を読み取ります。
    ///
    /// OSC 1.0 の文字列は仕様上 ASCII だが、実装間では UTF-8 が広く使われる。
    /// .ascii でデコードすると非 ASCII 文字を含むメッセージがアドレス／文字列値
    /// ごと破棄されるため、上位互換の UTF-8 でデコードする。
    private static func readString(data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }
        guard end > offset else { return "" }
        return String(data: data[offset..<end], encoding: .utf8)
    }

    /// ビッグエンディアンの Int32 を読み取ります。
    private static func readInt32(data: Data, offset: Int) -> Int32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let raw =
            (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
        return Int32(bitPattern: raw)
    }

    /// ビッグエンディアンの Float32 を読み取ります。
    private static func readFloat32(data: Data, offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let bits =
            (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
        return Float(bitPattern: bits)
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
