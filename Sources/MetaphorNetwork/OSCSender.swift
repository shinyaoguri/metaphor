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

/// Network.framework を使用して UDP OSC メッセージを送信します。
///
/// ``OSCReceiver`` と対になる送信側です。TouchDesigner / Max / VJ ツールとの
/// 双方向ループを実現します（Processing の oscP5 相当）。
///
/// ```swift
/// let osc = createOSCSender(host: "127.0.0.1", port: 9000)
/// osc?.send("/synth/freq", 440.0)
/// osc?.send("/note", 60, 127, "on")   // int, int, string
/// ```
///
/// `OSCValue` はリテラルから構築できます（整数 → `.int`、小数 → `.float`、
/// 文字列 → `.string`）。送信は非同期で、失敗は ``lastError`` から観測できます。
@MainActor
public final class OSCSender {

    // MARK: - パブリックプロパティ

    /// 送信先ホスト（IP アドレスまたはホスト名）。
    public let host: String

    /// 送信先の UDP ポート番号。
    public let port: UInt16

    /// 直近の送信・接続エラー。
    ///
    /// UDP 送信は非同期のため、エラーはこのプロパティで観測してください。
    public var lastError: (any Error)? { errorBox.value }

    // MARK: - プライベート

    private let connectionState = OSCConnectionState()
    private let errorBox = OSCErrorBox2()

    // MARK: - 初期化

    /// OSC センダーを作成し、送信先への UDP フローを開きます。
    ///
    /// - Parameters:
    ///   - host: 送信先ホスト（例: `"127.0.0.1"`）。
    ///   - port: 送信先の UDP ポート番号。
    /// - Throws: ポートが 0 の場合に ``OSCSenderError/invalidPort(_:)`` をスローします。
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

    /// OSC メッセージを送信します。
    ///
    /// - Parameters:
    ///   - address: OSC アドレスパターン（例: `"/synth/freq"`）。
    ///   - values: メッセージに含める値のリスト。
    public func send(_ address: String, _ values: [OSCValue]) {
        transmit(OSCEncoder.encodeMessage(address: address, values: values))
    }

    /// OSC メッセージを送信します（可変長引数版）。
    ///
    /// リテラルをそのまま渡せます: `send("/note", 60, 0.5, "on")`。
    ///
    /// - Parameters:
    ///   - address: OSC アドレスパターン。
    ///   - values: メッセージに含める値。
    public func send(_ address: String, _ values: OSCValue...) {
        send(address, values)
    }

    /// 複数のメッセージを 1 つの OSC バンドルとして送信します。
    ///
    /// timetag は immediate（即時実行）固定です。
    ///
    /// - Parameter messages: バンドルに含めるメッセージの配列。
    public func sendBundle(_ messages: [OSCMessage]) {
        guard !messages.isEmpty else { return }
        transmit(OSCEncoder.encodeBundle(messages: messages))
    }

    /// 送信先への UDP フローを閉じます。以降の送信は無視されます。
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

/// OSC 送信 I/O 用の専用シリアルキュー。
private let oscSenderQueue = DispatchQueue(label: "metaphor.osc.sender", qos: .userInitiated)

// MARK: - スレッドセーフなエラーボックス（送信側）

/// ネットワークスレッドで発生したエラーをメインスレッドへ渡します。
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

/// OSC 1.0 バイナリメッセージをエンコードします（``OSCParser`` の逆）。
enum OSCEncoder {

    /// 単一の OSC メッセージをエンコードします。
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

    /// 複数メッセージを OSC バンドルとしてエンコードします（timetag = immediate）。
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

    /// ヌル終端 + 4 バイトアラインで文字列を追加します（UTF-8）。
    private static func appendString(_ string: String, to data: inout Data) {
        data.append(contentsOf: Array(string.utf8))
        data.append(0)
        padToAlignment(&data)
    }

    /// ビッグエンディアンの Int32 を追加します。
    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let raw = UInt32(bitPattern: value)
        data.append(contentsOf: [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ])
    }

    /// データ長を 4 バイト境界までゼロパディングします。
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
    /// 整数リテラルから `.int` を構築します。
    public init(integerLiteral value: Int32) { self = .int(value) }

    /// 小数リテラルから `.float` を構築します。
    public init(floatLiteral value: Float) { self = .float(value) }

    /// 文字列リテラルから `.string` を構築します。
    public init(stringLiteral value: String) { self = .string(value) }
}

// MARK: - エラー

/// OSC センダー操作中に発生するエラーを表します。
public enum OSCSenderError: Error, LocalizedError {
    /// 指定されたポートが無効であることを示します。
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p):
            return "[metaphor] Invalid OSC port: \(p)"
        }
    }
}
