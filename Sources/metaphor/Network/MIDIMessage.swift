import Foundation

/// MIDI メッセージ
public struct MIDIMessage: Sendable {
    /// ステータスバイト（上位4ビット: メッセージタイプ、下位4ビット: チャンネル）
    public let status: UInt8

    /// チャンネル（0-15）
    public let channel: UInt8

    /// データバイト1（ノート番号 / CC番号）
    public let data1: UInt8

    /// データバイト2（ベロシティ / CC値）
    public let data2: UInt8

    /// タイムスタンプ
    public let timestamp: UInt64

    public init(status: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64 = 0) {
        self.status = status
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.timestamp = timestamp
    }

    // MARK: - Message Type Detection

    /// Note On メッセージか
    public var isNoteOn: Bool {
        (status & 0xF0) == 0x90 && data2 > 0
    }

    /// Note Off メッセージか
    public var isNoteOff: Bool {
        (status & 0xF0) == 0x80 || ((status & 0xF0) == 0x90 && data2 == 0)
    }

    /// Control Change メッセージか
    public var isControlChange: Bool {
        (status & 0xF0) == 0xB0
    }

    /// Program Change メッセージか
    public var isProgramChange: Bool {
        (status & 0xF0) == 0xC0
    }

    /// Pitch Bend メッセージか
    public var isPitchBend: Bool {
        (status & 0xF0) == 0xE0
    }

    // MARK: - Convenience

    /// ノート番号（Note On / Note Off）
    public var note: UInt8 { data1 }

    /// ベロシティ（Note On / Note Off）
    public var velocity: UInt8 { data2 }

    /// CC 番号（Control Change）
    public var controlNumber: UInt8 { data1 }

    /// CC 値（Control Change、0-127）
    public var controlValue: UInt8 { data2 }

    /// CC 値を 0.0〜1.0 に正規化
    public var normalizedControlValue: Float {
        Float(data2) / 127.0
    }

    /// Pitch Bend 値（-8192〜8191）
    public var pitchBendValue: Int16 {
        Int16(data1) | (Int16(data2) << 7) - 8192
    }
}

/// MIDI メッセージタイプ
public enum MIDIMessageType: UInt8, Sendable {
    case noteOff = 0x80
    case noteOn = 0x90
    case polyPressure = 0xA0
    case controlChange = 0xB0
    case programChange = 0xC0
    case channelPressure = 0xD0
    case pitchBend = 0xE0
}
