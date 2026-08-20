# Topics/Shaders — two real shaders, and 14 CPU approximations

[`CustomShader2D`](CustomShader2D) is the 2D shader example: `loadShader()`
compiles a Metal fragment function, `shader()` makes `rect()` / `circle()` render
through it, and `resetShader()` goes back to the built-in shader. Built-in
uniforms (resolution, mouse, time, frame count) arrive in `buffer(3)`, your own
struct in `buffer(4)` via `setParameters()`, and the `.metal` file is watched —
saving it recompiles the shader without rebuilding the sketch. Start there.

[`ToonShading`](ToonShading) is the 3D one: `createMaterialFromFile()` compiles a
fragment function, `material()` applies it to the 3D draws that follow, and
`noMaterial()` goes back to the built-in shading. The vertex stage stays built-in
— `Canvas3DVertexOut` already carries the normal and world position — so the
sketch only replaces how the surface is coloured. Uniforms (`buffer(1)`) and the
light array (`buffer(2)`) are the same ones the built-in shader reads, which is
why `directionalLight()` still steers the toon bands.

**The other 14 sketches run no shader at all.** They are ports of Processing's
`Topics/Shaders` samples, whose originals load a GLSL program and apply it with
`loadShader()` / `shader()` / `filter(shader)`. They were written before metaphor
had a 2D custom draw shader
([Epic #291](https://github.com/shinyaoguri/metaphor/issues/291)), so 13 of them
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
- Custom 3D surface shaders: `createMaterial(source:fragmentFunction:)` /
  `createMaterialFromFile(path:fragmentFunction:)` + `material()` — see
  [`ToonShading`](ToonShading).

## Why the unused `.glsl` files are still here

Every ported sketch keeps its original sample's `data/*.glsl` (22 files under this
directory) even though nothing reads them at runtime. They are the reference
material for porting those sketches back to real shaders now that the 2D shader
API has landed: the GLSL sources are what the Metal ports will be translated
from — exactly like the `.pde` originals kept beside them. They are deliberate
dead weight, not leftovers; please do not "clean them up".

`ToonShading` is the first one that went through that translation: its
`ToonShading/Resources/Toon.metal` is a line-by-line port of `data/ToonFrag.glsl`,
with the same four thresholds and the same four colours, and `data/ToonVert.glsl`
turned out to be unnecessary because the built-in vertex stage already supplies
what it computed. The GLSL stayed put as the record of where the Metal came from.
