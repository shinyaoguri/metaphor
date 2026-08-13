import CoreMIDI
import Foundation
import os

/// Manages MIDI input/output connections.
///
/// Connects to MIDI devices and sends/receives messages using CoreMIDI.
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
        /// Sources currently connected to inputPort (used to reconnect on hot-plug).
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

    /// Replaces the list of connected sources and returns the previous list.
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

    /// Whether MIDI input/output is currently running. Stays false if
    /// ``start()`` fails; inspect the failure via ``lastError``.
    public private(set) var isRunning = false

    /// The error from the most recent ``start()`` call. Resets to nil on success.
    ///
    /// `start()` is not `throws` — to keep Processing-style ergonomics — and
    /// instead reports CoreMIDI failures (OSStatus) through this property.
    public private(set) var lastError: MIDIManagerError?

    /// Cached CC values, indexed by [channel][cc].
    private var ccValues: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 128), count: 16)

    /// Notes currently held down.
    private var activeNotes: Set<UInt16> = []  // channel << 8 | note

    // MARK: - スレッドセーフなメッセージキュー

    private let messageBuffer = MIDIMessageBuffer()

    // MARK: - コールバック

    private var noteOnHandler: ((_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void)?
    private var noteOffHandler: ((_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void)?
    private var controlChangeHandler: ((_ channel: UInt8, _ cc: UInt8, _ value: UInt8) -> Void)?

    // MARK: - 初期化

    /// Creates a MIDI manager.
    public init() {}

    // MARK: - ライフサイクル

    /// Starts MIDI input/output.
    ///
    /// On failure, ``isRunning`` stays false and ``lastError`` is set with
    /// the failure detail (the CoreMIDI OSStatus). MIDI devices connected
    /// after startup are also connected automatically via hot-plug notifications.
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

    /// Reconnects the input port to match the current list of sources.
    ///
    /// Called both from `start()` and from hot-plug notifications (added,
    /// removed, setup changed). Notifications can arrive on any CoreMIDI
    /// thread, so this is implemented `nonisolated` and confines shared
    /// state to the Sendable `MIDIPortState` (the CoreMIDI API itself is
    /// thread-safe).
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

    /// Stops MIDI input/output.
    public func stop() {
        guard isRunning else { return }
        portState.dispose()
        isRunning = false
    }

    // MARK: - 入力: ポーリング

    /// Polls received messages and invokes the registered callbacks.
    ///
    /// Call this at the top of `draw()`.
    /// - Returns: The array of received MIDI messages.
    public func poll() -> [MIDIMessage] {
        let messages = messageBuffer.drain()
        for msg in messages {
            processMessage(msg)
        }
        return messages
    }

    // MARK: - 入力: CC 値アクセス

    /// Returns the normalized CC value (0.0-1.0).
    /// - Parameters:
    ///   - cc: The CC number (0-127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
    /// - Returns: The normalized CC value.
    public func controllerValue(_ cc: UInt8, channel: UInt8 = 0) -> Float {
        guard channel < 16, cc < 128 else { return 0 }
        return Float(ccValues[Int(channel)][Int(cc)]) / 127.0
    }

    /// Returns the raw CC value (0-127).
    /// - Parameters:
    ///   - cc: The CC number (0-127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
    /// - Returns: The raw CC value.
    public func controllerRawValue(_ cc: UInt8, channel: UInt8 = 0) -> UInt8 {
        guard channel < 16, cc < 128 else { return 0 }
        return ccValues[Int(channel)][Int(cc)]
    }

    /// Checks whether a note is currently held down.
    /// - Parameters:
    ///   - note: The MIDI note number (0-127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
    /// - Returns: `true` if the note is active.
    public func isNoteActive(_ note: UInt8, channel: UInt8 = 0) -> Bool {
        activeNotes.contains(UInt16(channel) << 8 | UInt16(note))
    }

    // MARK: - 入力: コールバック

    /// Registers a Note On callback.
    /// - Parameter handler: A closure called with (channel, note, velocity).
    public func onNoteOn(_ handler: @escaping (_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void) {
        noteOnHandler = handler
    }

    /// Registers a Note Off callback.
    /// - Parameter handler: A closure called with (channel, note, velocity).
    public func onNoteOff(_ handler: @escaping (_ channel: UInt8, _ note: UInt8, _ velocity: UInt8) -> Void) {
        noteOffHandler = handler
    }

    /// Registers a Control Change callback.
    /// - Parameter handler: A closure called with (channel, cc, value).
    public func onControlChange(_ handler: @escaping (_ channel: UInt8, _ cc: UInt8, _ value: UInt8) -> Void) {
        controlChangeHandler = handler
    }

    // MARK: - 出力

    /// Sends a Note On message.
    ///
    /// MIDI 1.0 data bytes are 7-bit: a `note` or `velocity` above 127 is sent as
    /// 127 (with a debug warning) rather than wrapping around to a low value.
    /// - Parameters:
    ///   - note: The MIDI note number (0-127; higher values are sent as 127).
    ///   - velocity: The note velocity (0-127, defaults to 100; higher values are sent as 127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
    public func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMessage(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Sends a Note Off message.
    ///
    /// MIDI 1.0 data bytes are 7-bit: a `note` or `velocity` above 127 is sent as
    /// 127 (with a debug warning) rather than wrapping around to a low value.
    /// - Parameters:
    ///   - note: The MIDI note number (0-127; higher values are sent as 127).
    ///   - velocity: The release velocity (0-127, defaults to 0; higher values are sent as 127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
    public func sendNoteOff(note: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0) {
        sendMessage(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Sends a Control Change message.
    ///
    /// MIDI 1.0 data bytes are 7-bit: a `cc` or `value` above 127 is sent as 127
    /// (with a debug warning) rather than wrapping around to a low value.
    /// - Parameters:
    ///   - cc: The CC number (0-127; higher values are sent as 127).
    ///   - value: The CC value (0-127; higher values are sent as 127).
    ///   - channel: The MIDI channel (0-15, defaults to 0).
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
        // 範囲外は clamp して送るが、値が黙って変わる方が原因を追いにくいので
        // DEBUG ビルドでだけ知らせる（Release では呼び出しごと消える）。
        if data1 > 127 || data2 > 127 {
            debugWarning(
                "MIDI data byte out of range (data1: \(data1), data2: \(data2)). "
                    + "MIDI 1.0 data bytes are 7-bit — values above 127 are sent as 127")
        }
        guard isRunning else { return }

        let destCount = MIDIGetNumberOfDestinations()
        guard destCount > 0 else { return }

        var eventList = MIDIEventList()
        var packet = MIDIEventListInit(&eventList, ._1_0)
        let words: [UInt32] = [
            Self.makeChannelVoiceWord(status: status, data1: data1, data2: data2)
        ]
        packet = MIDIEventListAdd(&eventList, 256, packet, 0, words.count, words)

        let outPort = portState.outputPort
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            MIDISendEventList(outPort, dest, &eventList)
        }
    }

    /// Builds the single UMP word of a MIDI 1.0 Channel Voice message.
    ///
    /// Data bytes are 7-bit on the wire, so anything above 127 is clamped rather
    /// than masked. Masking wraps: a velocity of 128 would become 0, turning a
    /// Note On into a Note Off, and a note of 128 would sound as the lowest note
    /// instead of the highest. Clamping pins an out-of-range parameter at the top
    /// of the range, where it is audible as saturation rather than as a jump.
    // internal: テストから生成ワードのビット列を直接検証できるようにする
    nonisolated static func makeChannelVoiceWord(status: UInt8, data1: UInt8, data2: UInt8) -> UInt32 {
        UInt32(0x20000000) | UInt32(status) << 16 | UInt32(min(data1, 127)) << 8 | UInt32(min(data2, 127))
    }

    /// The word count per UMP message type (MIDI 2.0 UMP spec). Used to skip
    /// whole messages at once — walking a multi-word message's payload one
    /// word at a time would risk misreading an incidental bit pattern in the
    /// payload as a message.
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

    /// The buffer limit (same value as the OSC-side queue). Prevents
    /// unbounded memory growth for sketches that never call `poll()`.
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

/// Represents errors that can occur during `MIDIManager` operations.
public enum MIDIManagerError: Error, LocalizedError, Equatable {
    /// Indicates that creating the MIDI client failed.
    case clientCreationFailed(OSStatus)
    /// Indicates that creating the input port failed.
    case inputPortCreationFailed(OSStatus)
    /// Indicates that creating the output port failed.
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
