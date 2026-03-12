# ``MetaphorML``

Texture conversion utilities for integrating Core ML models with Metal rendering.

## Overview

MetaphorML provides ``MLTextureConverter``, a bridge between Metal textures
and the data formats used by Core ML. Convert freely between `MTLTexture`,
`CVPixelBuffer`, `CGImage`, and `MLMultiArray` to feed GPU-rendered frames
into ML models or visualize model outputs as textures.

This module has no dependency on MetaphorCore and can be used standalone.
When using the umbrella module (`import metaphor`), ML features are
accessible through convenience methods like `createMLConverter()`.

### Quick Start

```swift
let converter = MLTextureConverter(device: device, commandQueue: queue)

// Feed a rendered frame into a Core ML model
let pixelBuffer = converter.pixelBuffer(from: renderTexture)

// Visualize model output as a texture
let outputTexture = converter.texture(from: modelOutput)
```

## Topics

### Texture Conversion

- ``MLTextureConverter``
