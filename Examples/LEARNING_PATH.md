# Learning Path

[Examples/](.) is a large collection of self-contained sketches: great for
"show me one that does X", useless for "what do I run first?" This page is a
curated route through a representative handful, grouped by what you're
learning next. It reuses the difficulty tags (`[Beginner]` /
`[Intermediate]` / `[Advanced]`) already present in
[`docs/ai/examples-index.md`](../docs/ai/examples-index.md) — that file
remains the full, searchable index; this page is a suggested order through it.

**New to metaphor?** Start with the tutorial
([`docs/tutorial/`](../docs/tutorial/) — Japanese, all ten parts published under
[Epic #483](https://github.com/shinyaoguri/metaphor/issues/483)). It teaches
the library in order with its own sketches. This page is the map for digging
through the examples themselves once you want more than the tutorial covers.

Each stop links straight to an example directory. Run any of them the same
way:

```bash
cd Examples/<path-from-the-link>
swift run
```

## 1. First shapes

Get a window open and draw something. All beginner-level, no dependencies
beyond the library.

- [Basics/Structure/SetupDraw](Basics/Structure/SetupDraw) — the `setup()` / `draw()` split itself.
- [Basics/Form/ShapePrimitives](Basics/Form/ShapePrimitives) — `rect()`, `ellipse()`, `triangle()`, `arc()` — the basic vocabulary.
- [Basics/Structure/Coordinates](Basics/Structure/Coordinates) — the coordinate system (origin at top-left).
- [Basics/Structure/NoLoop](Basics/Structure/NoLoop) — `noLoop()` for a single still frame instead of a continuous `draw()`.

## 2. Color and interaction

Respond to the mouse and keyboard, and move past grayscale.

- [Basics/Color/Hue](Basics/Color/Hue) — `colorMode`, moving the cursor to change hue.
- [Basics/Input/Mouse2D](Basics/Input/Mouse2D) — `mouseX` / `mouseY` driving position and size.
- [Basics/Input/Keyboard](Basics/Input/Keyboard) — `keyPressed()`, reading which key was hit.

## 3. Transforms and math

`push()` / `pop()`, moving and rotating shapes, and the noise/random functions
that show up in almost every generative sketch from here on.

- [Basics/Transform/Translate](Basics/Transform/Translate) — moving the origin.
- [Basics/Transform/Rotate](Basics/Transform/Rotate) — rotating around it.
- [Basics/Math/Map](Basics/Math/Map) — `map()`, rescaling one range of numbers into another.
- [Basics/Math/Noise1D](Basics/Math/Noise1D) — Perlin noise driving motion instead of pure randomness.

## 4. Going 3D

Same `Sketch` vocabulary, now with a camera and lights.

- [Basics/Form/Primitives3D](Basics/Form/Primitives3D) — `box()` / `sphere()` in synthetic 3D space.
- [Basics/Lights/OnOff](Basics/Lights/OnOff) — the default `lights()` call.
- [Basics/Lights/Mixture](Basics/Lights/Mixture) — directional / point / spot lights together (Blinn-Phong).
- [Basics/Control/Camera/Perspective](Basics/Control/Camera/Perspective) — `perspective()` and field of view.

## 5. Simulation and particles

Where sketches start accumulating state across frames — motion, collisions,
and particle systems.

- [Topics/Motion/Bounce](Topics/Motion/Bounce) — the reverse-direction-at-the-edge pattern used everywhere in Motion/.
- [Topics/Simulate/SimpleParticleSystem](Topics/Simulate/SimpleParticleSystem) — a `ParticleSystem` managing a growing/shrinking list of particles.
- [Topics/Simulate/Flocking](Topics/Simulate/Flocking) — Craig Reynolds' boids: avoidance, alignment, cohesion.

For particle counts in the tens of thousands and up, see
[Demos/Performance/MassiveCircles](Demos/Performance/MassiveCircles) (explicit
batched drawing) once you've outgrown per-particle `circle()` calls.

## 6. GPU effects: custom shaders and post-processing

metaphor draws through Metal, and you can drive that GPU work yourself in three
places: *while* shapes are drawn (a custom 2D fragment shader), *after* `draw()`
(a post-process pass over the finished frame), and on 3D geometry (a custom
material).

- [Topics/Shaders/CustomShader2D](Topics/Shaders/CustomShader2D) — `loadShader()`
  reads a Metal fragment function, `shader()` makes `rect()` / `circle()` render
  through it, `resetShader()` goes back. Built-in uniforms (resolution, mouse,
  time, frame count) arrive in `buffer(3)`; your own struct goes to `buffer(4)`
  via `setParameters()`. The `.metal` file is watched, so saving it recompiles
  the shader without rebuilding the sketch.

- [Samples/RenderGraphCompose](Samples/RenderGraphCompose) — the one example in
  this repository that actually runs GPU effect passes:
  `createEffectPass(_:effects:)` applies `ChromaticAberrationEffect` /
  `VignetteEffect` to individual passes of a render graph. Advanced; comes back
  in section 7.

The rest of the surface has no example yet, so read it in `llms.txt`:
`addPostEffect()` / `setPostEffects()` chain the same built-in effects over the
whole frame, `createPostEffect(name:source:fragmentFunction:)` compiles your own
Metal Shading Language fragment function into that chain, and
`createMaterial(source:fragmentFunction:)` + `material()` give 3D geometry a
custom surface shader.

**The other 15 sketches in `Topics/Shaders/` are not where you learn any of
that.** They port Processing samples whose originals were GLSL, but they recreate
the effect with CPU pixel loops instead, which is why
[`docs/ai/examples-index.md`](../docs/ai/examples-index.md) tags them
`cpu-approximation`. They are still worth reading for the effect itself (an
edge-detection kernel, a separable blur, Game of Life rules) — just not as
shader code. See
[Topics/Shaders/README.md](Topics/Shaders/README.md), which also explains why the
unused `.glsl` files are kept.

## 7. metaphor-specific features

Beyond the Processing-parity surface: the things that only exist in metaphor.

- [Samples/ProbeSnapshot](Samples/ProbeSnapshot) — the Probe plugin AI agents use to observe a running sketch (`probe()`, `.metaphor/probe/`).
- [Samples/RenderGraphCompose](Samples/RenderGraphCompose) — composing render passes with `RenderGraph`.
- [Samples/SceneGraphBasics](Samples/SceneGraphBasics) — retained-mode `SceneGraph` nodes instead of immediate-mode `draw()` calls.
- [Samples/RayTracing](Samples/RayTracing) — MPS/Metal ray tracing.

Part 10 of the tutorial turns the Probe into a workflow — `Examples/Tutorial/10-AI/01-ObservationLoop`
(why a frame that compiles can still be empty), `02-ProbeState` (`probe()` and what
lands in `frame.json`) and `03-AgentTools` (`probe()` plus `@Param`, the surface an
agent drives over MCP).

## 8. Camera, ML, and audio — permission-gated

These sketches ask macOS for microphone/camera access the first time they run.
**Read [docs/permissions.md](../docs/permissions.md) first** if you haven't
granted a terminal app camera/microphone access before — it explains why the
system dialog names your terminal instead of the sketch, and how to recover if
you clicked Deny.

- [Basics/Video/CameraSwitching](Basics/Video/CameraSwitching) — enumerating and switching between connected cameras (`listCaptureDevices()` / `createCapture(device:)`).
- [ML/FaceDetection](ML/FaceDetection) — `CaptureDevice` → `MLTextureConverter` → Vision's `VNDetectFaceRectanglesRequest`.
- [ML/PersonSegmentation](ML/PersonSegmentation) — the same pipeline feeding `VNGeneratePersonSegmentationRequest`.

For the microphone (`AudioAnalyzer` / `createAudioInput()`), the tutorial's
part 7 has two sketches — `Examples/Tutorial/07-Media/01-AudioInput` (volume)
and `02-Spectrum` (FFT and beat detection). To start a new sketch from a
template instead, [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli)'s
`audio-reactive` project template (`metaphor new MySketch --template
audio-reactive`) wires the same API up for you; the permission mechanics above
apply to it the same way.

## 9. Live performance: OSC, MIDI, Syphon

Sending/receiving external control signals and outputting to other apps.

- [Samples/OSCLoopback](Samples/OSCLoopback) — `OSCSender` / `OSCReceiver` round-tripping the mouse position.
- [Samples/Syphon/SyphonOutput](Samples/Syphon/SyphonOutput) — publishing frames to other Syphon-compatible apps (VJ software, TouchDesigner, etc.).
- [Samples/ParameterPanel](Samples/ParameterPanel) — `@Param` declarations driving both a live GUI panel and the `.metaphor/params/` file contract.

MIDI has no sample outside the tutorial. Part 8 of the tutorial covers all four
topics with a sketch each — `Examples/Tutorial/08-Connect/01-OSC` (loopback),
`02-MIDI` (knobs and pads), `03-Syphon` (fixed-resolution output) and
`04-Parameters` (`@Param` plus `gui.params()`).

## 10. Exporting your work

Getting the picture out of the window: stills, video, vector, and the settings
that make a render reproducible.

- [Samples/SVGExport](Samples/SVGExport) — `beginSVGRecord()` / `endSVGRecord()` writing plotter-ready line art from the same draw calls the screen gets.
- [Samples/StatePreservation](Samples/StatePreservation) — `saveState()` / `restoreState(_:)` and `preserveClock` keeping a simulation alive across a live-reload.

Part 9 of the tutorial covers the whole surface with a sketch each —
`Examples/Tutorial/09-Artwork/01-SaveImage` (`save()` and PNG sequences),
`02-RecordMotion` (video and GIF), `03-VectorExport` (SVG), `04-DeterministicRender`
(`beginOfflineRender()` plus fixed seeds, byte-identical across runs) and
`05-LongRun` (state preservation and the performance HUD).

## Where to go next

- **Learn the library in order**: [`docs/tutorial/`](../docs/tutorial/) — the systematic tutorial (Japanese), with its own sketches and rendered output per section.
- **Full, searchable index**: [`docs/ai/examples-index.md`](../docs/ai/examples-index.md) — every example, with tags, difficulty, and status (`supported` / `partial` / `stub` / `obsolete`).
- **Processing sample by name**: `Basics/` and `Topics/` mirror the official Processing example structure closely — most examples ship the original `.pde` alongside the Swift port.
- **Writing your own sketch with AI**: [`docs/ai/for-sketch-authors.md`](../docs/ai/for-sketch-authors.md).
- **All public API**: [`llms.txt`](../llms.txt) at the repository root, or the [DocC reference](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/) if you'd rather browse in a browser.
