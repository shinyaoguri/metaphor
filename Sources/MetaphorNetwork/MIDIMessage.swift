import Foundation

/// Represent a single MIDI message.
public struct MIDIMessage: Sendable {
    /// Status byte (upper 4 bits: message type, lower 4 bits: channel).
    public let status: UInt8

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// First data byte (note number or CC number).
    public let data1: UInt8

    /// Second data byte (velocity or CC value).
    public let data2: UInt8

    /// Timestamp of the message.
    public let timestamp: UInt64

    /// Create a MIDI message.
    /// - Parameters:
    ///   - status: Status byte.
    ///   - channel: MIDI channel (0-15).
    ///   - data1: First data byte.
    ///   - data2: Second data byte.
    ///   - timestamp: Timestamp (defaults to 0).
    public init(status: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64 = 0) {
        self.status = status
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.timestamp = timestamp
    }

    // MARK: - Message Type Detection

    /// Indicate whether this is a Note On message.
    public var isNoteOn: Bool {
        (status & 0xF0) == 0x90 && data2 > 0
    }

    /// Indicate whether this is a Note Off message.
    public var isNoteOff: Bool {
        (status & 0xF0) == 0x80 || ((status & 0xF0) == 0x90 && data2 == 0)
    }

    /// Indicate whether this is a Control Change message.
    public var isControlChange: Bool {
        (status & 0xF0) == 0xB0
    }

    /// Indicate whether this is a Program Change message.
    public var isProgramChange: Bool {
        (status & 0xF0) == 0xC0
    }

    /// Indicate whether this is a Pitch Bend message.
    public var isPitchBend: Bool {
        (status & 0xF0) == 0xE0
    }

    // MARK: - Convenience

    /// Return the note number (for Note On / Note Off messages).
    public var note: UInt8 { data1 }

    /// Return the velocity (for Note On / Note Off messages).
    public var velocity: UInt8 { data2 }

    /// Return the CC number (for Control Change messages).
    public var controlNumber: UInt8 { data1 }

    /// Return the CC value (for Control Change messages, 0-127).
    public var controlValue: UInt8 { data2 }

    /// Return the CC value normalized to 0.0-1.0.
    public var normalizedControlValue: Float {
        Float(data2) / 127.0
    }

    /// Return the pitch bend value (-8192 to 8191).
    public var pitchBendValue: Int16 {
        Int16(data1) | (Int16(data2) << 7) - 8192
    }
}

/// Define MIDI message types by their status byte.
public enum MIDIMessageType: UInt8, Sendable {
    case noteOff = 0x80
    case noteOn = 0x90
    case polyPressure = 0xA0
    case controlChange = 0xB0
    case programChange = 0xC0
    case channelPressure = 0xD0
    case pitchBend = 0xE0
}
