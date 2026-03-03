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
