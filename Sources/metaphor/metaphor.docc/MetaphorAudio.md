# ``MetaphorAudio``

@Metadata {
    @PageColor(yellow)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Audio input analysis and sound file playback for creative coding.

## Overview

MetaphorAudio provides real-time FFT spectrum analysis of microphone input,
plus audio file playback with the same analysis built in.
Use ``MetaphorAudio/AudioAnalyzer`` to capture live audio and read volume, spectrum, and beat information.
Use ``MetaphorAudio/SoundFile`` to play MP3, WAV, and AAC files, optionally with spectrum analysis.

This module does not depend on MetaphorCore and can be used on its own.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createAudioInput()`.

### Quick Start

```swift
// Live microphone analysis
let audio = AudioAnalyzer(fftSize: 1024)
try audio.start()

// Inside the draw loop:
audio.update()
let bass = audio.band(0)      // Low-frequency energy
let mid = audio.band(1)       // Mid-frequency energy
let treble = audio.band(2)    // High-frequency energy
```
