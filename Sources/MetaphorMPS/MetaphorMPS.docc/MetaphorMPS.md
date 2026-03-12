# ``MetaphorMPS``

Hardware-accelerated image processing and ray tracing using Metal Performance Shaders.

## Overview

MetaphorMPS provides GPU-optimized image filters and ray tracing through
Apple's Metal Performance Shaders framework. ``MPSImageFilterWrapper`` offers
Gaussian blur, Sobel edge detection, morphological operations, and more.
``MPSRayTracer`` provides mesh-based ray tracing with ambient occlusion,
soft shadows, and diffuse shading modes.

The module also includes ``PostEffect`` implementations (``MPSBlurEffect``,
``MPSSobelEffect``, etc.) that can be used directly in a post-processing
pipeline.

This module depends on MetaphorCore.
When using the umbrella module (`import metaphor`), MPS features are
accessible through convenience methods like `createMPSFilter()`.

### Quick Start

```swift
let filter = MPSImageFilterWrapper(device: device, commandQueue: queue)

// Apply Gaussian blur to an image
filter.gaussianBlur(image, sigma: 5.0)

// Use as a post-processing effect
let blur = MPSBlurEffect(sigma: 3.0)
postProcess(blur)
```

## Topics

### Image Filters

- ``MPSImageFilterWrapper``

### Post-Processing Effects

- ``MPSBlurEffect``
- ``MPSSobelEffect``
- ``MPSErodeEffect``
- ``MPSDilateEffect``

### Ray Tracing

- ``MPSRayTracer``
- ``RayTraceMode``
