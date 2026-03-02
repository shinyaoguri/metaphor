import CoreMIDI
import Foundation

/// MIDI 入出力マネージャー
///
/// CoreMIDI を使用して MIDI デバイスとの接続、メッセージの送受信を行う。
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
@MainActor
public final class MIDIManager {

    // MARK: - CoreMIDI Refs

    private nonisolated(unsafe) var client: MIDIClientRef = 0
    private nonisolated(unsafe) var inputPort: MIDIPortRef = 0
    private nonisolated(unsafe) var outputPort: MIDIPortRef = 0

    // MARK: - State

    private var isRunning = false

    /// CC 値のキャッシュ（[channel][cc] = value）
    private var ccValues: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 128), count: 16)

    /// 現在押されているノート
    private var activeNotes: Set<UInt16> = []  // channel << 8 | note

    // MARK: - Thread-safe Message Queue

    private let messageBuffer = MIDIMessageBuffer()

    // MARK: - Callbacks

    private var noteOnHandler: ((UInt8, UInt8, UInt8) -> Void)?
    private var noteOffHandler: ((UInt8, UInt8, UInt8) -> Void)?
    private var controlChangeHandler: ((UInt8, UInt8, UInt8) -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Lifecycle

    /// MIDI 入出力を開始
    public func start() {
        guard !isRunning else { return }

        let buffer = messageBuffer

        // MIDI Client 作成
        var clientRef: MIDIClientRef = 0
        MIDIClientCreateWithBlock("metaphor.midi" as CFString, &clientRef) { _ in
            // デバイス接続/切断通知（必要なら将来対応）
        }
        client = clientRef

        // Input Port 作成
        var inPort: MIDIPortRef = 0
        MIDIInputPortCreateWithProtocol(
            client,
            "metaphor.midi.in" as CFString,
            ._1_0,
            &inPort
        ) { eventList, _ in
            // MIDIEventList をパース
            let messages = MIDIManager.parseEventList(eventList)
            buffer.append(messages)
        }
        inputPort = inPort

        // Output Port 作成
        var outPort: MIDIPortRef = 0
        MIDIOutputPortCreate(client, "metaphor.midi.out" as CFString, &outPort)
        outputPort = outPort

        // 全ソースに接続
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }

        isRunning = true
    }

    /// MIDI 入出力を停止
    public func stop() {
        guard isRunning else { return }

        MIDIPortDispose(inputPort)
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)

        inputPort = 0
        outputPort = 0
        client = 0
        isRunning = false
    }

    // MARK: - Input: Polling

    /// 受信したメッセージを取得してコールバックを呼ぶ
    /// draw() の先頭で呼ぶ
    public func poll() -> [MIDIMessage] {
        let messages = messageBuffer.drain()
        for msg in messages {
            processMessage(msg)
        }
        return messages
    }

    // MARK: - Input: CC Value Access

    /// CC 値を取得（0〜127）
    /// - Parameters:
    ///   - cc: CC 番号（0-127）
    ///   - channel: MIDI チャンネル（0-15、デフォルト0）
    public func controllerValue(_ cc: UInt8, channel: UInt8 = 0) -> Float {
        guard channel < 16, cc < 128 else { return 0 }
        return Float(ccValues[Int(channel)][Int(cc)]) / 127.0
    }

    /// CC の生値を取得（0〜127）
    public func controllerRawValue(_ cc: UInt8, channel: UInt8 = 0) -> UInt8 {
        guard channel < 16, cc < 128 else { return 0 }
        return ccValues[Int(channel)][Int(cc)]
    }

    /// ノートが押されているか
    public func isNoteActive(_ note: UInt8, channel: UInt8 = 0) -> Bool {
        activeNotes.contains(UInt16(channel) << 8 | UInt16(note))
    }

    // MARK: - Input: Callbacks

    /// Note On コールバック設定
    /// - Parameter handler: (channel, note, velocity) -> Void
    public func onNoteOn(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        noteOnHandler = handler
    }

    /// Note Off コールバック設定
    /// - Parameter handler: (channel, note, velocity) -> Void
    public func onNoteOff(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        noteOffHandler = handler
    }

    /// Control Change コールバック設定
    /// - Parameter handler: (channel, cc, value) -> Void
    public func onControlChange(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        controlChangeHandler = handler
    }

    // MARK: - Output

    /// Note On を送信
    public func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMessage(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Note Off を送信
    public func sendNoteOff(note: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0) {
        sendMessage(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Control Change を送信
    public func sendControlChange(cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        sendMessage(status: 0xB0 | (channel & 0x0F), data1: cc, data2: value)
    }

    // MARK: - Private

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

        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            MIDISendEventList(outputPort, dest, &eventList)
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

                // UMP 1.0: 各ワードを解析
                withUnsafePointer(to: p.words) { wordsPtr in
                    wordsPtr.withMemoryRebound(to: UInt32.self, capacity: Int(p.wordCount)) { words in
                        for i in 0..<Int(p.wordCount) {
                            let word = words[i]
                            let messageType = (word >> 28) & 0x0F

                            // Type 2: MIDI 1.0 Channel Voice Message
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

// MARK: - Thread-safe Message Buffer

private final class MIDIMessageBuffer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _messages: [MIDIMessage] = []

    func append(_ messages: [MIDIMessage]) {
        lock.lock()
        _messages.append(contentsOf: messages)
        lock.unlock()
    }

    func drain() -> [MIDIMessage] {
        lock.lock()
        let msgs = _messages
        _messages.removeAll(keepingCapacity: true)
        lock.unlock()
        return msgs
    }
}
