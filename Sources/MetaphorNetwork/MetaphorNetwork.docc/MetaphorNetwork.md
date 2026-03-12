# ``MetaphorNetwork``

OSC and MIDI communication for interactive and live performance applications.

## Overview

MetaphorNetwork provides real-time communication protocols commonly used in
creative coding and live performance. ``OSCReceiver`` listens for UDP-based
Open Sound Control messages, while ``MIDIManager`` handles CoreMIDI input
and output for controllers, synthesizers, and other MIDI devices.

This module has no dependency on MetaphorCore and can be used standalone.
When using the umbrella module (`import metaphor`), network features are
accessible through convenience methods like `createOSCReceiver(port:)` and
`createMIDI()`.

### Quick Start

```swift
// Receive OSC messages
let osc = OSCReceiver(port: 9000)
osc.on("/sensor/value") { args in
    if case .float(let value) = args.first {
        print(value)
    }
}
try osc.start()

// MIDI controller input
let midi = MIDIManager()
midi.start()
let messages = midi.poll()
let knobValue = midi.controllerValue(1)  // CC#1 normalized to 0.0-1.0
```

## Topics

### OSC

- ``OSCReceiver``
- ``OSCValue``
- ``OSCReceiverError``

### MIDI

- ``MIDIManager``
- ``MIDIMessage``
- ``MIDIMessageType``
