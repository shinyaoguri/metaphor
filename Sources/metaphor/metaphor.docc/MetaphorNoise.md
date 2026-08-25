# ``MetaphorNoise``

@Metadata {
    @PageColor(blue)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Procedural noise generation built on GameplayKit.

## Overview

MetaphorNoise wraps GameplayKit's noise system for creative coding.
Generate Perlin, Voronoi, billow, ridged, and other noise as float values, 2D grids,
or Metal textures. Fractal settings,
noise composition (addition and multiplication), and transforms (turbulence, clamp, power) are supported.

This module depends on MetaphorCore for `MImage` and Metal texture handling.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createNoise(type:config:)`.

### Quick Start

```swift
let noise = GKNoiseWrapper(
    type: .perlin,
    config: NoiseConfig(frequency: 4.0, octaves: 6),
    device: device
)

// Sample an individual point
let value = noise.sample(x: 0.5, y: 0.3)

// Generate a texture for rendering
let texture = noise.texture(width: 512, height: 512)
```

### Sampling by Point or by Grid (the Coordinate Spaces Differ)

There are two ways into the field, and **each one reads a different coordinate space**.

| Entry point | `origin` / `sampleScale` |
|---|---|
| `sample(x:y:)` | **No effect** (reads noise space directly) |
| `sampleGrid` / `texture` / `image` / `colorMappedTexture` | Applied (delegates to `GKNoiseMap` starting from `origin`) |

The two agree only on the first point of the grid (`sample(x: origin.x, y: origin.y)`).
Past that they diverge, and chasing the difference with `origin + index × sampleScale` will not
line them up either — the spacing GameplayKit uses to step through a `GKNoiseMap` is not
determined by `sampleScale` alone, but also by the grid's `width` and `height`.

**Stick to one entry point within a single sketch.** Mixing them shows up as a mismatch between
what you see and what you measure.
