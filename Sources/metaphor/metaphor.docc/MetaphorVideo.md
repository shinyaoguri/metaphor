# ``MetaphorVideo``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Video file playback for creative coding.

## Overview

MetaphorVideo provides video file playback and per-frame texture access.
Use ``MetaphorVideo/VideoPlayer`` to play MP4, MOV, and M4V files and to obtain frames as
zero-copy Metal textures backed by CVMetalTextureCache.

This module does not depend on MetaphorCore and can be used on its own.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `loadVideo()` and `image(video, x, y)`.

### Quick Start

```swift
let video = try loadVideo("/path/to/video.mp4")
video.loop()

// Inside the draw loop:
video.update()
image(video, 0, 0, width, height)
```
