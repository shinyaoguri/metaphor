# Learning Path

[Examples/](.) has 278 self-contained sketches, which is great for search but
useless for "what do I run first?" This page is a curated route through a
representative handful, grouped by what you're learning next. It reuses the
difficulty tags (`[Beginner]` / `[Intermediate]` / `[Advanced]`) already
present in [`docs/ai/examples-index.md`](../docs/ai/examples-index.md) — that
file remains the full, searchable index; this page is a suggested order
through it.

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

## 6. GPU shaders and post-processing

Custom Metal Shading Language fragment shaders applied as a post-process pass.

- [Topics/Shaders/EdgeDetect](Topics/Shaders/EdgeDetect) — a minimal single-pass filter shader.
- [Topics/Shaders/BlurFilter](Topics/Shaders/BlurFilter) — a two-pass (horizontal/vertical) filter.
- [Topics/Shaders/ToonShading](Topics/Shaders/ToonShading) — a stylized shading pass.

## 7. metaphor-specific features

Beyond the Processing-parity surface: the things that only exist in metaphor.

- [Samples/ProbeSnapshot](Samples/ProbeSnapshot) — the Probe plugin AI agents use to observe a running sketch (`probe()`, `.metaphor/probe/`).
- [Samples/RenderGraphCompose](Samples/RenderGraphCompose) — composing render passes with `RenderGraph`.
- [Samples/SceneGraphBasics](Samples/SceneGraphBasics) — retained-mode `SceneGraph` nodes instead of immediate-mode `draw()` calls.
- [Samples/RayTracing](Samples/RayTracing) — MPS/Metal ray tracing.

## 8. Camera, ML, and audio — permission-gated

These sketches ask macOS for microphone/camera access the first time they run.
**Read [docs/permissions.md](../docs/permissions.md) first** if you haven't
granted a terminal app camera/microphone access before — it explains why the
system dialog names your terminal instead of the sketch, and how to recover if
you clicked Deny.

- [Basics/Video/CameraSwitching](Basics/Video/CameraSwitching) — enumerating and switching between connected cameras (`listCaptureDevices()` / `createCapture(device:)`).
- [ML/FaceDetection](ML/FaceDetection) — `CaptureDevice` → `MLTextureConverter` → Vision's `VNDetectFaceRectanglesRequest`.
- [ML/PersonSegmentation](ML/PersonSegmentation) — the same pipeline feeding `VNGeneratePersonSegmentationRequest`.

No example in this repository uses the microphone (`AudioAnalyzer` /
`createAudioInput()`) yet; [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli)'s
`audio-reactive` project template (`metaphor new MySketch --template
audio-reactive`) is the closest working starting point, and the same
permission mechanics apply to it.

## 9. Live performance: OSC, MIDI, Syphon

Sending/receiving external control signals and outputting to other apps.

- [Samples/OSCLoopback](Samples/OSCLoopback) — `OSCSender` / `OSCReceiver` round-tripping the mouse position.
- [Samples/Syphon/SyphonOutput](Samples/Syphon/SyphonOutput) — publishing frames to other Syphon-compatible apps (VJ software, TouchDesigner, etc.).

## Where to go next

- **Full, searchable index**: [`docs/ai/examples-index.md`](../docs/ai/examples-index.md) — every example, with tags, difficulty, and status (`supported` / `partial` / `stub` / `obsolete`).
- **Processing sample by name**: `Basics/` and `Topics/` mirror the official Processing example structure closely — most examples ship the original `.pde` alongside the Swift port.
- **Writing your own sketch with AI**: [`docs/ai/for-sketch-authors.md`](../docs/ai/for-sketch-authors.md).
- **All public API**: [`llms.txt`](../llms.txt) at the repository root, or the [DocC reference](https://shinyaoguri.github.io/metaphor/documentation/metaphor/) if you'd rather browse in a browser.
