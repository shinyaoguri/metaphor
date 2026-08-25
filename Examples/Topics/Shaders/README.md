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

## Where the original `.glsl` went

Every ported sketch used to keep its original sample's `data/*.glsl` beside the
Swift port, as the reference material a future Metal translation would be made
from. Those 28 files were removed in
[#1190](https://github.com/shinyaoguri/metaphor/issues/1190): seven of them
declared GPLv2, LGPL-2.1 or CC BY-NC-SA in their own headers, which this
repository's MIT license cannot absorb, and the remaining 21 shared their
provenance without saying anything about their license. Nothing read any of them
at runtime — metaphor is Metal, and the only example here that calls
`loadShader()` reads a `.metal` file written for this repository. The details are
in [THIRD_PARTY_LICENSES.md](../../../THIRD_PARTY_LICENSES.md).

To translate one of these sketches into a real Metal shader, fetch the GLSL from
upstream — [processing/processing-examples](https://github.com/processing/processing-examples)
mirrors Processing's own tree, so the sketch sits at the matching path there and
its `.pde` names what it loaded. Read it upstream rather than here: `Deform` no
longer bundles its original either, because that one carries a credit line and
was never licensed ([#1191](https://github.com/shinyaoguri/metaphor/issues/1191)).

`ToonShading` is the one that already went through that translation, and its
lineage is worth recording here since the source it came from is no longer in the
tree: `ToonShading/Resources/Toon.metal` is a line-by-line port of the sample's
`data/ToonFrag.glsl`, with the same four thresholds and the same four colours.
The companion `data/ToonVert.glsl` turned out to be unnecessary, because the
built-in vertex stage already supplies what it computed.
