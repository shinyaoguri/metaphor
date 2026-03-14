# ``MetaphorCoreImage``

Core Image filter integration for Metal-based creative coding.

## Overview

MetaphorCoreImage bridges Apple's Core Image framework with Metal textures.
Apply a curated set of filter presets — distortion, stylize, blur, color
effects, generators, and more — through ``CIFilterPreset``, or use any
Core Image filter by name with ``CIFilterWrapper``.

The module also provides ``PostEffect`` implementations (``CIFilterEffect``,
``CIFilterRawEffect``) for direct use in a post-processing pipeline.

This module depends on MetaphorCore.
Import `MetaphorCoreImage` directly or use the umbrella module (`import metaphor`).

### Quick Start

```swift
let ci = CIFilterWrapper(device: device, commandQueue: queue)

// Apply a preset filter to an image
ci.apply(filterName: CIFilterPreset.twirl.filterName,
         parameters: CIFilterPreset.twirl.parameters(textureSize: size),
         to: image)

// Use as a post-processing effect
let effect = CIFilterEffect(.kaleidoscope)
postProcess(effect)
```

## Topics

### Filter Presets

- ``CIFilterPreset``

### Filter Wrapper

- ``CIFilterWrapper``
- ``CIFilterValue``

### Post-Processing Effects

- ``CIFilterEffect``
- ``CIFilterRawEffect``
