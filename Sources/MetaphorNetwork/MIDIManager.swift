import CoreMIDI
import Foundation
import os

/// Manage MIDI input and output connections.
///
/// Use CoreMIDI to connect to MIDI devices and send/receive messages.
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
// MARK: - Thread-safe CoreMIDI Port State

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

    // MARK: - CoreMIDI Refs

    private let portState = MIDIPortState()

    // MARK: - State

    private var isRunning = false

    /// Cached CC values indexed by [channel][cc].
    private var ccValues: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 128), count: 16)

    /// Currently held notes.
    private var activeNotes: Set<UInt16> = []  // channel << 8 | note

    // MARK: - Thread-safe Message Queue

    private let messageBuffer = MIDIMessageBuffer()

    // MARK: - Callbacks

    private var noteOnHandler: ((UInt8, UInt8, UInt8) -> Void)?
    private var noteOffHandler: ((UInt8, UInt8, UInt8) -> Void)?
    private var controlChangeHandler: ((UInt8, UInt8, UInt8) -> Void)?

    // MARK: - Initialization

    /// Create a MIDI manager.
    public init() {}

    // MARK: - Lifecycle

    /// Start MIDI input and output.
    public func start() {
        guard !isRunning else { return }

        let buffer = messageBuffer

        // Create MIDI client
        var clientRef: MIDIClientRef = 0
        MIDIClientCreateWithBlock("metaphor.midi" as CFString, &clientRef) { _ in
            // Device connect/disconnect notifications (future use)
        }

        // Create input port
        var inPort: MIDIPortRef = 0
        MIDIInputPortCreateWithProtocol(
            clientRef,
            "metaphor.midi.in" as CFString,
            ._1_0,
            &inPort
        ) { eventList, _ in
            // Parse MIDIEventList
            let messages = MIDIManager.parseEventList(eventList)
            buffer.append(messages)
        }

        // Create output port
        var outPort: MIDIPortRef = 0
        MIDIOutputPortCreate(clientRef, "metaphor.midi.out" as CFString, &outPort)

        portState.set(client: clientRef, inputPort: inPort, outputPort: outPort)

        // Connect to all available sources
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

    /// Stop MIDI input and output.
    public func stop() {
        guard isRunning else { return }
        portState.dispose()
        isRunning = false
    }

    // MARK: - Input: Polling

    /// Poll received messages and invoke registered callbacks.
    ///
    /// Call at the beginning of `draw()`.
    /// - Returns: Array of received MIDI messages.
    public func poll() -> [MIDIMessage] {
        let messages = messageBuffer.drain()
        for msg in messages {
            processMessage(msg)
        }
        return messages
    }

    // MARK: - Input: CC Value Access

    /// Return the normalized CC value (0.0 to 1.0).
    /// - Parameters:
    ///   - cc: CC number (0-127).
    ///   - channel: MIDI channel (0-15, defaults to 0).
    /// - Returns: Normalized CC value.
    public func controllerValue(_ cc: UInt8, channel: UInt8 = 0) -> Float {
        guard channel < 16, cc < 128 else { return 0 }
        return Float(ccValues[Int(channel)][Int(cc)]) / 127.0
    }

    /// Return the raw CC value (0 to 127).
    /// - Parameters:
    ///   - cc: CC number (0-127).
    ///   - channel: MIDI channel (0-15, defaults to 0).
    /// - Returns: Raw CC value.
    public func controllerRawValue(_ cc: UInt8, channel: UInt8 = 0) -> UInt8 {
        guard channel < 16, cc < 128 else { return 0 }
        return ccValues[Int(channel)][Int(cc)]
    }

    /// Check whether a note is currently held down.
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - channel: MIDI channel (0-15, defaults to 0).
    /// - Returns: `true` if the note is active.
    public func isNoteActive(_ note: UInt8, channel: UInt8 = 0) -> Bool {
        activeNotes.contains(UInt16(channel) << 8 | UInt16(note))
    }

    // MARK: - Input: Callbacks

    /// Register a Note On callback.
    /// - Parameter handler: Closure invoked with (channel, note, velocity).
    public func onNoteOn(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        noteOnHandler = handler
    }

    /// Register a Note Off callback.
    /// - Parameter handler: Closure invoked with (channel, note, velocity).
    public func onNoteOff(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        noteOffHandler = handler
    }

    /// Register a Control Change callback.
    /// - Parameter handler: Closure invoked with (channel, cc, value).
    public func onControlChange(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) {
        controlChangeHandler = handler
    }

    // MARK: - Output

    /// Send a Note On message.
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Note velocity (0-127, defaults to 100).
    ///   - channel: MIDI channel (0-15, defaults to 0).
    public func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMessage(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Send a Note Off message.
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Release velocity (0-127, defaults to 0).
    ///   - channel: MIDI channel (0-15, defaults to 0).
    public func sendNoteOff(note: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0) {
        sendMessage(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity)
    }

    /// Send a Control Change message.
    /// - Parameters:
    ///   - cc: CC number (0-127).
    ///   - value: CC value (0-127).
    ///   - channel: MIDI channel (0-15, defaults to 0).
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

                // UMP 1.0: parse each word
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
