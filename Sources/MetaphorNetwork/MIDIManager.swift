import CoreMIDI
import Foundation
import os

/// MIDI 入出力接続を管理します。
///
/// CoreMIDI を使用して MIDI デバイスに接続し、メッセージの送受信を行います。
///
/// ```swift
/// var midi: MIDIManager!
/// func setup() {
///     midi = createMIDI()
///     midi.start()
///     midi.onNoteOn { channel, note, velocity in
///         print("Note On: \(note) vel:\(velocity)")
///     }
/// }
/// func draw() {
///     let val = midi.controllerValue(1) // mod wheel
/// }
/// ```
// MARK: - スレッドセーフな CoreMIDI ポート状態

private final class MIDIPortState: Sendable {
    private struct State {
        var client: MIDIClientRef = 0
        var inputPort: MIDIPortRef = 0
        var outputPort: MIDIPortRef = 0
        /// 現在 inputPort に接続済みのソース（ホットプラグ時の張り直しに使用）。
        var connectedSources: [MIDIEndpointRef] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func set(client: MIDIClientRef, inputPort: MIDIPortRef, outputPort: MIDIPortRef) {
        state.withLock { s in
            s.client = client
            s.inputPort = inputPort
            s.outputPort = outputPort
        }
    }

    var inputPort: MIDIPortRef {
        state.withLock { $0.inputPort }
    }

    var outputPort: MIDIPortRef {
        state.withLock { $0.outputPort }
    }

    /// 接続済みソースの一覧を差し替え、以前の一覧を返します。
    func replaceConnectedSources(_ sources: [MIDIEndpointRef]) -> [MIDIEndpointRef] {
        state.withLock { s in
            let previous = s.connectedSources
            s.connectedSources = sources
            return previous
        }
    }

    func dispose() {
        state.withLock { s in
            if s.inputPort != 0 { MIDIPortDispose(s.inputPort); s.inputPort = 0 }
            if s.outputPort != 0 { MIDIPortDispose(s.outputPort); s.outputPort = 0 }
            if s.client != 0 { MIDIClientDispose(s.client); s.client = 0 }
            s.connectedSources.removeAll()
        }
    }
}

@MainActor
public final class MIDIManager {

    // MARK: - CoreMIDI 参照

    private let portState = MIDIPortState()

    // MARK: - 状態

    /// MIDI 入出力が稼働中かどうか。``start()`` が失敗した場合は false のままで、
    /// 失敗内容は ``lastError`` で確認できます。
    public private(set) var isRunning = false

    /// 直近の ``start()`` で発生したエラー。成功時は nil に戻ります。
    ///
    /// `start()` は Processing 風の使い勝手を保つため throws にしない代わりに、
    /// CoreMIDI の失敗（OSStatus）をこのプロパティで報告します。
    public private(set) var lastError: MIDIManagerError?

