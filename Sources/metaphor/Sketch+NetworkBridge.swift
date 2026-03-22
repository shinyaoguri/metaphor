import MetaphorCore
import MetaphorNetwork

// MARK: - ネットワークブリッジ

extension Sketch {
    /// OSC（Open Sound Control）レシーバーを作成します。
    ///
    /// - Parameter port: リスニングする UDP ポート。
    /// - Returns: 新しい ``MetaphorNetwork/OSCReceiver`` インスタンス。
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        OSCReceiver(port: port)
    }

    /// 入出力用の MIDI マネージャーを作成します。
    ///
    /// - Returns: 新しい ``MetaphorNetwork/MIDIManager`` インスタンス。
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }
}
