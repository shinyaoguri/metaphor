import MetaphorCore
import MetaphorNetwork

// MARK: - Network Bridge

extension Sketch {
    /// Create an OSC (Open Sound Control) receiver.
    ///
    /// - Parameter port: The UDP port to listen on.
    /// - Returns: A new ``OSCReceiver`` instance.
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        OSCReceiver(port: port)
    }

    /// Create a MIDI manager for input and output.
    ///
    /// - Returns: A new ``MIDIManager`` instance.
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }
}
