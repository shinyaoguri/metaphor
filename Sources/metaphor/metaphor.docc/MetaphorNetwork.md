# ``MetaphorNetwork``

@Metadata {
    @PageColor(green)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

OSC and MIDI communication for interactive work and live performance.

## Overview

MetaphorNetwork provides the real-time communication protocols that creative coding and
live performance rely on. ``MetaphorNetwork/OSCReceiver`` receives UDP-based
Open Sound Control messages, and ``MetaphorNetwork/MIDIManager`` handles CoreMIDI input and
output with controllers, synthesizers, and other MIDI devices.

This module does not depend on MetaphorCore and can be used on its own.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createOSCReceiver(port:)` and `createMIDI()`.

### Quick Start

```swift
// Receiving OSC messages
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
