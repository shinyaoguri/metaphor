# Topics/Shaders — one real shader, and 15 CPU approximations

[`CustomShader2D`](CustomShader2D) is the shader example: `loadShader()` compiles
a Metal fragment function, `shader()` makes `rect()` / `circle()` render through
it, and `resetShader()` goes back to the built-in shader. Built-in uniforms
(resolution, mouse, time, frame count) arrive in `buffer(3)`, your own struct in
`buffer(4)` via `setParameters()`, and the `.metal` file is watched — saving it
recompiles the shader without rebuilding the sketch. Start there.

**The other 15 sketches run no shader at all.** They are ports of Processing's
`Topics/Shaders` samples, whose originals load a GLSL program and apply it with
`loadShader()` / `shader()` / `filter(shader)`. They were written before metaphor
had a 2D custom draw shader
([Epic #291](https://github.com/shinyaoguri/metaphor/issues/291)), so 14 of them
recreate the same visual result on the CPU: per-pixel loops over an `MImage`,
drawn with `image()` (the odd one out, `DomeProjection`, is a placeholder marked
`obsolete` — cubemap rendering is a non-goal). The `NOTE:` at the top of every
`App.swift` names the shader the original used, and
[`docs/ai/examples-index.md`](../../../docs/ai/examples-index.md) tags them
`cpu-approximation`.

So: read those for the *effect* — an edge-detection kernel, a separable blur,
Game of Life rules — never as a reference for how metaphor does GPU work.

The rest of the GPU surface:

- Post-process passes over the finished frame: `addPostEffect()` /
  `setPostEffects()` with the built-in effects, or your own Metal Shading
  Language fragment function via
  `createPostEffect(name:source:fragmentFunction:)`.
- Per-pass effects inside a render graph: `createEffectPass(_:effects:)` —
  see [`Samples/RenderGraphCompose`](../../Samples/RenderGraphCompose), the one
  example in this repository that runs GPU effect passes inside a graph.
- Custom 3D surface shaders: `createMaterial(source:fragmentFunction:)` +
  `material()`.

## Why the unused `.glsl` files are still here

Every ported sketch keeps its original sample's `data/*.glsl` (22 files under this
directory) even though nothing reads them at runtime. They are the reference
material for porting those sketches back to real shaders now that the 2D shader
API has landed: the GLSL sources are what the Metal ports will be translated
from — exactly like the `.pde` originals kept beside them. They are deliberate
dead weight, not leftovers; please do not "clean them up".