    /// [channel][cc] でインデックスされたキャッシュ済み CC 値。
    private var ccValues: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 128), count: 16)

    /// 現在押されているノート。
    private var activeNotes: Set<UInt16> = []  // channel << 8 | note

    // MARK: - スレッドセーフなメッセージキュー

    private let messageBuffer = MIDIMessageBuffer()

    // MARK: - コールバック

    private var noteOnHandler: ((_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void)?
    private var noteOffHandler: ((_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void)?
    private var controlChangeHandler: ((_ channel: UInt8, _ cc: UInt8, _ value: UInt8) -> Void)?

    // MARK: - 初期化

    /// MIDI マネージャーを作成します。
    public init() {}

    // MARK: - ライフサイクル

    /// MIDI 入出力を開始します。
    ///
    /// 失敗した場合は ``isRunning`` が false のままとなり、``lastError`` に
    /// 失敗内容（CoreMIDI の OSStatus）が入ります。
    /// 起動後に接続された MIDI デバイスもホットプラグ通知で自動的に接続されます。
    public func start() {
        guard !isRunning else { return }
        lastError = nil

        let buffer = messageBuffer
        let ports = portState

        // MIDI クライアントを作成。notify ブロックはデバイスの接続・切断・
        // 設定変更で呼ばれる（ホットプラグ対応。CoreMIDI が任意スレッドで
        // 呼び得るため、Sendable な portState 経由の nonisolated 実装で張り直す）
        var clientRef: MIDIClientRef = 0
        var status = MIDIClientCreateWithBlock("metaphor.midi" as CFString, &clientRef) { notification in
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
                MIDIManager.reconnectSources(portState: ports)
            default:
                break
            }
        }
        guard status == noErr else {
            lastError = .clientCreationFailed(status)
            debugWarning("MIDIClientCreateWithBlock failed: \(status)")
            return
        }

        // 入力ポートを作成
        var inPort: MIDIPortRef = 0
        status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "metaphor.midi.in" as CFString,
            ._1_0,
            &inPort
        ) { eventList, _ in
            // MIDIEventList をパース
            let messages = MIDIManager.parseEventList(eventList)
            buffer.append(messages)
        }
        guard status == noErr else {
            MIDIClientDispose(clientRef)
            lastError = .inputPortCreationFailed(status)
            debugWarning("MIDIInputPortCreateWithProtocol failed: \(status)")
            return
        }

        // 出力ポートを作成
        var outPort: MIDIPortRef = 0
        status = MIDIOutputPortCreate(clientRef, "metaphor.midi.out" as CFString, &outPort)
        guard status == noErr else {
            MIDIPortDispose(inPort)
            MIDIClientDispose(clientRef)
            lastError = .outputPortCreationFailed(status)
            debugWarning("MIDIOutputPortCreate failed: \(status)")
            return
        }

        portState.set(client: clientRef, inputPort: inPort, outputPort: outPort)

        // 利用可能なすべてのソースに接続
        Self.reconnectSources(portState: portState)

        isRunning = true
    }

    /// 現在のソース一覧に合わせて入力ポートの接続を張り直します。
    ///
    /// `start()` 時とホットプラグ通知（追加・削除・設定変更）の両方から呼ばれます。
    /// 通知は CoreMIDI の任意スレッドで届き得るため nonisolated で実装し、
    /// 共有状態は Sendable な `MIDIPortState` に限定します（CoreMIDI API 自体は
    /// スレッドセーフ）。
    private nonisolated static func reconnectSources(portState: MIDIPortState) {
        let inPort = portState.inputPort
        guard inPort != 0 else { return }

        var connected: [MIDIEndpointRef] = []
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            if MIDIPortConnectSource(inPort, source, nil) == noErr {
                connected.append(source)
            }
        }

        // 消えたソースへの接続を解除（二重接続は上の ConnectSource が同一ソースに
        // 対して冪等なため問題にならないが、切断済みの参照は明示的に外す）
        let previous = portState.replaceConnectedSources(connected)
        for old in previous where !connected.contains(old) {
            MIDIPortDisconnectSource(inPort, old)
        }
    }

    deinit {
        portState.dispose()
    }

    /// MIDI 入出力を停止します。
    public func stop() {
        guard isRunning else { return }
        portState.dispose()
        isRunning = false
    }

    // MARK: - 入力: ポーリング

    /// 受信したメッセージをポーリングし、登録済みコールバックを呼び出します。
    ///
    /// `draw()` の先頭で呼び出してください。
    /// - Returns: 受信した MIDI メッセージの配列。
    public func poll() -> [MIDIMessage] {
        let messages = messageBuffer.drain()
        for msg in messages {
            processMessage(msg)
        }
        return messages
    }

    // MARK: - 入力: CC 値アクセス

    /// 正規化された CC 値を返します（0.0〜1.0）。
    /// - Parameters:
    ///   - cc: CC 番号（0-127）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    /// - Returns: 正規化された CC 値。
    public func controllerValue(_ cc: UInt8, channel: UInt8 = 0) -> Float {
        guard channel < 16, cc < 128 else { return 0 }
        return Float(ccValues[Int(channel)][Int(cc)]) / 127.0
    }

    /// 生の CC 値を返します（0〜127）。
    /// - Parameters:
    ///   - cc: CC 番号（0-127）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    /// - Returns: 生の CC 値。
    public func controllerRawValue(_ cc: UInt8, channel: UInt8 = 0) -> UInt8 {
        guard channel < 16, cc < 128 else { return 0 }
        return ccValues[Int(channel)][Int(cc)]
    }

    /// ノートが現在押されているかどうかを確認します。
    /// - Parameters:
    ///   - note: MIDI ノート番号（0-127）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    /// - Returns: ノートがアクティブであれば `true`。
    public func isNoteActive(_ note: UInt8, channel: UInt8 = 0) -> Bool {
        activeNotes.contains(UInt16(channel) << 8 | UInt16(note))
    }

    // MARK: - 入力: コールバック

    /// Note On コールバックを登録します。
    /// - Parameter handler: (channel, note, velocity) で呼び出されるクロージャ。
    public func onNoteOn(_ handler: @escaping (_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void) {
        noteOnHandler = handler
    }

    /// Note Off コールバックを登録します。
    /// - Parameter handler: (channel, note, velocity) で呼び出されるクロージャ。
    public func onNoteOff(_ handler: @escaping (_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void) {
        noteOffHandler = handler
    }

    /// Control Change コールバックを登録します。
    /// - Parameter handler: (channel, cc, value) で呼び出されるクロージャ。
    public func onControlChange(_ handler: @escaping (_ channel: UInt8, _ cc: UInt8, _ value: UInt8) -> Void) {
        controlChangeHandler = handler
    }

    // MARK: - 出力

    /// Note On メッセージを送信します。
    /// - Parameters:
    ///   - note: MIDI ノート番号（0-127）。
    ///   - velocity: ノートベロシティ（0-127、デフォルトは100）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    public func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMessage(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Note Off メッセージを送信します。
    /// - Parameters:
    ///   - note: MIDI ノート番号（0-127）。
    ///   - velocity: リリースベロシティ（0-127、デフォルトは0）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    public func sendNoteOff(note: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0) {
        sendMessage(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Control Change メッセージを送信します。
    /// - Parameters:
    ///   - cc: CC 番号（0-127）。
    ///   - value: CC 値（0-127）。
    ///   - channel: MIDI チャンネル（0-15、デフォルトは0）。
    public func sendControlChange(cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        sendMessage(status: 0xB0 | (channel & 0x0F), data1: cc, data2: value)
    }

    // MARK: - プライベート

    private func processMessage(_ msg: MIDIMessage) {
        if msg.isNoteOn {
            activeNotes.insert(UInt16(msg.channel) << 8 | UInt16(msg.note))
            noteOnHandler?(msg.channel, msg.note, msg.velocity)
        } else if msg.isNoteOff {
            activeNotes.remove(UInt16(msg.channel) << 8 | UInt16(msg.note))
            noteOffHandler?(msg.channel, msg.note, msg.velocity)
        } else if msg.isControlChange {
            ccValues[Int(msg.channel)][Int(msg.controlNumber)] = msg.controlValue
            controlChangeHandler?(msg.channel, msg.controlNumber, msg.controlValue)
        }
    }

    private func sendMessage(status: UInt8, data1: UInt8, data2: UInt8) {
        guard isRunning else { return }

        let destCount = MIDIGetNumberOfDestinations()
        guard destCount > 0 else { return }

        var eventList = MIDIEventList()
        var packet = MIDIEventListInit(&eventList, ._1_0)
        let words: [UInt32] = [
            UInt32(0x20000000) | UInt32(status) << 16 | UInt32(data1) << 8 | UInt32(data2)
        ]
        packet = MIDIEventListAdd(&eventList, 256, packet, 0, words.count, words)

        let outPort = portState.outputPort
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            MIDISendEventList(outPort, dest, &eventList)
        }
    }

    /// UMP メッセージタイプごとのワード数（MIDI 2.0 UMP 仕様）。
    /// マルチワードメッセージのペイロードを 1 ワードずつ走査すると、
    /// ペイロード内の偶然のビットパターンをメッセージとして誤認するため、
    /// メッセージ単位でスキップするのに使う。
    private nonisolated static func umpWordCount(forMessageType mt: UInt32) -> Int {
        switch mt {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4  // 0x5, 0xD, 0xE, 0xF
        }
    }

    // internal: テストから直接イベントリストを与えて検証できるようにする
    nonisolated static func parseEventList(_ eventList: UnsafePointer<MIDIEventList>) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []

        // MIDIEventList は可変長構造体。`pointee` でローカルにコピーすると
        // ヘッダ + 先頭パケットの固定領域しか複製されず、2 パケット目以降を
        // MIDIEventPacketNext で歩くとコピーの外（スタック外）を読む。
        // 必ず元のポインタ上を unsafeSequence() で反復する。
        for packetPtr in eventList.unsafeSequence() {
            let timestamp = packetPtr.pointee.timeStamp
            let wordCount = Int(packetPtr.pointee.wordCount)

            // パケットは詰めて配置されるため、words はコピーせず元バッファ上で
            // wordCount 分だけ読む
            let wordsBase = (UnsafeRawPointer(packetPtr) + MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                .assumingMemoryBound(to: UInt32.self)

            var i = 0
            while i < wordCount {
                let word = wordsBase[i]
                let messageType = (word >> 28) & 0x0F

                // Type 2: MIDI 1.0 チャンネルボイスメッセージ
                if messageType == 2 {
                    let statusByte = UInt8((word >> 16) & 0xFF)
                    let channel = statusByte & 0x0F
                    let d1 = UInt8((word >> 8) & 0x7F)
                    let d2 = UInt8(word & 0x7F)
                    messages.append(MIDIMessage(
                        status: statusByte,
                        channel: channel,
                        data1: d1,
                        data2: d2,
                        timestamp: timestamp
                    ))
                }

                // マルチワードメッセージはペイロードごとスキップ
                i += Self.umpWordCount(forMessageType: messageType)
            }
        }

        return messages
    }
}

// MARK: - スレッドセーフなメッセージバッファ

// internal: テストから上限動作を検証できるようにする
final class MIDIMessageBuffer: Sendable {
    private struct State {
        var messages: [MIDIMessage] = []
        var dropped: Int = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// バッファ上限（OSC 側のキューと同じ値）。`poll()` を呼ばないスケッチで
    /// メモリが無制限に成長するのを防ぐ。
    static let maxBufferSize = 10_000

    func append(_ messages: [MIDIMessage]) {
        state.withLock { s in
            let available = Self.maxBufferSize - s.messages.count
            guard available > 0 else {
                s.dropped += messages.count
                return
            }
            if messages.count <= available {
                s.messages.append(contentsOf: messages)
            } else {
                s.messages.append(contentsOf: messages.prefix(available))
                s.dropped += messages.count - available
            }
        }
    }

    func drain() -> [MIDIMessage] {
        let (msgs, dropped) = state.withLock { s -> ([MIDIMessage], Int) in
            let msgs = s.messages
            let dropped = s.dropped
            s.messages.removeAll(keepingCapacity: true)
            s.dropped = 0
            return (msgs, dropped)
        }
        if dropped > 0 {
            debugWarning("MIDI message buffer overflowed: dropped \(dropped) message(s) since last poll()")
        }
        return msgs
    }
}

// MARK: - エラー

/// MIDIManager 操作中に発生するエラーを表します。
public enum MIDIManagerError: Error, LocalizedError, Equatable {
    /// MIDI クライアントの作成に失敗したことを示します。
    case clientCreationFailed(OSStatus)
    /// 入力ポートの作成に失敗したことを示します。
    case inputPortCreationFailed(OSStatus)
    /// 出力ポートの作成に失敗したことを示します。
    case outputPortCreationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .clientCreationFailed(let status):
            return "Failed to create MIDI client (OSStatus \(status))"
        case .inputPortCreationFailed(let status):
            return "Failed to create MIDI input port (OSStatus \(status))"
        case .outputPortCreationFailed(let status):
            return "Failed to create MIDI output port (OSStatus \(status))"
        }
    }
}
