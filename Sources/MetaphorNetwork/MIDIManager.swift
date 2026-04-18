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
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func set(client: MIDIClientRef, inputPort: MIDIPortRef, outputPort: MIDIPortRef) {
        state.withLock { s in
            s.client = client
            s.inputPort = inputPort
            s.outputPort = outputPort
        }
    }

    var outputPort: MIDIPortRef {
        state.withLock { $0.outputPort }
    }

    func dispose() {
        state.withLock { s in
            if s.inputPort != 0 { MIDIPortDispose(s.inputPort); s.inputPort = 0 }
            if s.outputPort != 0 { MIDIPortDispose(s.outputPort); s.outputPort = 0 }
            if s.client != 0 { MIDIClientDispose(s.client); s.client = 0 }
        }
    }
}

@MainActor
public final class MIDIManager {

    // MARK: - CoreMIDI 参照

    private let portState = MIDIPortState()

    // MARK: - 状態

    private var isRunning = false

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
    public func start() {
        guard !isRunning else { return }

        let buffer = messageBuffer

        // MIDI クライアントを作成
        var clientRef: MIDIClientRef = 0
        MIDIClientCreateWithBlock("metaphor.midi" as CFString, &clientRef) { _ in
            // デバイス接続・切断通知（将来使用）
        }

        // 入力ポートを作成
        var inPort: MIDIPortRef = 0
        MIDIInputPortCreateWithProtocol(
            clientRef,
            "metaphor.midi.in" as CFString,
            ._1_0,
            &inPort
        ) { eventList, _ in
            // MIDIEventList をパース
            let messages = MIDIManager.parseEventList(eventList)
            buffer.append(messages)
        }

        // 出力ポートを作成
        var outPort: MIDIPortRef = 0
        MIDIOutputPortCreate(clientRef, "metaphor.midi.out" as CFString, &outPort)

        portState.set(client: clientRef, inputPort: inPort, outputPort: outPort)

        // 利用可能なすべてのソースに接続
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inPort, source, nil)
        }

        isRunning = true
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

    private nonisolated static func parseEventList(_ eventList: UnsafePointer<MIDIEventList>) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []
        let list = eventList.pointee

        withUnsafePointer(to: list.packet) { firstPacket in
            var packet = firstPacket
            for _ in 0..<list.numPackets {
                let p = packet.pointee
                let timestamp = p.timeStamp

                // UMP 1.0: 各ワードをパース
                withUnsafePointer(to: p.words) { wordsPtr in
                    wordsPtr.withMemoryRebound(to: UInt32.self, capacity: Int(p.wordCount)) { words in
                        for i in 0..<Int(p.wordCount) {
                            let word = words[i]
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
                        }
                    }
                }

                packet = UnsafePointer(MIDIEventPacketNext(UnsafeMutablePointer(mutating: packet)))
            }
        }

        return messages
    }
}

// MARK: - スレッドセーフなメッセージバッファ

private final class MIDIMessageBuffer: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [MIDIMessage]())

    func append(_ messages: [MIDIMessage]) {
        state.withLock { $0.append(contentsOf: messages) }
    }

    func drain() -> [MIDIMessage] {
        state.withLock { s in
            let msgs = s
            s.removeAll(keepingCapacity: true)
            return msgs
        }
    }
}
