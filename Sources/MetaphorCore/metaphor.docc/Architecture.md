# Architecture

Understand how metaphor's rendering pipeline and API layers work together.

## Overview

metaphor is built around three core concepts: a two-pass rendering architecture,
a three-layer API design, and a GPU-first approach using Metal.

## Two-Pass Rendering

Every frame goes through two rendering passes:

### Offscreen Pass

Your drawing code renders to a fixed-resolution offscreen texture managed by ``TextureManager``.
This texture is independent of the window size, so you always work at a consistent resolution.

### Blit Pass

A built-in pipeline composites the offscreen texture to the screen (or MTKView) with
automatic aspect-ratio preservation. This pass also feeds into Syphon output if enabled.

This architecture enables:

- **Resolution independence** — Render at 1920x1080 regardless of window size.
- **Syphon output** — Send your rendered frame to VJ software at a fixed resolution.
- **Video export** — Capture frames at consistent quality.
- **Post-processing** — Apply GPU effects to the offscreen texture before display.

## Three-Layer API

### Sketch (Top Layer)

The ``Sketch`` protocol is the primary user-facing API. It provides convenience methods
through protocol extensions that delegate to the underlying layers:

```swift
// These are equivalent:
circle(400, 300, 100)           // Sketch extension (implicit context)
ctx.circle(400, 300, 100)       // SketchContext method
```

### SketchContext (Middle Layer)

``SketchContext`` manages drawing state, coordinate transforms, and the bridge between
2D and 3D rendering. It holds references to ``Canvas2D`` and ``Canvas3D`` instances
and routes drawing calls to the appropriate backend.

### Canvas2D / Canvas3D (Bottom Layer)

``Canvas2D`` and ``Canvas3D`` are the low-level drawing backends that directly issue
Metal render commands. They manage vertex buffers, pipeline states, and GPU resources.

## Frame Lifecycle

Each frame follows this sequence:

1. **Compute phase** — `onCompute(commandBuffer, time)` runs GPU compute dispatches.
2. **Draw phase** — `onDraw(renderEncoder, time)` runs your rendering code.
3. **Post-process phase** — ``PostProcessPipeline`` applies any configured effects.
4. **Blit phase** — The offscreen texture is composited to the screen.
5. **Syphon phase** — The frame is published to Syphon if enabled.

## Shader Compilation

metaphor embeds Metal Shading Language (MSL) source code as Swift strings. Shaders are
compiled at runtime via ``ShaderLibrary``, which caches compiled `MTLLibrary` and
`MTLFunction` instances. Custom shaders can be registered at runtime using
``ShaderLibrary/register(source:as:)``.

## GPU Instancing

For high-performance rendering, metaphor automatically batches consecutive draw calls
of the same shape and material into GPU-instanced draw calls. This is handled transparently
by the instancing layer in ``Canvas2D`` and ``Canvas3D``.
