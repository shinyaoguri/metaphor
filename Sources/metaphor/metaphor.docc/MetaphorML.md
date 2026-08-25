# ``MetaphorML``

@Metadata {
    @PageColor(blue)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Texture conversion utilities for combining Core ML models with Metal rendering.

## Overview

MetaphorML provides ``MetaphorML/MLTextureConverter``, a bridge between Metal textures and the
data formats Core ML works with. Convert freely between `MTLTexture`, `CVPixelBuffer`, `CGImage`,
and `MLMultiArray` to feed GPU-rendered frames into an ML model, or to draw a model's output
back out as a texture.

This module does not depend on MetaphorCore and can be used on its own.
Import `MetaphorML` directly, or use the umbrella module (`import metaphor`).

### Quick Start

```swift
let converter = MLTextureConverter(device: device, commandQueue: queue)

// Feed a rendered frame into a Core ML model
let pixelBuffer = converter.pixelBuffer(from: renderTexture)

// Draw the model output as a texture
let outputTexture = converter.texture(from: modelOutput)
```
