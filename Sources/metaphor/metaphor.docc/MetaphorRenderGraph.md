# ``MetaphorRenderGraph``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

A composable render pass graph for multi-pass rendering pipelines.

## Overview

MetaphorRenderGraph provides a directed acyclic graph (DAG) for building complex
multi-pass rendering pipelines.
Create source passes that render into offscreen textures,
chain post-processing effects, and merge multiple passes with blend operations.

Use ``MetaphorRenderGraph/SourcePass`` to create an offscreen render target with a draw callback,
``MetaphorRenderGraph/EffectPass`` to apply a post-processing chain, and ``MetaphorRenderGraph/MergePass`` to
blend the output of two passes. Connect them into a ``MetaphorRenderGraph/RenderGraph`` to run automatically.

This module depends on MetaphorCore.
Import `MetaphorRenderGraph` directly, or use the umbrella module (`import metaphor`).

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
