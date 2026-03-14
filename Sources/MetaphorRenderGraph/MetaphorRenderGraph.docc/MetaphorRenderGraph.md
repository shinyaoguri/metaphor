# ``MetaphorRenderGraph``

Composable render pass graph for multi-pass rendering pipelines.

## Overview

MetaphorRenderGraph provides a directed acyclic graph (DAG) of render passes
for building complex multi-pass rendering pipelines. Create source passes
that render to offscreen textures, chain post-processing effects, and merge
multiple passes with blend operations.

Use ``SourcePass`` to create offscreen render targets with draw callbacks,
``EffectPass`` to apply post-processing chains, and ``MergePass`` to blend
two pass outputs together. Connect them into a ``RenderGraph`` for automatic
execution.

This module depends on MetaphorCore.
Import `MetaphorRenderGraph` directly or use the umbrella module (`import metaphor`).

### Quick Start

```swift
let passA = try SourcePass(label: "scene", device: device, width: 1280, height: 720)
passA.onDraw = { encoder, time in
    // Draw scene A
}

let passB = try SourcePass(label: "overlay", device: device, width: 1280, height: 720)
passB.onDraw = { encoder, time in
    // Draw scene B
}

let merged = try MergePass(passA, passB, blend: .add, device: device, shaderLibrary: shaders)
let graph = RenderGraph(root: merged)
```

## Topics

### Graph

- ``RenderGraph``

### Pass Nodes

- ``RenderPassNode``
- ``SourcePass``
- ``EffectPass``
- ``MergePass``
