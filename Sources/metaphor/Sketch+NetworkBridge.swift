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

    /// OSC メッセージ送信用のセンダーを作成します。
    ///
    /// TouchDesigner / Max / VJ ツールへの送信に使います（受信は
    /// ``createOSCReceiver(port:)``）。生成に失敗した場合は警告を出力して
    /// `nil` を返します（ポート 0 など）。
    ///
    /// - Parameters:
    ///   - host: 送信先ホスト（例: `"127.0.0.1"`）。
    ///   - port: 送信先の UDP ポート番号。
    /// - Returns: 新しい ``MetaphorNetwork/OSCSender``。失敗時は `nil`。
    public func createOSCSender(host: String, port: UInt16) -> OSCSender? {
        do {
            return try OSCSender(host: host, port: port)
        } catch {
            metaphorWarning("createOSCSender: \(error.localizedDescription)")
            return nil
        }
    }

    /// 入出力用の MIDI マネージャーを作成します。
    ///
    /// - Returns: 新しい ``MetaphorNetwork/MIDIManager`` インスタンス。
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }
}
