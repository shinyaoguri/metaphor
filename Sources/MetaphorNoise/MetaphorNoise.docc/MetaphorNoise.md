# ``MetaphorNoise``

Procedural noise generation using GameplayKit.

## Overview

MetaphorNoise wraps GameplayKit's noise system for creative coding use.
Generate Perlin, Voronoi, billow, ridged, and other noise types as float
values, 2D grids, or Metal textures. Supports fractal configuration,
noise composition (add, multiply), and transformations (turbulence, clamp,
power).

This module depends on MetaphorCore for `MImage` and Metal texture handling.
When using the umbrella module (`import metaphor`), noise features are
accessible through convenience methods like `createNoise(type:config:)`.

### Quick Start

```swift
let noise = GKNoiseWrapper(
    type: .perlin,
    config: NoiseConfig(frequency: 4.0, octaves: 6),
    device: device
)

// Sample individual points
let value = noise.sample(x: 0.5, y: 0.3)

// Generate a texture for rendering
let texture = noise.texture(width: 512, height: 512)
```

## Topics

### Noise Types

- ``NoiseType``

### Configuration

- ``NoiseConfig``

### Generator

- ``GKNoiseWrapper``
