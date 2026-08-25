# ``MetaphorMPS``

@Metadata {
    @PageColor(red)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Hardware-accelerated image processing and ray tracing through Metal Performance Shaders.

## Overview

MetaphorMPS exposes GPU-optimized image filters and ray tracing through Apple's
Metal Performance Shaders framework.
``MetaphorMPS/MPSImageFilterWrapper`` covers Gaussian blur, Sobel edge detection,
and morphological operations, while ``MetaphorMPS/MPSRayTracer`` performs mesh-based ray tracing
with ambient occlusion, soft shadow, and diffuse shading modes.

It also ships ``MetaphorCore/PostEffect`` implementations (``MetaphorMPS/MPSBlurEffect``,
``MetaphorMPS/MPSSobelEffect``, and others) that drop straight into the post-processing pipeline.

This module depends on MetaphorCore.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createMPSFilter()`.

### Quick Start

```swift
let filter = MPSImageFilterWrapper(device: device, commandQueue: queue)

// Apply a Gaussian blur to an image
filter.gaussianBlur(image, sigma: 5.0)

// Use it as a post-processing effect
let blur = MPSBlurEffect(sigma: 3.0)
postProcess(blur)
```
