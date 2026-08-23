import MetaphorCore
import MetaphorNetwork

// MARK: - ネットワークブリッジ

extension Sketch {
    /// Creates an OSC (Open Sound Control) receiver.
    ///
    /// - Parameter port: The UDP port to listen on.
    /// - Returns: A new ``MetaphorNetwork/OSCReceiver`` instance.
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        OSCReceiver(port: port)
    }

    /// Creates a sender for outgoing OSC messages.
    ///
    /// Use it to send to TouchDesigner, Max or a VJ tool; to receive, use
    /// ``createOSCReceiver(port:)``. Creation that fails — port 0, for instance —
    /// logs a warning and returns `nil`.
    ///
    /// - Parameters:
    ///   - host: The destination host, for example `"127.0.0.1"`.
    ///   - port: The destination UDP port.
    /// - Returns: A new ``MetaphorNetwork/OSCSender``, or `nil` on failure.
    public func createOSCSender(host: String, port: UInt16) -> OSCSender? {
        do {
            return try OSCSender(host: host, port: port)
        } catch {
            metaphorWarning("createOSCSender: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates a MIDI manager for input and output.
    ///
    /// - Returns: A new ``MetaphorNetwork/MIDIManager`` instance.
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }
}
