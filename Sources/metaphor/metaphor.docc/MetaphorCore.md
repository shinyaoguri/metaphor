# ``MetaphorCore``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

The rendering engine, drawing system, and Sketch protocol at the heart of metaphor.

## Overview

MetaphorCore provides the Metal rendering pipeline, the 2D and 3D drawing backends,
compute shader support, and the ``MetaphorCore/Sketch`` protocol that ties them together.

You normally do not import MetaphorCore directly — use `import metaphor` (the umbrella module),
which covers every module including audio, physics, and machine learning.
[See the full API reference](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor).
