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

// MARK: - 7-bit data bytes

/// UMP word の data1 (bit 8-15) と data2 (bit 0-7) を 8-bit のまま取り出します。
/// 7-bit でマスクして読むと範囲外ビットの混入自体が見えなくなるため、
/// 検証側はワイヤ上のバイトをそのまま取ります。
private func dataBytes(of word: UInt32) -> (data1: UInt8, data2: UInt8) {
    (UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF))
}

/// MIDI 1.0 Channel Voice メッセージの data byte は 7-bit。API の型は `UInt8`
/// なので 128〜255 も渡せてしまい、そのまま UMP word へ載せると規格外の
/// メッセージを送っていた (#583)。範囲外は 127 へ clamp する。
@Suite("MIDI 7-bit data bytes")
struct MIDIDataByteRangeTests {

    @Test("in-range data bytes pass through unchanged", arguments: [UInt8(0), 1, 64, 100, 126, 127])
    func inRangeUnchanged(value: UInt8) {
        let word = MIDIManager.makeChannelVoiceWord(status: 0x90, data1: value, data2: value)
        let bytes = dataBytes(of: word)
        #expect(bytes.data1 == value)
        #expect(bytes.data2 == value)
    }

    @Test("out-of-range data bytes are clamped to 127", arguments: [UInt8(128), 129, 200, 255])
    func outOfRangeClamped(value: UInt8) {
        let word = MIDIManager.makeChannelVoiceWord(status: 0x90, data1: value, data2: value)
        let bytes = dataBytes(of: word)
        // mask (& 0x7F) だと 128 → 0、255 → 127 と折り返して別の値に化ける
        #expect(bytes.data1 == 127)
        #expect(bytes.data2 == 127)
    }

    /// 折り返しを許すと velocity 128 が 0 になり、Note On が Note Off の意味に
    /// なる（`isNoteOn` は data2 > 0）。clamp ならその取り違えが起きない。
    @Test("velocity above the range stays a Note On")
    func loudVelocityStaysNoteOn() {
        let word = MIDIManager.makeChannelVoiceWord(status: 0x90, data1: 60, data2: 200)
        let bytes = dataBytes(of: word)
        #expect(bytes.data2 == 127)

        let messages = parseSingleWord(word)
        #expect(messages.count == 1)
        #expect(messages.first?.isNoteOn == true)
        #expect(messages.first?.isNoteOff == false)
        #expect(messages.first?.velocity == 127)
    }

    /// note 128 を折り返すと最高音のつもりが最低音になる。
    @Test("note above the range stays at the top of the range")
    func highNoteStaysHigh() {
        let word = MIDIManager.makeChannelVoiceWord(status: 0x90, data1: 130, data2: 100)
        #expect(dataBytes(of: word).data1 == 127)
    }

    /// data byte の clamp が status byte（上位ニブル + channel）と UMP の
    /// message type を巻き添えにしないこと。
    @Test("status byte and UMP message type survive clamping", arguments: [UInt8(0x90), 0x80, 0xB0, 0x9F, 0xBF])
    func statusPreserved(status: UInt8) {
        let word = MIDIManager.makeChannelVoiceWord(status: status, data1: 255, data2: 255)
        #expect(UInt8((word >> 16) & 0xFF) == status)
        #expect((word >> 28) & 0x0F == 2, "MIDI 1.0 Channel Voice は UMP message type 2")
    }

    /// 既存の channel マスク（`0x90 | (channel & 0x0F)`）は送信 API 側にあり、
    /// data byte の clamp を入れても意味が変わらないこと。
    @Test("channel mask keeps wrapping as before")
    func channelMaskUnchanged() {
        let word = MIDIManager.makeChannelVoiceWord(status: 0x90 | (UInt8(20) & 0x0F), data1: 60, data2: 100)
        #expect(UInt8((word >> 16) & 0xFF) == 0x94, "channel 20 は 4 へ折り返す（従来どおり）")
    }

    /// `MIDIMessage` は受信経路（`parseEventList`）では常に 7-bit だが、公開
    /// 初期化子だけ抜けていた。`pitchBendValue` / `normalizedControlValue` は
    /// 7-bit を前提に計算するため、ここでも不変条件を保つ。
    @Test("MIDIMessage clamps its data bytes")
    func messageInitClamps() {
        let msg = MIDIMessage(status: 0xB0, channel: 0, data1: 200, data2: 255)
        #expect(msg.data1 == 127)
        #expect(msg.data2 == 127)
        #expect(msg.normalizedControlValue == 1.0)
    }

    @Test("MIDIMessage keeps in-range data bytes")
    func messageInitInRange() {
        let msg = MIDIMessage(status: 0x90, channel: 3, data1: 60, data2: 127)
        #expect(msg.data1 == 60)
        #expect(msg.data2 == 127)
        #expect(msg.channel == 3)
        #expect(msg.status == 0x90)
    }
}

/// 単一ワードの `MIDIEventList` を組んでパースします。
private func parseSingleWord(_ word: UInt32) -> [MIDIMessage] {
    let capacity = 256
    let rawPtr = UnsafeMutableRawPointer.allocate(
        byteCount: capacity, alignment: MemoryLayout<MIDIEventList>.alignment)
    defer { rawPtr.deallocate() }
    let listPtr = rawPtr.assumingMemoryBound(to: MIDIEventList.self)

    var packet = MIDIEventListInit(listPtr, ._1_0)
    var word = word
    packet = MIDIEventListAdd(listPtr, capacity, packet, 1, 1, &word)
    _ = packet

    return MIDIManager.parseEventList(UnsafePointer(listPtr))
}

// MARK: - MIDIMessageBuffer

@Suite("MIDI message buffer")
struct MIDIMessageBufferTests {

    @Test("buffer is capped and drains report drops")
    func bufferCap() {
        let buffer = MIDIMessageBuffer()
        let batch = [MIDIMessage](
            repeating: MIDIMessage(status: 0x90, channel: 0, data1: 60, data2: 100),
            count: 6_000
        )
        // 上限 10,000 を超えて追加しても無制限には成長しない
        buffer.append(batch)
        buffer.append(batch)
        buffer.append(batch)

        let drained = buffer.drain()
        #expect(drained.count == MIDIMessageBuffer.maxBufferSize)
        // drain 後は再び追加できる
        buffer.append(batch)
        #expect(buffer.drain().count == 6_000)
    }
}
