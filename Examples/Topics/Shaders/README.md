# Topics/Shaders — CPU approximations, not shaders

These 15 sketches are ports of Processing's `Topics/Shaders` samples. **None of
them runs a shader.**

Processing's originals load a GLSL program and apply it with `loadShader()` /
`shader()` / `filter(shader)`. metaphor has no equivalent for 2D custom draw
shaders yet — it is planned in
[Epic #291](https://github.com/shinyaoguri/metaphor/issues/291). Until that
lands, 14 of the 15 recreate the same visual result on the CPU: per-pixel loops
over an `MImage`, drawn with `image()` (the odd one out, `DomeProjection`, is a
placeholder marked `obsolete` — cubemap rendering is a non-goal). The `NOTE:` at
the top of every `App.swift` names the shader the original used, and
[`docs/ai/examples-index.md`](../../../docs/ai/examples-index.md) tags them
`cpu-approximation`.

So: read them for the *effect* — an edge-detection kernel, a separable blur,
Game of Life rules — never as a reference for how metaphor does GPU work.

What metaphor does have today, if that is what you came for:

- Post-process passes over the finished frame: `addPostEffect()` /
  `setPostEffects()` with the built-in effects, or your own Metal Shading
  Language fragment function via
  `createPostEffect(name:source:fragmentFunction:)`.
- Per-pass effects inside a render graph: `createEffectPass(_:effects:)` —
  see [`Samples/RenderGraphCompose`](../../Samples/RenderGraphCompose), the one
  example in this repository that actually runs GPU effect passes.
- Custom 3D surface shaders: `createMaterial(source:fragmentFunction:)` +
  `material()`.

## Why the unused `.glsl` files are still here

Every sketch keeps its original sample's `data/*.glsl` (22 files under this
directory) even though nothing reads them at runtime. They are the reference
material for #291: when the 2D shader API lands, these sketches get ported back
to real shaders, and the GLSL sources are what the Metal ports will be
translated from — exactly like the `.pde` originals kept beside them. They are
deliberate dead weight, not leftovers; please do not "clean them up".
