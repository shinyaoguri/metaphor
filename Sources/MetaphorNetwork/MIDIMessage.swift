import Foundation

/// 単一の MIDI メッセージを表します。
public struct MIDIMessage: Sendable {
    /// ステータスバイト（上位4ビット: メッセージタイプ、下位4ビット: チャンネル）。
    public let status: UInt8

    /// MIDI チャンネル（0-15）。
    public let channel: UInt8

    /// 第1データバイト（ノート番号または CC 番号）。
    public let data1: UInt8

    /// 第2データバイト（ベロシティまたは CC 値）。
    public let data2: UInt8

    /// メッセージのタイムスタンプ。
    public let timestamp: UInt64

    /// MIDI メッセージを作成します。
    /// - Parameters:
    ///   - status: ステータスバイト。
    ///   - channel: MIDI チャンネル（0-15）。
    ///   - data1: 第1データバイト。
    ///   - data2: 第2データバイト。
    ///   - timestamp: タイムスタンプ（デフォルトは0）。
    public init(status: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64 = 0) {
        self.status = status
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.timestamp = timestamp
    }

    // MARK: - メッセージタイプ判定

    /// Note On メッセージかどうかを示します。
    public var isNoteOn: Bool {
        (status & 0xF0) == 0x90 && data2 > 0
    }

    /// Note Off メッセージかどうかを示します。
    public var isNoteOff: Bool {
        (status & 0xF0) == 0x80 || ((status & 0xF0) == 0x90 && data2 == 0)
    }

    /// Control Change メッセージかどうかを示します。
    public var isControlChange: Bool {
        (status & 0xF0) == 0xB0
    }

    /// Program Change メッセージかどうかを示します。
    public var isProgramChange: Bool {
        (status & 0xF0) == 0xC0
    }

    /// Pitch Bend メッセージかどうかを示します。
    public var isPitchBend: Bool {
        (status & 0xF0) == 0xE0
    }

    // MARK: - 便利プロパティ

    /// ノート番号を返します（Note On / Note Off メッセージ用）。
    public var note: UInt8 { data1 }

    /// ベロシティを返します（Note On / Note Off メッセージ用）。
    public var velocity: UInt8 { data2 }

    /// CC 番号を返します（Control Change メッセージ用）。
    public var controlNumber: UInt8 { data1 }

    /// CC 値を返します（Control Change メッセージ用、0-127）。
    public var controlValue: UInt8 { data2 }

    /// CC 値を 0.0〜1.0 に正規化して返します。
    public var normalizedControlValue: Float {
        Float(data2) / 127.0
    }

    /// ピッチベンド値を返します（-8192〜8191）。
    public var pitchBendValue: Int16 {
        Int16(data1) | (Int16(data2) << 7) - 8192
    }
}

/// ステータスバイトによる MIDI メッセージタイプの定義。
public enum MIDIMessageType: UInt8, Sendable {
    case noteOff = 0x80
    case noteOn = 0x90
    case polyPressure = 0xA0
    case controlChange = 0xB0
    case programChange = 0xC0
    case channelPressure = 0xD0
    case pitchBend = 0xE0
}
