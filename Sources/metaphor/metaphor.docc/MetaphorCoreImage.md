# ``MetaphorCoreImage``

@Metadata {
    @PageColor(red)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Core Image filter integration for Metal-based creative coding.

## Overview

MetaphorCoreImage bridges Apple's Core Image framework and Metal textures.
Apply a curated set of filter presets — distortion, stylize, blur, color effects, generators
and more — with ``MetaphorCoreImage/CIFilterPreset``, or reach any Core Image filter by name
with ``MetaphorCoreImage/CIFilterWrapper``.

It also ships ``MetaphorCore/PostEffect`` implementations (``MetaphorCoreImage/CIFilterEffect``,
``MetaphorCoreImage/CIFilterRawEffect``) that drop straight into the post-processing pipeline.

This module depends on MetaphorCore.
Import `MetaphorCoreImage` directly, or use the umbrella module (`import metaphor`).

### Quick Start

```swift
let ci = CIFilterWrapper(device: device, commandQueue: queue)

// Apply a preset filter to an image
ci.apply(filterName: CIFilterPreset.twirl.filterName,
         parameters: CIFilterPreset.twirl.parameters(textureSize: size),
         to: image)

// Use it as a post-processing effect
let effect = CIFilterEffect(.kaleidoscope)
postProcess(effect)
```
