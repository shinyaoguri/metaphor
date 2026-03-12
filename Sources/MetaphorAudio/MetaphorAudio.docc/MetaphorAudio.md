# ``MetaphorAudio``

Audio input analysis and sound file playback for creative coding.

## Overview

MetaphorAudio provides real-time FFT spectrum analysis from microphone input
and audio file playback with integrated analysis. Use ``AudioAnalyzer`` to
capture live audio and extract volume, spectrum, and beat data. Use
``SoundFile`` to play MP3, WAV, or AAC files with optional spectrum analysis.

This module has no dependency on MetaphorCore and can be used standalone.
When using the umbrella module (`import metaphor`), audio features are
accessible through convenience methods like `createAudioInput()`.

### Quick Start

```swift
// Live microphone analysis
let audio = AudioAnalyzer(fftSize: 1024)
try audio.start()

// In your draw loop:
audio.update()
let bass = audio.band(0)      // Bass energy
let mid = audio.band(1)       // Mid energy
let treble = audio.band(2)    // Treble energy
```

## Topics

### Audio Analysis

- ``AudioAnalyzer``

### Sound File Playback

- ``SoundFile``

### Errors

- ``SoundFileError``
