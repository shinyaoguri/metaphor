import Foundation

/// Represents a single MIDI message.
public struct MIDIMessage: Sendable {
    /// The status byte (upper 4 bits: message type, lower 4 bits: channel).
    public let status: UInt8

    /// The MIDI channel (0-15).
    public let channel: UInt8

    /// The first data byte (note number or CC number, 0-127).
    public let data1: UInt8

    /// The second data byte (velocity or CC value, 0-127).
    public let data2: UInt8

    /// The message's timestamp.
    public let timestamp: UInt64

    /// Creates a MIDI message.
    ///
    /// MIDI 1.0 data bytes are 7-bit, so `data1` / `data2` above 127 are stored
    /// as 127. Received messages are already 7-bit; clamping here puts
    /// hand-built messages on the same footing, so ``pitchBendValue`` and
    /// ``normalizedControlValue`` are never read off a value they cannot express.
    /// - Parameters:
    ///   - status: The status byte.
    ///   - channel: The MIDI channel (0-15).
    ///   - data1: The first data byte (0-127; higher values are stored as 127).
    ///   - data2: The second data byte (0-127; higher values are stored as 127).
    ///   - timestamp: The timestamp (defaults to 0).
    public init(status: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64 = 0) {
        self.status = status
        self.channel = channel
        self.data1 = min(data1, 127)
        self.data2 = min(data2, 127)
        self.timestamp = timestamp
    }

    // MARK: - メッセージタイプ判定

    /// Indicates whether this is a Note On message.
    public var isNoteOn: Bool {
        (status & 0xF0) == 0x90 && data2 > 0
    }

    /// Indicates whether this is a Note Off message.
    public var isNoteOff: Bool {
        (status & 0xF0) == 0x80 || ((status & 0xF0) == 0x90 && data2 == 0)
    }

    /// Indicates whether this is a Control Change message.
    public var isControlChange: Bool {
        (status & 0xF0) == 0xB0
    }

    /// Indicates whether this is a Program Change message.
    public var isProgramChange: Bool {
        (status & 0xF0) == 0xC0
    }

    /// Indicates whether this is a Pitch Bend message.
    public var isPitchBend: Bool {
        (status & 0xF0) == 0xE0
    }

    // MARK: - 便利プロパティ

    /// Returns the note number (for Note On / Note Off messages).
    public var note: UInt8 { data1 }

    /// Returns the velocity (for Note On / Note Off messages).
    public var velocity: UInt8 { data2 }

    /// Returns the CC number (for Control Change messages).
    public var controlNumber: UInt8 { data1 }

    /// Returns the CC value (for Control Change messages, 0-127).
    public var controlValue: UInt8 { data2 }

    /// Returns the CC value normalized to 0.0-1.0.
    public var normalizedControlValue: Float {
        Float(data2) / 127.0
    }

    /// Returns the pitch bend value (-8192 to 8191).
    public var pitchBendValue: Int16 {
        Int16(data1) | (Int16(data2) << 7) - 8192
    }
}

/// Defines MIDI message types by status byte.
public enum MIDIMessageType: UInt8, Sendable {
    case noteOff = 0x80
    case noteOn = 0x90
    case polyPressure = 0xA0
    case controlChange = 0xB0
    case programChange = 0xC0
    case channelPressure = 0xD0
    case pitchBend = 0xE0
}
