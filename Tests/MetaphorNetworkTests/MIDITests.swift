import Testing
@testable import MetaphorNetwork

// MARK: - MIDI Message

@Suite("MIDI Message")
struct MIDIMessageTests {

    @Test("Note On detection")
    func noteOn() {
        let msg = MIDIMessage(status: 0x90, channel: 0, data1: 60, data2: 100)
        #expect(msg.isNoteOn == true)
        #expect(msg.isNoteOff == false)
        #expect(msg.note == 60)
        #expect(msg.velocity == 100)
    }

    @Test("Note Off detection (0x80)")
    func noteOff() {
        let msg = MIDIMessage(status: 0x80, channel: 0, data1: 60, data2: 0)
        #expect(msg.isNoteOff == true)
        #expect(msg.isNoteOn == false)
    }

    @Test("Note Off via velocity 0 on Note On")
    func noteOffViaVelocityZero() {
        let msg = MIDIMessage(status: 0x90, channel: 0, data1: 60, data2: 0)
        #expect(msg.isNoteOff == true)
        #expect(msg.isNoteOn == false)
    }

    @Test("Control Change detection")
    func controlChange() {
        let msg = MIDIMessage(status: 0xB0, channel: 5, data1: 1, data2: 64)
        #expect(msg.isControlChange == true)
        #expect(msg.channel == 5)
        #expect(msg.controlNumber == 1)
        #expect(msg.controlValue == 64)
        #expect(abs(msg.normalizedControlValue - 0.5039) < 0.01)
    }

    @Test("Program Change detection")
    func programChange() {
        let msg = MIDIMessage(status: 0xC0, channel: 0, data1: 10, data2: 0)
        #expect(msg.isProgramChange == true)
    }

    @Test("Pitch Bend detection")
    func pitchBend() {
        let msg = MIDIMessage(status: 0xE0, channel: 0, data1: 0, data2: 64)
        #expect(msg.isPitchBend == true)
    }

    @Test("MIDIMessageType enum values")
    func messageTypes() {
        #expect(MIDIMessageType.noteOn.rawValue == 0x90)
        #expect(MIDIMessageType.noteOff.rawValue == 0x80)
        #expect(MIDIMessageType.controlChange.rawValue == 0xB0)
        #expect(MIDIMessageType.programChange.rawValue == 0xC0)
        #expect(MIDIMessageType.pitchBend.rawValue == 0xE0)
        #expect(MIDIMessageType.polyPressure.rawValue == 0xA0)
        #expect(MIDIMessageType.channelPressure.rawValue == 0xD0)
    }
}

// MARK: - MIDI Manager

@Suite("MIDI Manager")
@MainActor
struct MIDIManagerTests {

    @Test("MIDIManager initializes with default CC values")
    func defaultValues() {
        let midi = MIDIManager()
        #expect(midi.controllerValue(0) == 0)
        #expect(midi.controllerValue(1) == 0)
        #expect(midi.controllerRawValue(127) == 0)
    }

    @Test("MIDIManager isNoteActive returns false before start")
    func noActiveNotes() {
        let midi = MIDIManager()
        #expect(midi.isNoteActive(60) == false)
        #expect(midi.isNoteActive(127, channel: 15) == false)
    }

    @Test("MIDIManager poll returns empty before start")
    func emptyPoll() {
        let midi = MIDIManager()
        let msgs = midi.poll()
        #expect(msgs.isEmpty)
    }

    @Test("controllerValue bounds check")
    func ccBoundsCheck() {
        let midi = MIDIManager()
        // Out of bounds returns 0
        #expect(midi.controllerValue(200) == 0)
        #expect(midi.controllerValue(0, channel: 20) == 0)
    }
}

import CoreMIDI

// MARK: - MIDIEventList parsing

@Suite("MIDIEventList parsing")
struct MIDIEventListParsingTests {

    /// 複数パケットの MIDIEventList をヒープ上に構築してパースします。
    /// 以前の実装は eventList.pointee のローカルコピー上を MIDIEventPacketNext で
    /// 歩いていたため、2 パケット目以降はスタック外読み取りだった。
    @Test("multi-packet event list parses every packet")
    func multiPacketParsing() {
        let capacity = 4096
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: capacity, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { rawPtr.deallocate() }
        let listPtr = rawPtr.assumingMemoryBound(to: MIDIEventList.self)

        var packet = MIDIEventListInit(listPtr, ._1_0)
        let noteCount = 10
        for k in 0..<noteCount {
            // Note On, channel 0, note 60+k, velocity 100
            var word: UInt32 = 0x2090_0000 | UInt32(60 + k) << 8 | 100
            // タイムスタンプを変えて個別のパケットに分割させる
            packet = MIDIEventListAdd(listPtr, capacity, packet, MIDITimeStamp(k + 1), 1, &word)
        }
        #expect(listPtr.pointee.numPackets > 1, "Test requires multiple packets to exercise packet iteration")

        let messages = MIDIManager.parseEventList(UnsafePointer(listPtr))
        #expect(messages.count == noteCount)
        for (k, msg) in messages.enumerated() {
            #expect(msg.status == 0x90)
            #expect(msg.data1 == UInt8(60 + k))
            #expect(msg.data2 == 100)
        }
    }

    /// マルチワード UMP メッセージのペイロードがメッセージとして誤認されないこと。
    @Test("multi-word UMP payload words are not misparsed as messages")
    func multiWordPayloadSkipped() {
        let capacity = 1024
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: capacity, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { rawPtr.deallocate() }
        let listPtr = rawPtr.assumingMemoryBound(to: MIDIEventList.self)

        var packet = MIDIEventListInit(listPtr, ._2_0)
        // Type 4 (MIDI 2.0 channel voice, 2 ワード) — 2 ワード目の上位ニブルが
        // 偶然 0x2 になるペイロード。1 ワードずつ走査する実装はこれを
        // MIDI 1.0 メッセージとして誤認する。
        var words: [UInt32] = [0x4090_3C00, 0x2ABC_DEF0, 0x2091_3C40]
        packet = MIDIEventListAdd(listPtr, capacity, packet, 1, words.count, &words)
        _ = packet

        let messages = MIDIManager.parseEventList(UnsafePointer(listPtr))
        #expect(messages.count == 1, "Only the real type-2 word should parse (got \(messages.count))")
        #expect(messages.first?.status == 0x91)
        #expect(messages.first?.data1 == 0x3C)
        #expect(messages.first?.data2 == 0x40)
    }
}
