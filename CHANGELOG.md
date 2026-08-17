# Changelog

All notable changes to `metaphor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the usual `0.x` caveat: **while the major version is 0, a minor release may
break API**. Those breaks are always listed under a **Breaking Changes** heading
so the eventual 1.0 migration guide can be assembled straight from this file.

Entries for `0.8.0` and earlier are short retrospective summaries written when
this file was introduced — they are not exhaustive. Follow the release link in
each one for the full list of merged pull requests.

<!--
Maintaining this file
  - Do NOT add entries here by hand. A user-facing pull request adds one file
    per change to changelog.d/ (`<slug>.<category>.md` — see
    changelog.d/README.md and CONTRIBUTING.md); the release workflow folds them
    into `## [Unreleased]` and promotes that to the released version. One file
    per change means concurrent pull requests never conflict over these lines,
    which is what the old "append to Unreleased" rule caused. Internal-only
    changes — design docs, CI plumbing, dependency bumps of the website — do
    not need an entry at all.
  - Writing directly under `## [Unreleased]` still works and is still
    collected; it is the escape hatch for a hotfix on a branch where
    changelog.d/ has already been drained, not the everyday path.
  - Subsections, in this order, keeping only the ones you need:
    `### Breaking Changes` (a deliberate extension of Keep a Changelog, so
    upgraders see it first), `### Added`, `### Changed`, `### Deprecated`,
    `### Removed`, `### Fixed`, `### Security`.
  - Write for someone upgrading the library: what changed, and what they must
    do about it. Link the PR or Issue.
  - English, to match the other community-facing documents. Internal design
    docs under docs/design/ stay Japanese.
  - Releases are automated: .github/workflows/release.yml refuses to release
    while changelog.d/ and `## [Unreleased]` are both empty, then collects,
    promotes to `## [X.Y.Z] - YYYY-MM-DD` and copies it into the GitHub Release
    notes (scripts/changelog.py). Do not hand-edit released sections.
-->

## [Unreleased]

## [0.10.0] - 2026-08-17

### Breaking Changes

- The recording and `dispatch` names deprecated in v0.9.0 are **removed** (ADR-0007 phase 2, [#322](https://github.com/shinyaoguri/metaphor/issues/322)). They warned for one minor release; the compiler now rejects them:

  | Removed | Use instead |
  |---|---|
  | `beginSVG(_:)` / `endSVG()` | `beginSVGRecord(_:)` / `endSVGRecord()` |
  | `beginRecord(directory:pattern:)` / `endRecord()` | `beginFrameRecord(directory:pattern:)` / `endFrameRecord()` |
  | `endGIFRecord(_:) async throws` | `endGIFRecordAsync(_:)` |
  | `endVideoRecord() async` (and `VideoExporter.endRecord() async`) | `endVideoRecordAsync()` (and `VideoExporter.endRecordAsync()`) |
  | `dispatch(_:threads:_:)` / `dispatch(_:width:height:_:)` | `dispatch(_:threads:configure:)` / `dispatch(_:width:height:configure:)` |

  Each removal applies to both the `Sketch` layer and the `SketchContext` layer.

  **Most sketches need no change.** The two `dispatch` removals only drop an unlabelled-trailing-closure overload, so the usual `dispatch(kernel, threads: n) { encoder in ... }` still resolves — to the `configure:` version — and keeps compiling. Only a call that passes the closure as an explicit final argument (`dispatch(kernel, threads: n, myClosure)`) has to add the `configure:` label.

  Likewise, `endVideoRecord()` and `VideoExporter.endRecord()` still exist as the synchronous, completion-handler forms; only the same-named `async` overloads are gone. If you were awaiting one, add the `Async` suffix.
- `VignetteEffect.intensity` is now a plain 0…1 strength — `0` disables the
  effect and `1` is the strongest — instead of "the radius at which the picture
  reaches pure black", where **larger meant weaker**. With the old meaning the
  default `VignetteEffect()` crushed everything past `dist >= 0.5` to black,
  which on a 16:9 canvas is most of the frame: writing `addPostEffect(VignetteEffect())`
  was enough to black out a sketch (measured on a real piece: mean luminance
  0.331 → 0.006). To keep an existing look, convert your old value `r` with
  `new = (1.25 - r) / 0.6`, clamped to 0…1:

  | old `intensity` | new `intensity` |
  |---|---|
  | `1.0` (barely visible) | `0.4` |
  | `0.7` | `0.9` |
  | `0.5` (nearly black) | `1.0` |

  `smoothness` is unchanged. Values outside 0…1 are now clamped
  ([#684](https://github.com/shinyaoguri/metaphor/issues/684))
- The 3D prelude now also carries the shaders' `stage_in` structs —
  `Canvas3DVertexOut` / `Canvas3DTexVertexOut` and the two vertex-input structs —
  so a custom material no longer has to copy them by hand
  ([#713](https://github.com/shinyaoguri/metaphor/issues/713)). **If your shader
  defines a struct with one of those names, delete it**: MSL now fails with
  `redefinition of 'Canvas3DVertexOut'`. Structs you named yourself are
  unaffected; the layout is unchanged, so nothing else has to move.
- `arc()` now normalizes its angles the way Processing does
  ([#743](https://github.com/shinyaoguri/metaphor/issues/743)). Two behaviours
  change:
  - **`stopAngle <= startAngle` draws nothing.** It used to draw the arc
    backwards (the segment count was taken from `abs(stop - start)` while the
    step kept its sign). **If you relied on reversed angles**, swap the two
    arguments or add `2 * .pi` to `stopAngle`: `arc(x, y, w, h, .pi, .pi * 0.25)`
    becomes `arc(x, y, w, h, .pi * 0.25, .pi)`. The first reversed call also
    prints a warning in debug builds, so a sketch that silently lost an arc says
    why.
  - **A sweep wider than 2π is clamped to `0…2π`.** It used to keep winding, so a
    translucent fill came out darker on the angles that overlapped and the vertex
    count grew with the number of turns (`5 * .pi` emitted 2.5× the vertices of a
    full circle).

  Non-finite angles (`.nan` / `.infinity`) now draw nothing instead of trapping
  on a `Float`-to-`Int` conversion. SVG export follows the same normalization,
  so a recorded arc matches what was rasterized.
- `textLeading(l)` now takes the line height **in pixels**, like Processing — it
  used to be a multiplier of the font size, which contradicted its own
  documentation ("the line height, in pixels")
  ([#744](https://github.com/shinyaoguri/metaphor/issues/744)). **If you passed a
  multiplier, convert it**: `textLeading(1.5)` with `textSize(20)` becomes
  `textLeading(30)`. Left as it was, `textLeading(1.5)` now asks for a 1.5-pixel
  line height and the lines pile on top of each other; the reverse — a value meant
  as pixels, such as `textLeading(20)` — used to blow the line spacing up to
  `fontSize × 19` and silently drop every line that no longer fit the text box.

  Also as in Processing, `textSize()` and `textFont()` now reset the leading to a
  value derived from the font (`(ascent + descent) * 1.275`), so call
  `textLeading()` *after* them. The default line height is unchanged in spirit but
  slightly looser in numbers: it follows the font's own metrics instead of
  `fontSize * 1.2`.
- Sketch output now lands **inside the project instead of the Desktop**, and an
  explicit path is finally honoured
  ([#757](https://github.com/shinyaoguri/metaphor/issues/757)). `saveFrame(_:)`
  used to prepend `~/Desktop/` unconditionally, so the save location could not be
  chosen at all: `saveFrame("/tmp/shots/a.png")` wrote to
  `~/Desktop/tmp/shots/a.png` — and because the parent directory was created on
  the way, it did not even fail. The same Desktop default was hard-coded in
  `save()`, `beginFrameRecord(directory:)`, `beginVideoRecord(_:)` and
  `endGIFRecord(_:)` / `endGIFRecordAsync(_:)`.

  Every output path now follows one rule:

  | Call | Writes to |
  |---|---|
  | `saveFrame()` | `<project>/output/screen-0001.png` |
  | `saveFrame("shots/a.png")` | `<project>/shots/a.png` |
  | `saveFrame("/tmp/a.png")` / `saveFrame("~/Pictures/a.png")` | unchanged, as given |
  | `save()` | `<project>/output/metaphor_<timestamp>.png` |
  | `beginFrameRecord()` | `<project>/output/metaphor_frames_<timestamp>/` |
  | `beginVideoRecord()` / `endGIFRecord()` | `<project>/output/metaphor_<timestamp>.{mp4,gif}` |

  `<project>` is the process working directory, or `METAPHOR_STATE_DIR` when set
  (`metaphor run` / `watch` pass it to the child, and it is what makes a `.app`
  launched from Finder — where the working directory is `/` — write somewhere
  usable). `beginSVGRecord(_:)` resolves relative paths the same way; it used to
  be plain working-directory relative.

  **If you relied on files appearing on the Desktop**, pass the path explicitly:
  `saveFrame("~/Desktop/screen.png")`. Screenshot failures are also reported
  through `metaphorWarning` now (directory creation and the final PNG write were
  both silent).
- `MShape.normal()` (retained shapes: `createShape()` + `beginShape()`) now applies
  to **every vertex that follows**, up to `endShape()`. It used to apply to the next
  single vertex only, so porting a Processing sketch that calls `normal()` once
  before a run of `vertex()` calls left every vertex but the first at the default
  `(0, 1, 0)` — the shape came out mostly black, and the workaround was to repeat
  `normal()` inside the vertex loop. Immediate mode (`beginShape3D()`) has always
  persisted until `endShape3D()`, Processing's `PShape.normal()` does the same, and
  the umbrella doc already said "the vertices that follow"; the retained
  implementation was the odd one out. **If you repeat `normal()` per vertex, nothing
  changes** — that is still how you give each vertex its own normal. What changes is
  code that called `normal()` for some vertices and relied on the others falling back
  to `(0, 1, 0)`: those vertices now inherit the last normal you set. Shapes that
  never call `normal()` are unaffected (they get automatic face normals,
  [#738](https://github.com/shinyaoguri/metaphor/issues/738))
  ([#876](https://github.com/shinyaoguri/metaphor/issues/876))
- Custom 2D fragment shaders must now return **premultiplied alpha**. The canvas stores
  colors with alpha already applied (see
  [ADR-0012](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0012-alpha-semantics.md)),
  and the preamble gained `metaphorPremultiply()` / `metaphorUnpremultiply()` for the
  conversion:

  ```metal
  // before
  return float4(rgb, 1.0) * in.color;
  // after
  return metaphorPremultiply(float4(rgb, 1.0) * in.color);
  ```

  Shaders that only ever return opaque colors are unaffected — premultiplying an opaque
  color changes nothing. `in.color` still arrives straight (un-premultiplied), as before.
  Textures read inside a custom shader are premultiplied too, so unpremultiply them before
  multiplying by a straight color
  ([#854](https://github.com/shinyaoguri/metaphor/issues/854))
- **`background()` is a replacement, not a composite.** The full-screen quad it falls back to
  is now drawn with blending off, matching what the render pass clear has always done, so both
  paths agree on the meaning (ADR-0012, and Processing's own `SRC` composite). Two consequences
  for existing sketches: `blendMode()` no longer affects `background()`, and a translucent
  background replaces the canvas instead of veiling it — `background(0, 0, 0, 20)` now leaves
  an almost fully transparent canvas rather than fading the previous frame. To fade, draw a
  full-screen `rect()` with the fade color instead
  ([#829](https://github.com/shinyaoguri/metaphor/issues/829))

### Added

- Tutorial parts 1 and 2 are now published: "入門" (getting started) and "2D を描く"
  (drawing in 2D), 16 sections in total. Each section ships a runnable SwiftPM
  package under `Examples/Tutorial/` and a result image generated from it, so
  every line of code in the prose is compiled in CI. Read them on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#488](https://github.com/shinyaoguri/metaphor/issues/488))
- **83 example packages that had no picture now ship one**, shot by actually running
  the sketch headless through the Probe (`make example-shots`). Together with the 162
  images carried over from the Processing originals, every `supported` example outside
  `Examples/Tutorial/` now either has a result image or says in writing why it cannot
  have one. Two declarations carry that: `no-capture.txt` (the picture depends on a
  camera, an external video, or hardware we cannot assume — plus, for now, the handful
  of sketches whose drawing is broken, each naming the issue that tracks it) and
  `probe-input.jsonl` (the sketch needs mouse or keyboard input before it draws
  anything worth looking at — that input is fed to the sketch during the shot). A new
  [`docs/ai/examples-shots.config.json`](../docs/ai/examples-shots.config.json) holds
  per-example exceptions to *when* the frame is grabbed, for sketches that settle into
  their picture on a different schedule than the 1.5 second default
  ([#501](https://github.com/shinyaoguri/metaphor/issues/501))
- Tutorial part 3, "動かす" (motion), is now published — 10 sections covering time
  (`frameCount` / `time` / `deltaTime`), value remapping, easing, trigonometry,
  randomness, Perlin noise, vectors, arrays of moving objects, particles, and
  bulk drawing with `circles()`. As with parts 1 and 2, every section ships a
  runnable SwiftPM package under `Examples/Tutorial/03-Motion/`; sections whose
  point is the movement itself also carry an animated WebP captured from that
  same sketch. Read them on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#508](https://github.com/shinyaoguri/metaphor/issues/508))
- Tutorial part 4, "入力を受ける" (input), is now published — four sections covering
  the mouse (`mouseX` / `pmouseX` / `isMousePressed` and the event callbacks),
  the keyboard (`isKeyDown(_:)` for held and simultaneous keys, `keyCode`
  constants, filtering auto-repeat with `isKeyRepeat`), hit testing and
  hand-built UI (hover / press / drag, buttons and sliders), and windows
  (rendering resolution vs. `windowScale`, letterboxing, secondary windows). Each
  section ships a runnable SwiftPM package under `Examples/Tutorial/04-Input/`.
  The API reference's
  [Getting Started](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/gettingstarted)
  page now points at this part instead of listing the input API twice. Read it on
  the [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/input/) or
  in [`docs/tutorial/`](../docs/tutorial/)
  ([#509](https://github.com/shinyaoguri/metaphor/issues/509))
- Tutorial screenshots can now be captured with input applied: a
  `probe-input.jsonl` next to a tutorial sketch is streamed to the sketch's stdin
  (the JSON Lines input events of CONTRACT.md point 3) before the shot is taken,
  so mouse- and keyboard-driven sections photograph the same picture every time —
  including "button held down" states. See `docs/tutorial/README.md`
  ([#509](https://github.com/shinyaoguri/metaphor/issues/509))
- Tutorial part 5, "3D へ" (into 3D), is now published — ten sections covering the
  pixel-space world coordinates that 3D shares with 2D, the built-in primitives
  and their `detail`, 3D transforms and nested coordinate systems, cameras
  (`camera(eye:center:up:)`, `perspective` vs. `ortho`, `orbitControl()` and the
  fact that it orbits the world origin), the four light types and how fast their
  falloff really is, Blinn-Phong vs. PBR materials, shadow mapping, texturing
  built-in and hand-built geometry, meshes and `loadModel`, and instancing
  thousands of cubes. Each section ships a runnable SwiftPM package under
  `Examples/Tutorial/05-ThreeD/`, and the transform and camera sections carry an
  animated WebP. Read it on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/3d/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#526](https://github.com/shinyaoguri/metaphor/issues/526))
- The API reference now shows what a symbol actually draws: `circle()`, `rect()`,
  `arc()`, `bezier()`, `rotate()`, `rectMode()`, `strokeWeight()` and
  `blendMode()` carry a short self-contained snippet followed by the image it
  produces (`rotate()` also gets an animated GIF). The snippets live in the doc
  comments themselves, are compiled in CI, and the images are shot by running
  them — so the picture can never drift from the code
  ([#531](https://github.com/shinyaoguri/metaphor/issues/531))
- **3D, lighting and motion now carry pictures too**, bringing the reference to 57
  illustrated symbols. The 3D primitives (`box()`, `sphere()`, `cylinder()`, `cone()`,
  `torus()`, `plane()`), the camera and projection calls (`camera()`, `perspective()`,
  `ortho()`, `rotateX()`, and `rotateY()` as a GIF), the whole lighting and material
  set (`lights()`, `ambientLight()`, `directionalLight()`, `pointLight()`,
  `spotLight()`, `specular()`, `shininess()`, `metallic()`, `roughness()`, `pbr()`),
  and `noise()` / `noiseDetail()` / `ease()` (a GIF) all show their output. Several doc
  comments gained notes that only became visible once the pictures were taken — that
  the default `lights()` rig shines from below, that `ortho()`'s omitted bounds do not
  line up with the default camera, and that the default `falloff` of `pointLight()` /
  `spotLight()` lets almost no light reach anything at pixel-space distances
  ([#759](https://github.com/shinyaoguri/metaphor/issues/759))
- Tutorial part 6, "GPU を使う" (using the GPU), is now published — six sections
  covering the `compute()` hook (writing an MSL kernel, `createComputeKernel`,
  `GPUBuffer`, `dispatch`, matching struct layouts across Swift and MSL, and the
  one-frame delay before a dispatch result can be read back on the CPU), GPU
  particles (`createParticleSystem` with a million particles, emitters, forces,
  and the pixel-space defaults that need scaling up), post-processing (the
  built-in effects, their ordering, and the fact that they apply to everything on
  screen), custom post effects (a hand-written MSL fragment shader via
  `createPostEffect` plus `setParameters`), 2D custom draw shaders (`loadShader` /
  `createShader` / `shader` / `resetShader`, the built-in uniforms in `buffer(3)`,
  `setParameters` into `buffer(4)`, and saving a `.metal` file to reload it), and
  what is still missing (no vertex-stage replacement in 2D).
  Each section ships a runnable SwiftPM package under `Examples/Tutorial/06-GPU/`,
  and the particle and post-process sections carry an animated WebP. Read it on
  the [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/gpu/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#543](https://github.com/shinyaoguri/metaphor/issues/543))
- Tutorial part 8, "外とつなぐ" (connecting to the outside), is now published —
  four sections covering OSC (`createOSCSender` / `createOSCReceiver`, address
  patterns, why handlers only fire inside `poll()`, the four `OSCValue` cases and
  guarding against mismatched senders, and reaching other apps or machines), MIDI
  (`createMIDI`, a `start()` that reports failure through `isRunning` /
  `lastError` instead of throwing, cached values versus one-shot events, and the
  128 steps a 7-bit CC gives you), Syphon (`syphonName` in `SketchConfig`, the
  fact that what gets published is the final offscreen texture rather than the
  letterboxed window, and the automatic switch to a timer-driven render loop so
  output survives being occluded), and parameters (`@Param`, the one-line
  `gui.params()` panel, persistence in `.metaphor/params/params.json`, and
  writing values from outside through `set-request.json`). Each section ships a
  runnable SwiftPM package under `Examples/Tutorial/08-Connect/`. Read it on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/connect/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#545](https://github.com/shinyaoguri/metaphor/issues/545))
- Tutorial part 9, "作品にする" (making it a work), is now published — five
  sections on getting a sketch out of the window: stills (`save(_:)` as a
  reservation carried out at the end of the frame, the desktop-bound `save()` /
  `saveFrame()`, and PNG sequences through `beginFrameRecord` /
  `endFrameRecord`), motion (`beginVideoRecord` with `VideoExportConfig`, the
  completion callback that says when the file is actually finished, and why
  `beginGIFRecord(fps:)` sets playback speed without dropping frames), vector
  (`beginSVGRecord` / `endSVGRecord` recording the same draw calls the screen
  gets, what is skipped, and how to draw for a pen plotter), deterministic
  rendering (fixed seeds plus frame-number-driven motion plus
  `beginOfflineRender(fps:)`, render resolution separated from window size, and
  handing the sequence to `ffmpeg`), and long runs (`saveState()` /
  `restoreState(_:)`, `preserveClock`, bounded containers, and
  `enablePerformanceHUD()`). Each section ships a runnable SwiftPM package under
  `Examples/Tutorial/09-Artwork/`. Read it on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/artwork/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#546](https://github.com/shinyaoguri/metaphor/issues/546))
- Tutorial part 10, "AI と作る" (making things with an AI), is now published, and
  with it the tutorial's ten-part arc is complete. Five sections on handing the
  "run it and look at it" half of the loop to an agent: the observation loop
  (why code that compiles is not code that draws, and how `contentFraction` /
  `contentBounds` turn "the frame is empty" into a number), declaring state with
  `probe(_:_:)` (the accepted types, the no-op contract when no probe plugin is
  registered, `METAPHOR_PROBE=1`, and what `custom` / `customTypes` / `stats` /
  `performance` hold in `frame.json`), connecting an AI client over MCP (one-time
  registration, the tools it gets, when to snapshot versus capture a sequence,
  and why `set_param` beats a rebuild for hunting values), sharing one running
  sketch between a person and an agent (`metaphor watch` first, client second —
  and what breaks in the other order), and the context an agent needs
  (`llms-sketch.txt` / `llms.txt` / the examples index, plus asking for
  verification so the loop actually closes). Three of the sections ship a
  runnable SwiftPM package under `Examples/Tutorial/10-AI/`; the other two are
  about operating the tools, and say so. Read it on the
  [tutorial site](https://shinyaoguri.github.io/metaphor/tutorial/ai/) or in
  [`docs/tutorial/`](../docs/tutorial/)
  ([#547](https://github.com/shinyaoguri/metaphor/issues/547))
- Every published tutorial section now ends with a **"ふりかえり" (recap)** checklist,
  and every part opens with **"この部の前提" (prerequisites)**. The recap is three to
  five task-list items stating what the section made possible, so a reader can spot
  what they skimmed past without a quiz; the prerequisites name the earlier parts and
  the specific things they taught (Part 1 names the Swift knowledge and the supported
  hardware instead). Both were applied retroactively to all 40 published sections
  across Parts 1–5, and [`docs/tutorial/README.md`](../docs/tutorial/README.md) now
  carries them as writing conventions so later parts are written with them from the
  start. The tutorial site styles the task lists so the checkbox replaces the bullet
  instead of doubling it
  ([#549](https://github.com/shinyaoguri/metaphor/issues/549))
- **Example screenshots can now be taken with mouse and keyboard input applied.**
  `make example-shots` streams a sketch's `probe-input.jsonl` (the JSON Lines input
  events of CONTRACT.md point 3) to its stdin once the draw loop is running, then
  grabs the frame — the same mechanism the tutorial shots already used, now shared by
  both scripts (`scripts/shots_common.py`). Eleven examples that could only be
  photographed as a clipped picture drawn at the origin now ship one that shows what
  the sketch is about: `PrimitivePShape`, `PolygonPShape`, `GroupPShape`,
  `PathPShape`, `RGBCube`, `SaveFile1`, `Zoom`, `BlurFilter`, `ImageMask`,
  `OSCLoopback` and `PluginMouseTrail`. Because the shot is taken after the script has
  been played back, retaking it produces the same picture
  ([#610](https://github.com/shinyaoguri/metaphor/issues/610))
- 2D drawing can now run your own Metal fragment shader
  ([#647](https://github.com/shinyaoguri/metaphor/issues/647)). `loadShader(path,
  fragment:)` / `createShader(source:fragment:)` build a `Shader2D`, `shader(_:)`
  applies it so `rect()` / `circle()` / `line()` become surfaces the shader runs
  on, and `resetShader()` goes back to the built-in shader — the 2D counterpart
  of `createMaterial()` / `material()` / `noMaterial()` in 3D. Also available on
  `Graphics` (offscreen buffers).
  - metaphor always prepends a preamble (`#include <metal_stdlib>`,
    `using namespace metal;`, and the `Canvas2DVertexOut` /
    `Canvas2DTexVertexOut` / `Canvas2DShaderUniforms` definitions), so a shader
    file contains just the fragment function. Do not redefine those structs.
  - 2D color vertices carry no UV, so build one from the fragment's
    `[[position]]` (screen pixels) and the supplied `resolution`:
    `float2 uv = in.position.xy / u.resolution;` — the same shape as Shadertoy's
    `fragCoord / iResolution`. `Canvas2DShaderUniforms` (`buffer(3)`) also
    carries `mouse`, `time` and `frameCount`; `setParameters(_:)` sends your own
    struct to `buffer(4)`, frozen into the batch at the time you draw.
  - `blendMode(.difference)` and `.exclusion` are implemented with framebuffer
    fetch and cannot coexist with a custom fragment shader. While one is applied
    they fall back to normal alpha blending and warn once.
  - New example: `Examples/Topics/Shaders/CustomShader2D`.
- Shader files now hot reload on save — no rebuild, no restart
  ([#648](https://github.com/shinyaoguri/metaphor/issues/648)). Any `.metal`
  file read through `loadShader(_:fragment:)` (2D),
  `createMaterialFromFile(path:fragmentFunction:vertexFunction:)` (3D) or the
  new `createPostEffectFromFile(name:path:fragmentFunction:)` (post-process) is
  watched; saving it recompiles the shader and swaps it into the running sketch.
  Nothing to write in the sketch — editing the file *is* the workflow.
  - A shader that fails to compile leaves the **last working one in place** and
    prints the compiler error to stderr. Half-written MSL no longer blanks the
    window; fix the file, save again, and it recovers.
  - While `noLoop()` is in effect a successful reload triggers one redraw, so a
    stopped sketch still shows the new shader.
  - Enabled by default in debug builds only, so a release build ships no file
    watcher. Override with `SketchConfig(shaderHotReload:)` or the environment
    variable `METAPHOR_SHADER_HOT_RELOAD` (`1` enables, `0` disables). The
    watcher starts only once a file-backed shader is actually loaded.
  - `createPostEffectFromFile` compiles the file as-is, like
    `createMaterialFromFile` — put the `PostProcessShaders.commonStructs`
    definitions in the file if the fragment needs `PPVertexOut` /
    `PostProcessParams`. Effects built from a source string
    (`createPostEffect(name:source:fragmentFunction:)`) have no file to watch,
    so they still need `reloadShaderFromFile(key:path:)` if you want to swap
    them by hand.
- `loadFont(path)` loads a font file (`.ttf` / `.otf` / `.ttc` / `.otc` / `.dfont`)
  and returns an `MFont`; pass it to `textFont(font)` to draw and measure text with
  it. The font is registered for the current process only, so it never touches the
  system font configuration, and results are cached by path — calling `loadFont`
  every frame does not re-register. Font family names still work via
  `textFont(String)`
  ([#649](https://github.com/shinyaoguri/metaphor/issues/649))
- Glyph outlines are now available as geometry, which makes generative typography
  possible: `textToPoints(str, x, y)` returns the points along the outline as a flat
  array (p5-compatible), `textToContours(str, x, y)` returns them grouped per contour,
  and `textToShape(str, x, y)` returns an `MShape` whose children carry the counters
  (the hole in `o`) as contours, so `shape()` fills it correctly. All three read
  `textSize` / `textFont` / `textAlign` exactly like `text()` does, so the same
  arguments place the outline where the text would have been drawn. `sampleFactor`
  controls how finely curves are flattened
  ([#650](https://github.com/shinyaoguri/metaphor/issues/650))
- Probe `frame.json` now reports which file-backed shaders drew the frame, so a
  tool can tell when a `.metal` save has actually landed
  ([#671](https://github.com/shinyaoguri/metaphor/issues/671)). New optional
  top-level key `shaders`, additive under the existing `schemaVersion: 4`:
  - `generation` — reload landings since launch (`+1` per reload where at least
    one shader was swapped in). Monotonic, so editing a shader and reverting it
    still registers.
  - `digest` — aggregate hash of the shader sources currently loaded in the
    library. Content-derived, so it survives a restart. Treat it as an opaque
    identifier and only compare it for equality.
  - `lastError` — the compiler error from the most recent reload, omitted once
    everything compiles again. This is what separates "not reflected yet" from
    "broken, so it will never be reflected".
  - Both values move **only after a swap succeeds**, so there is no window where
    the stamp is new but the picture is old. While a shader fails to compile the
    last working one keeps drawing and the values stay put — correctly reporting
    "not reflected".
  - The key is omitted entirely for sketches that load no shader from a file.
    `sourceStamp` is unchanged and still covers rebuild-and-restart edits.
- `directionalLight` / `pointLight` / `spotLight` now take an `intensity`
  multiplier (default `1.0`, so existing sketches are unchanged). PBR shades
  direct light as `albedo / π` with no IBL, so a single light used to be too dim
  to give shape and the only way to compensate was to add more lights — now
  `directionalLight(-0.4, 1, -0.6, intensity: 3)` does it with one. The shader
  already multiplied by `colorAndIntensity.w`; only the API was hard-coding it to
  `1.0`. The same argument is available on `Graphics3D` (`createGraphics3D`).
  Note that the default rig from `lights()` (intensity `0.7`) renders about 35%
  darker under `pbr(true)` than under Blinn-Phong — set your own lights with
  `intensity` when you need PBR to read
  ([#687](https://github.com/shinyaoguri/metaphor/issues/687))
- New `METAPHOR_STATE_DIR` environment variable sets the base directory for every
  `.metaphor/` file protocol — the Probe (`.metaphor/probe/`), the Parameter Store
  (`.metaphor/params/`) and state-preserving reload (`.metaphor/state/`). These were
  resolved against the process's working directory, which is fine under `swift run`
  but breaks as soon as a sketch is launched as a `.app`: LaunchServices starts it
  with **cwd = `/`**, so probe requests are never answered and parameters are never
  persisted. That is exactly the shape a permanently installed piece runs in (`open`,
  a login item, the Dock). Point the variable at the project and all three agree:

  ```bash
  open -n .build/strata.app --env METAPHOR_PROBE=1 --env "METAPHOR_STATE_DIR=$PWD"
  ```

  Unset, everything resolves against the working directory exactly as before.
  `metaphor run` / `metaphor watch` (from metaphor-cli 0.6.0) pass the resolved path
  down to the sketch, so the CLI and the sketch can never disagree because of cwd
  ([#688](https://github.com/shinyaoguri/metaphor/issues/688))
- New `@Interpolated` property wrapper and `Blendable` protocol interpolate a
  **bundle of values** in one line, so scene transitions no longer need a
  hand-written `blend` function with one line per field. Adding a field used to
  mean remembering to extend that function; forgetting still type-checked and
  showed up as "only that one parameter snaps instead of easing", which is hard
  to spot. `Int` and `Double` now conform to `Interpolatable` as well (`Int`
  rounds, so band counts and step counts can be blended too):

  ```swift
  final class SceneProfile: Blendable {
      @Interpolated var elevation: Float = 210
      @Interpolated var bands: Int = 7
      @Interpolated var lightDirection = SIMD3<Float>(-0.4, 1, -0.6)
      init() {}
  }

  let current = SceneProfile.blend(dawn, dusk, ease(t))
  // or, without allocating each frame:
  profile.blend(from: dawn, to: dusk, t: ease(t))
  ```

  `Blendable` is class-only: `@Interpolated` boxes are reference types, so a
  struct would share them between copies
  ([#691](https://github.com/shinyaoguri/metaphor/issues/691))
- Sketches can now read their own runtime performance through `performance`:
  measured `fps`, `frameTimeMs` (mean / max), `memoryMB`, `cpuPercent` and
  `thermalState`. These are the same values — same collection path, same
  semantics — that the Probe writes into `frame.json`, but they are readable
  **whether or not the Probe is enabled**, so a piece can degrade itself
  (fewer particles, a lighter scene) instead of depending on an external process
  watching it. The syscall-backed fields (`memoryMB`, `cpuPercent`) refresh at
  most every 0.5s, so reading `performance` every frame costs nothing extra:

  ```swift
  if let fps = performance.fps, fps < 55 { particleCount -= 200 }
  if performance.thermalState == .serious { scene = .calm }
  ```

  ([#692](https://github.com/shinyaoguri/metaphor/issues/692))
- `emissive` and `specular` now take three channel values like `fill` does:
  `emissive(214, 168, 255)` instead of `emissive(Color(r: 0.84, g: 0.66, b: 1))`.
  The values follow `colorMode` (0–255 by default), so material colors no longer
  need a different scale from `fill` / `stroke` / `background` / `ambientLight`
  on the next line. The existing `Color` and grayscale overloads are unchanged,
  and the same three-argument form is available on `Graphics3D`
  (`createGraphics3D`). No alpha argument: the fourth component of each material
  slot is `metallic` / `shininess`, so there is nowhere to put it — matching
  Processing, where `emissive()` and `specular()` are three-channel only
  ([#700](https://github.com/shinyaoguri/metaphor/issues/700))
- `toneMapping(_:)` and `exposure(_:)` map 3D lighting results into 0…1 so that
  bright highlights keep their gradation instead of clamping to flat white.
  `ToneMapMode` offers `.none` (**the default** — existing sketches render
  exactly as before), `.reinhard` and `.acesFilmic`; `exposure(_:)` applies
  before tone mapping and defaults to `1.0` (identity). Both are properties of
  the whole picture: they are **not** restored by `pushStyle()` / `popStyle()`,
  and they apply only to lit 3D geometry — 2D drawing and the unlit pass are
  untouched. Reach for `.acesFilmic` when using metals or strong lights
  ([#706](https://github.com/shinyaoguri/metaphor/issues/706),
  [#293](https://github.com/shinyaoguri/metaphor/issues/293))
  - Custom material shaders pick this up for free as long as they call
    `calculateLighting` and prefix their source with
    `BuiltinShaders.canvas3DStructs`. Shaders that hand-copy the `Material3D`
    struct instead must add the new trailing `float4 toneMapParams;` field —
    it grew from 64 to 80 bytes.
- `environment(_:intensity:background:)` lights 3D geometry with an image-based
  environment and draws it as a skybox behind the scene, so `metallic` finally
  becomes usable: without an environment, raising `metallic` removes diffuse
  light with nothing to reflect, and the surface collapses into a featureless
  grey blob. Three presets — `.studio`, `.sunset`, `.overcast` — are generated
  procedurally, so no HDR asset is needed; each is baked (environment cube →
  irradiance → GGX-prefiltered mips) once per preset and then only sampled.
  `noEnvironment()` turns it back off
  ([#710](https://github.com/shinyaoguri/metaphor/issues/710),
  [#293](https://github.com/shinyaoguri/metaphor/issues/293))
  - Sketches that never call `environment(...)` render exactly as before.
  - IBL applies to the **PBR** path only (`roughness(_:)` / `pbr(true)`);
    Blinn-Phong is unchanged. An environment-lit PBR material is also the one
    case that stays lit with no lights at all, so `environment(.studio)` alone
    is enough to shade a metal.
  - Setting an environment promotes tone mapping to `.acesFilmic` unless
    `toneMapping(_:)` was called explicitly, and suppresses the default ambient
    (an explicit `ambientLight(_:)` still wins) so the two are not counted twice.
  - The skybox is drawn just before the first 3D draw call of the frame: 2D drawn
    before it is covered, 2D drawn after it (HUDs and other foreground) stays on
    top, and a frame with no 3D draws no skybox. Pass `background: false` for
    lighting without the backdrop.
  - Custom material shaders keep working unchanged; they opt into IBL by calling
    the new `calculateLighting` overload that also takes the two `texturecube`
    arguments bound at `texture(2)` / `texture(3)`. Shaders that hand-copy
    `Material3D` should note that `toneMapParams.z` now carries the environment
    intensity (the struct layout is unchanged).
- New `KeyCode` namespace for the macOS virtual key codes: `KeyCode.return`, `KeyCode.space`,
  `KeyCode.left`, … carrying exactly the values of the Processing-style globals (`RETURN`,
  `SPACE`, `LEFT`, …), which stay as they are. Reach for it when your sketch also does
  `import Foundation`: four of the globals — `RETURN` / `TAB` / `BACKSPACE` / `CONTROL` —
  collide with macros of the same name in Darwin's `sys/tty.h` and fail to compile with
  `ambiguous use of 'RETURN'`. Module-qualifying (`metaphor.RETURN`) does not help, because
  `metaphor` re-exports Foundation; `KeyCode.return` does
  ([#794](https://github.com/shinyaoguri/metaphor/issues/794))
- `metaphorWarning(_:)`, `metaphorAlert(_:)` and `metaphorDiagnostic(_:)` are now
  public, so every module — and your own extensions — can emit the same
  `[metaphor] …` diagnostics instead of hand-rolling `print()`. They moved into a
  new zero-dependency `MetaphorLog` target that `MetaphorCore` re-exports, so
  `import metaphor` / `import MetaphorCore` reaches them under the same names as
  before. Pick `metaphorWarning` (stdout, DEBUG only) when the caller passed a bad
  value, `metaphorAlert` (stderr, always) when the caller is right but the
  environment is silently broken, and `metaphorDiagnostic` (stderr,
  `METAPHOR_DEBUG=1` only) for ignorable internal events worth isolating
  ([#805](https://github.com/shinyaoguri/metaphor/issues/805))
- `isInFront(x, y, z)` tells you whether a 3D point sits in front of the camera
  plane, i.e. whether `screenX/screenY/screenZ` returned a usable value. Points
  behind the camera get a negative clip `w`, so the perspective divide mirrors
  their screen x/y through the origin and pushes the depth outside `0...1` —
  and nothing in the returned value said so, which made labels and culling
  built on `screenX/Y/Z` silently wrong. Guard those call sites with the new
  predicate:

  ```swift
  if isInFront(px, py, pz) {
      text("label", screenX(px, py, pz), screenY(px, py, pz))
  }
  ```

  A `true` result only promises the value is not mirrored — not that the point
  is on screen, and not that `screenZ` lies in `0...1` (it does so only inside
  the frustum). Orthographic projection has no perspective divide and therefore
  never mirrors, so `isInFront` is always `true` there. Available on `Sketch`,
  `SketchContext`, and `Canvas3D`
  ([#824](https://github.com/shinyaoguri/metaphor/issues/824))
- `Graphics3D` gained `background()` — the same three overloads `Graphics` has
  (`Color`, a grayscale value, and channel values with an optional alpha). Until now a 3D
  offscreen buffer had no way to say what its backdrop should be and was stuck on opaque
  black, so putting a 3D layer in front of a `MergePass(.alpha)` wiped out everything
  underneath. `background(0, 0, 0, 0)` now starts the layer transparent. Like the 2D
  `background()`, it replaces rather than composites (ADR-0012), it takes effect in the
  frame it is called even when called mid-frame, and the color persists across frames.
  **The default is unchanged**: a `Graphics3D` you never call `background()` on still
  clears to opaque black, matching `Graphics`
  ([#830](https://github.com/shinyaoguri/metaphor/issues/830))
- `MShape.fill(gray, alpha)` and `MShape.stroke(gray, alpha)`, so a retained
  shape definition can set a translucent gray the way the sketch-level
  `fill(_:_:)` / `stroke(_:_:)` already could. Both values are read in the
  shape's `colorMode()` range
  ([#853](https://github.com/shinyaoguri/metaphor/issues/853))
- The API reference is now published in Japanese as well, at
  [`/reference/ja/`](https://shinyaoguri.github.io/metaphor/reference/ja/documentation/metaphor/),
  alongside the English one. English doc comments stay the canonical source; the Japanese
  pages are a generated artifact built by applying a translation ledger
  (`docs/reference/i18n/ja.json`) to the DocC output, so declarations, parameter tables and
  code samples are never touched. Passages without a translation yet are shown in English.
  Each page carries a language link in its header. See
  [ADR-0011](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0011-docc-english-canon-japanese-generated.md)
  for the reasoning and the known limits (DocC's own UI labels stay English, and the link
  goes to the other language's top page rather than the current page).
- The project website now has a tutorial section at
  [`/tutorial/`](https://shinyaoguri.github.io/metaphor/tutorial/) (English at
  `/en/tutorial/`), with a chapter sidebar, per-page table of contents, previous
  / next paging and Shiki syntax highlighting. It publishes `docs/tutorial/`
  directly — the Markdown in the repository stays the single source of truth, so
  editing a part there updates the site with no extra step
  ([#487](https://github.com/shinyaoguri/metaphor/issues/487))

### Changed

- The README and the DocC "Getting started" article now hand their introductory
  material over to the tutorial instead of repeating it. `README.md` /
  `README.en.md` gained a `Tutorial` section linking every published part (1–4)
  and dropped the lifecycle table and the "common functions" cheat sheet, which
  Parts 1 and 2 cover in full; `GettingStarted.md` is trimmed to install + a
  first sketch + symbol links, sending the lifecycle and `SketchConfig` details
  to Part 1. Nothing about the API changed — only where each topic is explained
  ([#510](https://github.com/shinyaoguri/metaphor/issues/510))
- API reference pages now put the result image and its code side by side, the way
  the p5.js reference does, instead of stacking them. Symbols whose figure is wide
  or whose code lines are long (`bezier()`) keep the full-width stacked layout
  ([#531](https://github.com/shinyaoguri/metaphor/issues/531))
- The tutorial site now honors **`prefers-reduced-motion`**. A section that carries
  a motion clip (an animated WebP) also carries the still frame it was cut from,
  and a reader who asked their system to reduce motion is served the still alone —
  the clip's paragraph is dropped, and because it never renders, the browser does
  not download it either. The pairing comes from the image ledger
  (`docs/tutorial/images/manifest.json`), which records the still and the clip in
  one entry, so it survives the move to Gyazo where neither the URL nor the file
  extension distinguishes them. GitHub's Markdown view cannot be controlled this
  way and still autoplays. Alongside it, the **alt text of all 65 published images**
  was rewritten from labels ("the result of easing") into descriptions of what is
  actually visible ("three circles chasing a white ring, the ones with a smaller
  easing coefficient trailing further behind"), and
  [`docs/tutorial/README.md`](../docs/tutorial/README.md) now carries the rule as a
  writing convention: say what can be seen, put the movement in the clip's alt, and
  make the still's alt carry the section on its own
  ([#553](https://github.com/shinyaoguri/metaphor/issues/553))
- `DynamicMesh` no longer reallocates every GPU buffer on every change. Dirty
  tracking is now per kind (vertices / indices / UVs) and updates copy into the
  existing buffer when it is large enough, so animating vertices leaves the
  **index buffer untouched** instead of rebuilding it each frame. Vertex and UV
  buffers cycle through a ring of three — the same depth as the renderer's
  triple buffering — so the GPU never reads a buffer being overwritten. On a
  128×128 heightfield (16,384 vertices / 96,774 indices) this removes about
  1MB of buffer allocation per frame (≈60MB/s at 60fps); 60 frames of vertex
  updates measured 162ms → 117ms
  ([#686](https://github.com/shinyaoguri/metaphor/issues/686))
- `BuiltinShaders.canvas3DStructs` / `canvas3DLightingFn` — the MSL prelude you
  prepend to a custom 3D material shader — are now generated from the same
  headers the built-in shaders use (`Shaders/Metal/*.h`) instead of being kept as
  a second, hand-written copy
  ([#707](https://github.com/shinyaoguri/metaphor/issues/707)). The lighting maths
  is unchanged and no shader needs editing, but the strings themselves are not
  byte-identical: they carry the headers' comments (about 1.4x longer) and every
  function is now `static inline`. If you match on the prelude text, or read line
  numbers out of Metal compile errors for a shader you built by concatenation,
  those line numbers shift.
- `createMaterial(source:fragmentFunction:vertexFunction:)` and
  `createMaterialFromFile(path:fragmentFunction:vertexFunction:)` now **always**
  prepend the MSL prelude (`BuiltinShaders.canvas3DPreamble` = `#include
  <metal_stdlib>` + `using namespace metal;` + the 3D structs + the lighting
  functions), the way 2D's `createShader()` / `loadShader()` already did
  ([#713](https://github.com/shinyaoguri/metaphor/issues/713)). Write the
  fragment function and nothing else — forgetting the prelude used to fail with
  `use of undeclared identifier 'Canvas3DUniforms'`.
  - Shaders that prepend the prelude themselves keep working: the prelude is
    wrapped in an `#ifndef` guard, so a second copy expands to nothing.
  - `BuiltinShaders.canvas3DPreamble` is new and public; the existing
    `canvas3DStructs` / `canvas3DLightingFn` are unchanged in content but now
    carry that guard.
- `BuiltinShaders.canvas2DStructs` — the MSL prelude `createShader()` /
  `loadShader()` prepend to a custom 2D shader — is now generated from the same
  header the built-in shaders use (`Shaders/Metal/MetaphorCanvas2DTypes.h`)
  instead of being a second, hand-written copy, matching what 3D (#707) and
  post-processing (#718) already do
  ([#714](https://github.com/shinyaoguri/metaphor/issues/714)). Layouts are
  unchanged and no shader needs editing, but the string itself is not
  byte-identical: it carries the header's comments and two extra types
  (`Canvas2DVertexIn` / `Canvas2DTexVertexIn`, the built-in vertex inputs). If
  you read line numbers out of Metal compile errors for a shader you built by
  concatenating the prelude yourself, those line numbers shift.
  - **If your shader defines `Canvas2DVertexIn` or `Canvas2DTexVertexIn` by
    hand**, delete those definitions: MSL now fails with `redefinition of
    'Canvas2DVertexIn'`. The `[[stage_in]]` types you actually write against
    (`Canvas2DVertexOut` / `Canvas2DTexVertexOut`) are unchanged.
- `createPostEffect(name:source:fragmentFunction:)` and
  `createPostEffectFromFile(name:path:fragmentFunction:)` now **always** prepend
  the MSL prelude (`PostProcessShaders.postProcessPreamble` = `#include
  <metal_stdlib>` + `using namespace metal;` + `PPVertexOut` +
  `PostProcessParams`), the way 2D's `createShader()` / `loadShader()` and 3D's
  `createMaterial()` already did
  ([#718](https://github.com/shinyaoguri/metaphor/issues/718)). Write the
  fragment function and nothing else — forgetting the prelude used to fail with
  `use of undeclared identifier 'PPVertexOut'`. The same prelude is applied on
  every shader hot reload, so a saved file no longer has to carry it either.
  - Effects that prepend `PostProcessShaders.commonStructs` themselves keep
    working: the prelude is wrapped in an `#ifndef` guard, so a second copy
    expands to nothing.
  - **If your shader defines `PPVertexOut` or `PostProcessParams` by hand**
    (copied from the docs rather than taken from `commonStructs`), delete those
    definitions: MSL now fails with `redefinition of 'PPVertexOut'`. The layout
    is unchanged, so deleting is all it takes.
  - `PostProcessShaders.postProcessPreamble` is new and public.
    `PostProcessShaders.commonStructs` now holds **only** the two structs (plus
    the guard); `#include <metal_stdlib>` / `using namespace metal;` moved to
    `postProcessPreamble`. Sources that concatenated `commonStructs` and went
    through `createPostEffect()` are unaffected — the preamble supplies both
    lines.
- `beginShape3D(.lines)` and `beginShape3D(.points)` now take their color from
  `stroke()` instead of `fill()`, matching Processing's LINES / POINTS. Changing
  `stroke()` between vertices colors each segment or point individually, exactly
  as changing `fill()` does for the surface modes. Two things are deliberately
  unchanged: a color passed explicitly to `vertex(x, y, z, color)` still wins
  over both (so the per-point colors added in
  [#825](https://github.com/shinyaoguri/metaphor/issues/825) keep working), and
  a shape drawn under `noStroke()` still falls back to the fill color rather
  than disappearing. Sketches that set `fill()` to color their lines or points
  should set `stroke()` instead. Fixed alongside it: immediate-mode `.points`
  had its own encoding path with no stroke pass, so the *same* sketch drew
  differently depending on whether `shadows()` was enabled — points now go
  through the same path as every other shape
  ([#739](https://github.com/shinyaoguri/metaphor/issues/739))
- `ortho()` called without arguments now lines up with the default camera, so a
  bare `ortho()` draws in the same pixel coordinates as 2D
  ([#777](https://github.com/shinyaoguri/metaphor/issues/777)). Orthographic
  projection applies in **view space**, but the omitted planes used to be filled
  with world-space canvas bounds (`left: 0`, `right: width`, `bottom: height`,
  `top: 0`), whose origin sits in a corner rather than at the view origin — the
  subject landed exactly half a screen off and upside down, and the fixed
  `near`/`far` of ±1000 clipped anything placed a little further back.

  | Plane | Before | Now |
  |---|---|---|
  | `left` / `right` | `0` / `width` | `-width / 2` / `width / 2` |
  | `bottom` / `top` | `height` / `0` | `-height / 2` / `height / 2` |
  | `near` / `far` | `-1000` / `1000` | ∓ (default camera distance × 10), matching `perspective()`'s default depth |

  `near` and `far` became `Float?` so they can follow the canvas height; passing
  numbers is unchanged. `Graphics3D.ortho()`, which had its own `-10` / `10000`
  defaults, now resolves them the same way as the other layers. Sketches that
  called `ortho()` with no arguments change appearance — for the old framing,
  pass the previous values explicitly:
  `ortho(left: 0, right: width, bottom: height, top: 0, near: -1000, far: 1000)`.
- `GKNoiseWrapper` now documents that its two ways of reading the noise use
  different coordinate spaces, instead of leaving it to be discovered. Behaviour
  is unchanged; what changed is what the API promises. `sample(x:y:)` samples the
  noise space directly and applies neither `NoiseConfig.origin` nor
  `NoiseConfig.sampleScale` — those two are grid-only, steering `sampleGrid`,
  `texture`, `image` and `colorMappedTexture`. The two entry points agree on the
  grid's first sample (`sample(x: origin.x, y: origin.y)`) and nowhere else:
  GameplayKit does not step `GKNoiseMap` by `origin + index × sampleScale`, and
  the step it does use varies with the grid's `width` / `height`, so the same
  `sampleScale` puts index `(1, 0)` at different points in the noise on a 64×64
  and a 16×16 grid. Read the field through one entry point per sketch; if you
  need `origin` / `sampleScale` applied to point sampling, offset and scale the
  coordinates yourself before calling `sample(x:y:)`
  ([#785](https://github.com/shinyaoguri/metaphor/issues/785))
- `Physics2D.bounds` walls now behave like an immovable body carrying the same
  coefficients as the body touching them: `PhysicsBody2D.restitution` and
  `.friction` apply at the walls, and the push-back no longer leaks into the
  Verlet velocity (a clamped body used to gain or lose speed for free). A body
  therefore bounces off the world walls exactly as it does off a static body, and
  the default `restitution` of `0.5` means sketches relying on `bounds` as a
  container will now see bodies bounce. Set `restitution = 0` (and `friction = 0`)
  on those bodies to keep the previous behaviour
  ([#796](https://github.com/shinyaoguri/metaphor/issues/796))
- `Physics2D.step(_:iterations:)` now warns (DEBUG) when `iterations` is negative
  instead of dropping the step in complete silence. The silence was not a design
  choice: `MetaphorPhysics` is a Tier 1 module and simply could not reach the
  shared logger
  ([#805](https://github.com/shinyaoguri/metaphor/issues/805))
- Release builds no longer print library warnings to stdout. The bridge helpers
  (`createSourcePass`, `createEffectPass`, `createMergePass`, `createPhysics2D`,
  `createAudioInput`, `createOSCSender`), `MLTextureConverter`, `VideoPlayer`, the
  OSC receiver/sender and `SyphonOutput` used to write `print("[metaphor] …")`
  unconditionally, because the shared logger was unreachable from those modules.
  Argument mistakes are now DEBUG-only and environment-level failures go to
  stderr, leaving stdout — which is shared with Syphon output and the JSON Lines
  channel `metaphor-cli` speaks — clean
  ([#805](https://github.com/shinyaoguri/metaphor/issues/805))
- The tutorial's 65 images no longer live in the repository. They are hosted on
  Gyazo, and `docs/tutorial/` now carries only the prose and a ledger
  (`docs/tutorial/images/manifest.json`) recording the immutable URL and content
  hash each section points at. Nothing changes for readers: the tutorial site
  still serves locally optimized images (Astro fetches and re-encodes them at
  build time, animation intact), and the Markdown still renders on GitHub. What
  changes is how a retake works — `make tutorial-shots` now captures, uploads,
  and rewrites the URLs in the prose for you, so never edit an image URL by
  hand. Assets are append-only: a retake publishes a new URL and leaves the old
  one alive, so checking out an older revision still shows the pictures that
  revision was written against. Two consequences worth knowing: images do not
  render offline, and a fork cannot replace one without a maintainer uploading
  it. Rationale and the measurements behind it are in
  [ADR-0010](../docs/adr/0010-tutorial-images-via-gyazo.md)
  ([#511](https://github.com/shinyaoguri/metaphor/issues/511))
- **The API freeze announced with `v0.9.0` has been withdrawn.** Design work was
  still outstanding when it shipped — renamed APIs whose old spellings are still
  deprecated-but-present, and undecided Processing-compatibility semantics — and
  the freeze made that work unreachable
  ([ADR-0009](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0009-unfreeze-api-until-1-0.md),
  [#477](https://github.com/shinyaoguri/metaphor/issues/477)). Until `1.0.0`, a
  breaking change may ship in a **minor** release when the design justifies it:
  - Deprecation stays the default path — a symbol is marked
    `@available(*, deprecated, renamed:)` in one published release before it is
    removed — and every breaking change still gets a `### Breaking Changes`
    entry with a migration table.
  - Nothing changes for runtime contracts (Probe wire schema, stdin protocol,
    contract environment variables) or for rendering-output disclosure.
  - Pin `.upToNextMinor(from: "0.9.0")` if you would rather not take breaking
    changes automatically. `v1.0.0` is where the freeze actually begins.

### Deprecated

- The RGB initializer of `Color` now spells its alpha argument `alpha:`, so all three initializers agree ([#566](https://github.com/shinyaoguri/metaphor/issues/566)):

  | Deprecated | Use instead |
  |---|---|
  | `Color(r:g:b:a:)` | `Color(r:g:b:alpha:)` |

  `Color(gray:alpha:)` and `Color(hue:saturation:brightness:alpha:)` already used `alpha:`; `Color(r:g:b:a:)` was the odd one out, and writing `Color(r:g:b:alpha:)` failed with `extra argument 'alpha' in call` — an error that never names the label you actually want.

  **Nothing breaks yet.** The old label still compiles: it forwards to the new initializer and emits a deprecation warning. Removal follows in a later release.

  One detail if you rely on defaults: the deprecated `a:` overload no longer has `a: Float = 1.0`. Without that, `Color(r: 1, g: 0, b: 0)` would match both initializers and fail as *ambiguous use of 'init'*. Three-argument calls therefore resolve to the new `alpha:` initializer and keep defaulting to fully opaque, exactly as before.

### Fixed

- `createGraphics3D()`: reading pixels back right after `endDraw()` no longer races
  the GPU. `Graphics3D.toImage()` now passes its drawing command queue to the
  returned `MImage`, so `loadPixels()` is ordered after the draw by commit order.
  Previously the readback ran on a separate shared queue and could observe the
  texture before the frame had finished — an all-black or stale image. The 2D
  `Graphics.toImage()` already did this; only the 3D path was missing it
  ([#353](https://github.com/shinyaoguri/metaphor/issues/353))
- `background()` now fills the canvas all the way to its edges on the very first
  frame. The full-screen quad it draws when the render pass clear cannot be used
  yet stopped half a pixel short of the top row and left column (the 2D
  projection maps integer coordinates to pixel centers), so with the default 4x
  MSAA those 255 pixels came out at half the background brightness. Single-frame
  captures — `noLoop()` sketches, Probe snapshots, a `save()` on frame 1 — showed
  this every time ([#373](https://github.com/shinyaoguri/metaphor/issues/373))
- Meshes drawn through the non-instanced (immediate) 3D path now receive shadows.
  `Canvas3D` bound the shadow uniforms and the shadow map for that path, but the
  built-in fragment shaders (`metaphor_canvas3DFragment` /
  `metaphor_canvas3DTexturedFragment`) never declared them, so only the instanced
  path applied shadows. A mesh that fell back to the immediate path — the
  instance buffer filling up mid-frame — stayed unshadowed while everything
  around it was correctly shaded
  ([#391](https://github.com/shinyaoguri/metaphor/issues/391))
- `previousFrame()`: reading the previous frame back on the CPU (`loadPixels()` /
  `get()`) no longer races the GPU. The returned `MImage` now carries the
  renderer's command queue as its readback queue, so the readback is ordered
  after the frame-start copy by commit order. Previously it ran on a separate
  shared queue and could observe the texture before that copy had finished.
  Drawing the image on the GPU (`image(previousFrame()!, 0, 0)`) was never
  affected ([#479](https://github.com/shinyaoguri/metaphor/issues/479))
- `curveVertex()` now passes through the points you give it. The Catmull-Rom
  expansion added a `(1 - s) * lerp(p1, p2, t)` term on top of an already
  complete spline, so with the default tightness every curve was drawn at 1.5×
  its size, offset from the origin. `curveTightness()` now changes the spline
  basis (as in Processing) instead of blending towards a straight line, and the
  curve starts and ends exactly on its control points for any tightness
  ([#503](https://github.com/shinyaoguri/metaphor/issues/503))
- `text(_:_:_:_:_:)` (the overload that wraps inside a bounding box) no longer
  draws upside down. The multi-line renderer flipped the Core Text context
  vertically before drawing, on top of the flip a `CGBitmapContext`'s byte order
  already provides, so glyphs came out mirrored and the first line landed at the
  bottom. Wrapped text now matches the single-line `text(_:_:_:)` in orientation
  and line order — no API change, only the rendered output
  ([#504](https://github.com/shinyaoguri/metaphor/issues/504))
- The Probe sequence contact sheet (`.metaphor/probe/current/sequence/contact_sheet.png`)
  no longer composes each cell upside down. Individual `frame.NNNN.png` files were
  always correct; only the montage was flipped, which also affected the
  `capture_sequence` MCP tool in `metaphor-cli`
  ([#514](https://github.com/shinyaoguri/metaphor/issues/514))
- `text()` is drawn with the current `fill()` color again. Both text paths (the
  glyph atlas and the cached-texture fallback) took their vertex color from
  `tint()`, so every string came out white — or tinted by whatever color was
  meant for `image()`. `tint()` now stays confined to image drawing
  ([#516](https://github.com/shinyaoguri/metaphor/issues/516))
- `pmouseX` / `pmouseY` now hold the position from **one** frame ago, as documented,
  instead of two. The previous position was saved at the start of a frame, so whether
  it lagged by one or two frames depended on where mouse events happened to be
  processed; it is now saved at the end of the frame, after `draw()`. Anything deriving
  motion from `mouse - pmouse` was counting two frames of movement — most visibly
  `orbitControl()`, which rotated the camera about twice as far as the drag
  ([#522](https://github.com/shinyaoguri/metaphor/issues/522))
- The grayscale forms of `specular()` and `emissive()` now follow the current
  `colorMode` range, like `fill()` and `ambientLight()` already did. They passed the
  value straight through, so `specular(200)` meant a specular color of 200.0 and the
  highlight stayed a blown-out white blob no matter how high `shininess()` went.
  **This changes how existing sketches look**: a value written for the 0–1 scale
  (`specular(0.9)`) is now 0.9/255. Call `colorMode(.rgb, 1)` first, or scale the
  value to the range (`specular(230)`). The `Color` overloads are unchanged
  ([#527](https://github.com/shinyaoguri/metaphor/issues/527))
- The published API reference now carries the theme that ships with the docs, and
  it lives at [`/reference/`](https://shinyaoguri.github.io/metaphor/reference/)
  instead of `/documentation/`. Two things were broken. The docs workflow merged
  DocC's output into the landing page's output by copying a fixed list of
  directories, so `theme-settings.json`, `metadata.json`, `images/`, `videos/`
  and `downloads/` never reached the site — the theme 404'd and the pages fell
  back to the stock palette. And `metaphor.docc/theme-settings.json` nested its
  colors under `standard` / `custom`, which DocC-Render turns into meaningless
  variables (`--color-custom-0-name`) instead of colors, so the file would not
  have applied even when served. The reference is now placed under `/reference/`
  whole rather than merged, and the theme lists its colors flat. Colors that
  DocC defines separately for light and dark (backgrounds, greys) are left to
  DocC — overriding them from this file pins a single value and disables dark
  mode. Old `/documentation/**` links redirect to the new location
  ([#529](https://github.com/shinyaoguri/metaphor/issues/529))
- `curve()` now respects `curveTightness()`. It evaluated the spline with the
  public `curvePoint(_:_:_:_:_:)`, which is fixed to the standard Catmull-Rom
  basis, so the setting reached SVG export only — the same scene drew one shape
  on screen and another in the exported `.svg`. Both paths now use the
  tightness-aware basis that `curveVertex()` already uses, so `curve()` and
  `curveVertex()` agree as well
  ([#538](https://github.com/shinyaoguri/metaphor/issues/538))
- `Graphics` (the `createGraphics()` offscreen buffer) now forwards
  `curveDetail(_:)` and `curveTightness(_:)` to its canvas. It already forwarded
  `curve()`, `curveVertex()` and `bezier()`, but not the two settings that shape
  them, so curves drawn into an offscreen buffer were stuck at the defaults
  (detail 20, tightness 0) with no way to change them — the same calls on a
  sketch worked. Both settings affect `curve()` and `curveVertex()`, and
  `curveDetail(_:)` clamps values below 1 to 1, exactly as on a sketch
  ([#540](https://github.com/shinyaoguri/metaphor/issues/540))
- `enablePerformanceHUD()` now actually shows the overlay. Its colors were
  passed as 0–1 channel values through `fill(_:_:_:_:)`, which goes through
  `colorMode` (max 255 by default), so the panel and the numbers were drawn with
  an alpha of `0.6/255` and `1/255` — invisible on any background. The HUD now
  passes `Color` values directly, so it is also unaffected by a sketch's
  `colorMode` ([#574](https://github.com/shinyaoguri/metaphor/issues/574))
- The three image-export examples under `Examples/Topics/File IO/` no longer
  claim that saving is unavailable. `SaveOneImage` printed "save() not available
  in metaphor", `SaveFrames` only counted frames instead of writing them, and
  `TileImages` printed the file name of every tile without producing a single
  file — while `save(_:)`, `beginFrameRecord(directory:pattern:)` and
  `endFrameRecord()` have been there all along. They now write real files
  (`output/line.png`, `output/frames####.png`, `output/lines-<row>-<column>.png`)
  and note where metaphor differs from the Processing originals: PNG instead of
  TIFF, a printf-style frame pattern instead of `####`, and exports taken from
  the finished frame rather than at the point of the call. The example index
  description for `SaveOneImage` no longer promises a `line.tif` that was never
  written ([#576](https://github.com/shinyaoguri/metaphor/issues/576))
- `TableRow.getInt()` no longer terminates the process on numeric cells it cannot
  represent. It ran `Int(Double(cell) ?? 0)`, so a CSV containing `nan`, `inf`,
  `1e999` or a value beyond the `Int` range trapped with "Double value cannot be
  converted to Int because it is either infinite or NaN" — reading external data
  was enough to kill a sketch, while ordinary non-numeric text quietly returned 0.
  Such cells now return 0 (with a debug warning), and `getFloat()` / `getDouble()`
  reject non-finite values the same way so that "0 when not a number" means the
  same thing in all three getters. Truncation of fractional values is unchanged
  ([#580](https://github.com/shinyaoguri/metaphor/issues/580))
- `Physics2D.step(_:iterations:)` no longer crashes on a negative `iterations`.
  The count was unvalidated and reached `for iteration in 0..<iterations`, which
  trapped with "Range requires lowerBound <= upperBound" — and it did so only
  after gravity and integration had already run, leaving the world half-advanced.
  Negative values now skip the whole step at the entry point, matching the
  existing `dt` guard. `iterations: 0` keeps its meaning: integrate, but solve no
  constraints, collisions or bounds. Driving `iterations` from `@Param`, OSC or
  MIDI can no longer kill a running sketch
  ([#581](https://github.com/shinyaoguri/metaphor/issues/581))
- `ImageFilter.applyToPixels()` now validates its buffer instead of reading out of
  bounds. The public entry point accepted any `pixels` array with any `width` /
  `height`: a length that was not a multiple of 4 ran the per-pixel filters off
  the end at `pixels[i + 1]`, a length that disagreed with the dimensions did the
  same through `(y * width + x) * 4` in the spatial filters, and a negative
  dimension trapped on a reversed range. Feeding it an external RGBA buffer could
  therefore terminate the process. It now requires `pixels.count == width *
  height * 4` with non-negative, non-overflowing dimensions, and otherwise warns
  and does nothing. The documented contract states this, and the
  `ImageFilter.apply(_:to:)` path through `MImage` is unaffected
  ([#582](https://github.com/shinyaoguri/metaphor/issues/582))
- `MIDIManager.sendNoteOn()` / `sendNoteOff()` / `sendControlChange()` no longer
  put out-of-range data bytes on the wire. The parameters are documented as
  0-127 but typed `UInt8`, and only the channel was masked, so a note, velocity,
  CC number or CC value computed above 127 was written straight into the MIDI 1.0
  UMP word as a malformed message — receivers were free to ignore, fold or
  misread it. Data bytes above 127 are now sent as 127 (with a debug warning)
  rather than wrapped, so an overshooting parameter saturates at the top of the
  range instead of folding back to the bottom: masking would have turned a
  velocity of 128 into 0, which reads as a Note Off, and the highest note into
  the lowest one. `MIDIMessage`'s initializer clamps its data bytes the same way,
  so `pitchBendValue` and `normalizedControlValue` are never computed from a
  value MIDI cannot express. Channel wrapping is unchanged
  ([#583](https://github.com/shinyaoguri/metaphor/issues/583))
- The README files no longer under-report the tutorial: `docs/README.md`,
  `docs/README.en.md` and `Examples/README.md` still announced Parts 1–5 (Parts
  1–4 in English) as the published range after all ten parts had shipped, so
  Parts 6–9 — GPU, media, OSC/MIDI/Parameter Store, and shipping a piece — were
  unreachable from the entry points. The published range is now generated from
  the `draft` flag in each part's frontmatter
  (`make tutorial-status`, verified in CI), so the entry points cannot drift
  apart again ([#584](https://github.com/shinyaoguri/metaphor/issues/584))
- Tutorial 2.7 "Text" now shows a screenshot taken after the `text(_:_:_:_:_:)`
  fix in [#504](https://github.com/shinyaoguri/metaphor/issues/504) — the old one
  had the wrapped paragraph rendered upside down — and the prose no longer claims
  the section's sketch leaves text wrapping out, which it never did
  ([#601](https://github.com/shinyaoguri/metaphor/issues/601))
- `loadModel(_:normalize:)` now documents what normalizing actually does: the
  model is centred on the origin and its **longest edge becomes 2 units**
  (`[-1, 1]`). On a pixel-sized canvas a normalized model is therefore only a
  couple of pixels across, so you have to give it a size with `scale(_:)` — or
  pass `normalize: false` to keep the model's own coordinates. This is why
  `Examples/Basics/Shape/LoadDisplayOBJ` rendered a fully black frame: the
  rocket loaded fine (its longest edge is 396 units), was scaled down to 2, and
  the fallback `box()` never ran because `loadModel()` had not failed. The
  example now scales the mesh, and a test pins the normalization contract
  ([#604](https://github.com/shinyaoguri/metaphor/issues/604))
- `Examples/Topics/Image Processing/EdgeDetection` now runs the Laplacian over
  the original `moon.jpg` photo instead of a procedurally generated gradient.
  The generated image had no sharp luminance changes at all, so the convolution
  output stayed pinned near its 128 offset — a flat grey rectangle that showed
  nothing of what the example is about. The photo was already committed under
  `data/` but no code read it
  ([#605](https://github.com/shinyaoguri/metaphor/issues/605))
- `Examples/Topics/Image Processing/Explode` and
  `Examples/Demos/Performance/StaticParticlesImmediate` now draw 3D primitives
  (`box()` / `sphere()`) instead of `rect()` / `ellipse()`. Both positioned their
  elements with the three-argument `translate(x, y, z)`, which only applies to 3D
  drawing (ADR-0005), so every element collapsed onto a single point.
  `StaticParticlesImmediate` also brackets its camera transform with
  `pushMatrix()` / `popMatrix()` so the fps overlay stays in the corner
  ([#612](https://github.com/shinyaoguri/metaphor/issues/612))
- The `ToonShading` example no longer renders a completely black screen. It drew
  an oversized black sphere in front of the lit one to fake an outline, which the
  depth test dutifully let hide everything behind it. The outline sphere is gone
  and the sketch now does real toon shading on the GPU: a Metal fragment function
  loaded with `createMaterialFromFile(path:fragmentFunction:)` and applied with
  `material(_:)`, ported from the bundled `data/ToonFrag.glsl`. It is the first
  example of a custom 3D surface shader
  ([#613](https://github.com/shinyaoguri/metaphor/issues/613))
- `Examples/Topics/Advanced Data/HashMapClass` now counts words in the bundled
  `dracula.txt` / `frankenstein.txt` instead of two hand-written 90-word
  strings. Only one word in those strings met the example's "appears in a single
  book more than five times" test, and it was drawn 3.1px tall in black on grey,
  so the sketch looked like an empty grey screen
  ([#614](https://github.com/shinyaoguri/metaphor/issues/614))
- `Examples/Topics/File IO/SaveFile2` now paints the grey background and black
  stroke the original Processing sketch gets by default. It never calls
  `background()` in `draw()`, so on metaphor's black initial clear colour the
  recorded points were drawn black on black and nothing was visible
  ([#615](https://github.com/shinyaoguri/metaphor/issues/615))
- `Examples/ML/FaceDetection` and `Examples/ML/PersonSegmentation` now show their
  "Camera not available" fallback when there is no usable camera. They guarded
  with `guard let cam = capture`, but `createCapture()` returns a non-optional
  `CaptureDevice`, so the branch was unreachable and the sketch drew a black
  frame with no explanation. Both check `cam.isAvailable` now
  ([#616](https://github.com/shinyaoguri/metaphor/issues/616))
- Secondary windows created with `createWindow()` now stay off-screen in
  headless runs. `METAPHOR_VIEWER=1` (the mode `metaphor watch` / `make
  example-shots` use) suppressed only the primary window, so every sketch with a
  secondary window still popped one up on screen. Headless secondary windows now
  skip the `NSWindow` / `MTKView` entirely and are driven by the same timer loop
  as the primary — offscreen rendering and Syphon output are unaffected
  ([#617](https://github.com/shinyaoguri/metaphor/issues/617))
- `Examples/Demos/Performance/StaticParticlesRetained` is a real sketch again. It
  was a stub whose header claimed the retained-shape API (`createShape()` /
  `addChild()`) did not exist in metaphor; both have shipped for a while. The
  example now builds all 5,000 particle quads into a single `.path3D` shape in
  `setup()` and draws them with one `shape()` call per frame, matching the
  particle count and fps overlay of its immediate-mode counterpart
  `StaticParticlesImmediate` so the two can be compared
  ([#618](https://github.com/shinyaoguri/metaphor/issues/618))
- `Examples/Topics/Image Processing/Blur` and `Convolution` now convolve the
  bundled `moon.jpg` / `moon-wide.jpg` photos instead of a generated gradient.
  Both photos were already committed under `data/` but neither package declared
  them as resources, so no code could read them and the kernels ran over a
  smooth ramp where their differences barely show
  ([#620](https://github.com/shinyaoguri/metaphor/issues/620))
- `Examples/Topics/Shaders/EdgeDetect` now runs its Laplacian over the bundled
  `leaves.jpg` photo instead of a procedurally generated pattern. The generated
  pattern had a period of roughly 335px against a 640px canvas, so a 3x3
  Laplacian returned almost zero everywhere and the sketch rendered as flat grey
  — mathematically correct, but showing nothing of what edge detection is. The
  photo was already committed under `data/` and no code read it
  ([#622](https://github.com/shinyaoguri/metaphor/issues/622))
- `Examples/Demos/Graphics/Yellowtail` no longer traps on the very first drag.
  `Gesture.smooth()` walked `1..<(nPoints - 2)`, which is an invalid range while
  a gesture still has two points — Processing's C-style `for` simply runs zero
  times there, Swift's `..<` traps
  ([#626](https://github.com/shinyaoguri/metaphor/issues/626))
- `reloadShader(key:source:)` / `reloadShaderFromFile(key:path:)` no longer
  destroy the working shader when the new source fails to compile
  ([#648](https://github.com/shinyaoguri/metaphor/issues/648)). They used to
  drop the registered library *before* compiling, so a single typo left the key
  with no library at all: every later `function(named:from:)` returned nil and
  the sketch drew nothing until it was restarted. The new source is compiled
  first and swapped in only on success.
- The `Planets`, `Trefoil` and `Wiggling` examples are real sketches again. They
  were stubs carrying a stale note claiming the retained shape API
  (`createShape`, `setTexture`, `setVertex`) was missing from metaphor — all of
  it has been implemented for a while. `Planets` also declares its bundled
  images as target resources, so they actually load at runtime
  ([#679](https://github.com/shinyaoguri/metaphor/issues/679))
- `Examples/Demos/Performance/StaticParticlesImmediate` and
  `StaticParticlesRetained` are back to the 50,000 particles of the Processing
  sketch they are ported from. At the 5,000 they had been reduced to, both sides
  reached the 60 fps target on Apple Silicon, so the pair — the only place in the
  examples where immediate and retained drawing can be compared — printed `60`
  and `60` and showed no difference at all. At 50,000 the immediate side drops to
  about 32 fps while the retained side stays at 60
  ([#680](https://github.com/shinyaoguri/metaphor/issues/680))
- Camera and microphone capture no longer fail silently while their permission is
  still `notDetermined`. macOS only shows the TCC dialog to a **bundled app** that
  declares `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`, so a plain
  executable built by `swift run` is never asked and simply receives nothing —
  while `CaptureDevice.isAvailable` reported `true`. Now:
  - `CaptureDevice.authorizationStatus` / `.isAuthorized` and
    `AudioAnalyzer.authorizationStatus` / `.isAuthorized` expose the permission
    state, so sketches, HUDs and the Probe can read it
  - if the status is still `notDetermined` and nothing has arrived 3 seconds after
    `start()`, a warning is printed to stderr (**in release builds too**, since
    that is exactly the case where the app bundle matters) telling you to wrap the
    sketch in a `.app` or grant access in System Settings
  - `isAvailable` documents that it means "the session was configured", not "frames
    are arriving" ([#685](https://github.com/shinyaoguri/metaphor/issues/685))
- Sketches now shut down gracefully on `SIGTERM` / `SIGINT` instead of being killed
  outright, so the Syphon server is stopped and its retire notification is sent. Without
  a handler the default signal disposition skipped `renderer.shutdown()` entirely, leaving
  a dead server in `SyphonServerDirectory` for clients that keep the directory alive
  (the live viewer, MadMapper, VDMX) — and `metaphor watch` grew one more zombie on every
  reload, since it stops the child sketch with `SIGTERM`. Set
  `METAPHOR_SIGNAL_HANDLERS=0` to opt out and handle the signals yourself
  ([#715](https://github.com/shinyaoguri/metaphor/issues/715))
- Fragment-only custom materials (`createMaterial(source:fragmentFunction:)` without a
  `vertexFunction`) applied to built-in shapes rendered nothing: the instance batch
  combined the non-instanced built-in vertex shader with instanced buffers, so vertices
  read a mismatched uniform layout and flew off-screen. Draws now fall back to the
  immediate path while a custom material is active — same as materials with a custom
  vertex function — so the shape actually appears. Instancing is bypassed for custom
  materials ([#717](https://github.com/shinyaoguri/metaphor/issues/717))
- Retained 3D custom shapes (`createShape()` + `beginShape()` with `vertex(x, y, z)`) now stroke
  their outline instead of a wireframe, and the stroke-only modes finally draw:
    - `.polygon`: the stroke follows the shape's outline (closed by `endShape(.close)`). It used to
      be the fill mesh drawn as a wireframe, so the triangle fan's interior edges showed up as
      diagonals across the face — there was no way to just outline a face
    - `.lines` / `.points`: previously nothing was drawn at all; the fill mesh came out empty and the
      shape silently disappeared. They are drawn with the stroke color now, and drawing one with
      `noStroke()` warns once instead of vanishing
    - `.triangles` / `.triangleStrip` / `.triangleFan` keep the wireframe stroke, which is where the
      triangle edges are the outline

  3D stroke width is still fixed at one pixel — `strokeWeight()` does not affect it
  ([#735](https://github.com/shinyaoguri/metaphor/issues/735))
- `beginContour()` / `endContour()` on a 3D shape now warn once instead of doing
  nothing silently. Contours are read only by the 2D tessellator, so a 3D shape
  built with `vertex(x, y, z)` — retained (`MShape`) or immediate
  (`beginShape3D()`) — came out as a shape with no hole at all, and nothing said
  why. Both paths now leave the 2D contour state untouched and print the reason
  on the first call. The doc summaries (and therefore `llms.txt`) say "2D shapes
  only" as well, so it is visible from the API list
  ([#736](https://github.com/shinyaoguri/metaphor/issues/736))
- Retained 3D shapes (`createShape()` + `beginShape()` + `vertex(x, y, z)`) now
  compute face normals automatically when you never call `normal()`. Every
  vertex used to keep the default `(0, 1, 0)`, so a shape lit from the side sank
  to solid black — while the *same* code drawn in immediate mode came out shaded,
  because `Canvas3D.endShape()` has always computed face normals. Nothing to
  change in your sketch; shapes that were black now pick up shading, and shapes
  that call `normal()` keep exactly the normals they set. Note that
  `MShape.normal()` still applies to **the next vertex only** (immediate mode's
  `normal()` persists until `endShape()`); that asymmetry is tracked separately
  in [#876](https://github.com/shinyaoguri/metaphor/issues/876)
  ([#738](https://github.com/shinyaoguri/metaphor/issues/738))
- `text(str, x, y)` now honours newlines: `"AA\nBB"` is drawn as two lines instead
  of being flattened into `"AABB"`. Lines are spaced by `textLeading()`, each line
  is aligned horizontally on its own width, and the vertical alignment treats all
  lines as one block (`.baseline` still puts the first line's baseline on `y`).
  `textWidth()` follows suit and returns the widest line
  ([#744](https://github.com/shinyaoguri/metaphor/issues/744))
- A `Graphics` / `Graphics3D` buffer can now be redrawn and pasted several times
  within one frame — each `image(pg, …)` draws what the buffer held at that call,
  the way Processing behaves. Previously `toImage()` only referenced the buffer's
  color texture, and because the main 2D batch runs at the end of the frame while
  the offscreen passes commit as they are drawn, every paste ended up showing the
  *last* content. Position and size were right and only the picture was wrong, so
  it could not be noticed without looking at the result. The buffer now freezes
  the texture it hands out and rotates its draw target on the next `beginDraw()`
  (copy-on-write); the usual `background()` path copies nothing, and only a pass
  that keeps the previous content blits it across. Reusing one buffer many times
  in a frame therefore costs one texture per redraw
  ([#745](https://github.com/shinyaoguri/metaphor/issues/745))
- `textToContours()` / `textToPoints()` / `textToShape()` now break a string on
  newlines the way `text()` does. They went through a single-line Core Text
  path, so `"AA\nBB"` came back as one concatenated `"AABB"` outline — the same
  string drew as two rows but sampled as one. Rows are now laid out with
  `textLeading()`, aligned horizontally on each row's own width and vertically
  as one block, exactly like `text(str, x, y)`
  ([#748](https://github.com/shinyaoguri/metaphor/issues/748))
- `PhysicsBody2D.restitution` and `.friction` now actually affect the
  simulation. Collision resolution corrected a body's `position` before reading
  its velocity, and since Verlet derives velocity from `position -
  previousPosition`, the correction cancelled the approach speed — the impulse
  step bailed out every time, so neither coefficient ever reached the result.
  Overlap correction now moves `previousPosition` by the same amount, leaving
  velocity untouched, so bodies bounce (a ball dropped onto a `restitution =
  0.9` floor returns to 80% of its drop height instead of 5%) and sliding
  bodies are slowed by friction. Contacts slower than the approach speed
  gravity adds in one step are treated as inelastic, so resting bodies settle
  instead of jittering. World `bounds` are unchanged: they clamp positions and
  ignore both coefficients — put a static body where a bouncy wall is wanted
  ([#755](https://github.com/shinyaoguri/metaphor/issues/755))
- `Physics2D` driven as an automatic subsystem (the `import metaphor` bridge) no longer
  depends on frame-time jitter. It used to hand the real frame delta straight to
  `step(dt)`, but Verlet integration carries velocity as displacement *per step*, so a
  varying `dt` adds and removes energy — the same 10-second free fall came out 25%
  further when the frame time alternated around the same average, which meant a sketch
  moved differently on every run and on every machine. The bridge now calls the new
  `Physics2D.advance(_:iterations:)`, which buffers the elapsed time and spends it in
  fixed-size steps. **Sketches using the automatic bridge will move slightly differently
  than before** — that is the fix; the old motion was not reproducible in the first
  place. Two new knobs: `fixedTimeStep` (default `1.0 / 120.0`, two sub-steps per frame
  at 60 fps) and `maxSubSteps` (default `8`, i.e. `1/15` s of simulation per call; time
  beyond the budget is dropped so a slow machine runs in slow motion rather than
  spiralling). `step(_:iterations:)` is unchanged and stays as the low-level entry point
  for callers that own the schedule — its doc now says to pass a fixed `dt`
  ([#756](https://github.com/shinyaoguri/metaphor/issues/756))
- `saveFrame(_:)` / `save(_:)` called several times in the same frame now write
  every file instead of silently keeping only the last one. The pending
  destinations are queued, and the frame is read back once and written to all of
  them — so the images are identical (each call captures the frame's final
  output, not the drawing state at the moment of the call)
  ([#762](https://github.com/shinyaoguri/metaphor/issues/762))
- Self-intersecting polygons now fill the way Processing and p5.js fill them. A pentagram
  written as five `vertex()` calls came out as a blob, because ear clipping — which only
  handles simple polygons — ran out of ears and fell back to a triangle fan. `beginShape()`
  (with and without per-vertex colors) and `polygon()` now split the outline at its
  self-intersections, cut the plane into faces, and fill only the faces whose winding number
  is non-zero. Simple polygons take the same path as before and are unchanged; `beginContour()`
  holes are unaffected ([#768](https://github.com/shinyaoguri/metaphor/issues/768))
- `strokeJoin(.round)` now actually rounds the corner. The join fan swept the
  *long* way around between the two outward offset directions, so it filled the
  inside of the corner — already covered by the two segment quads — and left the
  outside empty, showing up as a V-shaped notch that looked worse than `.bevel`.
  Every 2D polyline corner was affected (`beginShape()` / `endShape()` shapes,
  `MShape` outlines, closed shapes); `.miter` and `.bevel` render exactly as
  before ([#769](https://github.com/shinyaoguri/metaphor/issues/769))
- The default `lights()` rig now shines **from above** instead of from below
  ([#774](https://github.com/shinyaoguri/metaphor/issues/774)). Its single
  directional light pointed at `(-0.5, -1.0, -0.8)`, and since world +Y runs
  down the screen — and the shader lights a surface from `normalize(-direction)`
  — that is a light coming from directly *below*: upward-facing surfaces went
  dark while downward-facing ones lit up, the opposite of what
  `directionalLight(0, 1, 0)` ("light from straight above") documents. The
  direction is now `(-0.5, 1.0, -0.8)`.

  No public API changed, but anything drawn with a bare `lights()` is shaded
  differently, and `enableShadows()` casts its shadows in the new direction too.
  To keep the old look, place the light yourself:
  `directionalLight(-0.5, -1, -0.8, intensity: 0.7)` after `lights()`.
- `AudioAnalyzer.bandEnergy(lowFreq:highFreq:)` が、サンプルレート不明のまま黙って `0` を返さなくなりました。`injectSamples(_:)` で自前の波形を解析する経路では `sampleRate` が必須ですが、渡し忘れても `spectrum` / `volume` / `band(_:)` は動き続けるため、症状が「その帯域が無音」と見分けられませんでした。DEBUG ビルドで一度だけ警告を出します（戻り値は従来どおり `0`）。
- Resuming with `loop()` after `noLoop()` no longer hands the whole paused
  duration to the next frame as its `deltaTime`. The clock behind `time` runs on
  real time and keeps advancing while the loop is stopped, but frames only fire
  when the loop runs, so the first frame after a 0.8 s pause reported a
  `deltaTime` of 0.89 s — 54 times a 60fps step, enough to blow up anything
  integrating over it (`Physics2D`, `TweenManager`, hand-written velocity
  integration). `loop()` now moves the frame-time origin to the current clock
  before frames restart, so that first frame is one step again; `time` still
  catches up to real time as before. `redraw()` is unchanged — it draws a single
  frame on demand and keeps reporting the real elapsed time
  ([#793](https://github.com/shinyaoguri/metaphor/issues/793))
- `createGraphics(_:_:)` and `createGraphics3D(_:_:)` no longer abort the process
  when given a zero or negative size. Both return `Graphics?` / `Graphics3D?`, so
  the type already declares that they can fail — but a degenerate size reached
  `MTLTextureDescriptor`, whose validation ends the process with an assertion
  (`MTLTextureDescriptor has width of zero` → `Abort trap: 6`) instead of letting
  `makeTexture` return `nil`. A `guard let` at the call site could not catch it.
  They now return `nil` and log the reason in DEBUG builds, matching
  `createImage(_:_:)`. The guard also went into `TextureManager.init` — the one
  gate `Graphics`, `Graphics3D` and the main canvas all pass through — so
  `resizeCanvas(width:height:)` degrades to a no-op instead of aborting, and into
  the `MImage.createImage(_:_:device:)` static overload, which builds its
  descriptor without going through `TextureManager`
  ([#798](https://github.com/shinyaoguri/metaphor/issues/798))
- `Color(hex: String)` now validates the spelling instead of handing it straight
  to `UInt32(_:radix:)`. Any hex string of 1–8 digits used to be accepted, so a
  wrong digit count silently produced a *different colour* rather than the `nil`
  the failable initializer promises — most visibly `Color(hex: "#FFF")`, which
  came back blue `(0.00, 0.06, 1.00)` instead of white. Accepted spellings are
  now **3, 6 or 8 digits only**, and every character has to be an ASCII hex digit
  (`"+FFFFF"` parsed fine before — `UInt32(_:radix:)` accepts a leading sign —
  and full-width `"ＦＦＦＦＦＦ"` passes `isHexDigit`, so both are checked).
  - `"#FFF"` and other 3-digit strings are expanded CSS-style (`"#0AF"` →
    `"#00AAFF"`), so `#FFF` is white.
  - **4-digit shorthand stays unsupported** and returns `nil`: this library's
    8-digit form is AARRGGBB, the reverse of CSS's RRGGBBAA, so `#RGBA` could be
    read either way and whichever we picked, the other spelling would quietly
    yield a different colour — the very failure being fixed here.
  - Strings that used to yield a colour by accident (`"#F"`, `"#12345"`,
    `"#1234567"`, …) now return `nil`; check the optional, or spell the colour
    with 3, 6 or 8 digits
    ([#799](https://github.com/shinyaoguri/metaphor/issues/799))
- `blendMode(.subtract)` no longer punches a hole in the canvas: the mode used to
  subtract the alpha channel as well (`result.a = dst.a - src.a`), so painting an
  opaque color over an opaque background left that area fully transparent. Only
  the color channels are subtracted now, and the destination alpha is kept. The
  difference shows up when the result leaves the offscreen texture — exported
  PNGs and Syphon/NDI output no longer show those areas as transparent
  ([#800](https://github.com/shinyaoguri/metaphor/issues/800))
- `blendMode()` now honours the `fill` / `stroke` alpha in **every** mode. `.multiply`,
  `.screen`, `.lightest` and `.darkest` used to ignore it entirely — painting with a fully
  transparent color still changed the backdrop — and `.subtract` applied it before clamping.
  Alpha is now uniformly "how much of the blend to apply":
  `result = mix(dst, blend(src, dst), src.a)`, matching what `.difference` / `.exclusion`
  already did ([#801](https://github.com/shinyaoguri/metaphor/issues/801))
- Blending no longer punches holes in the canvas: `.multiply` and `.darkest` used to leave
  `result.a = 0` where a transparent color was painted, which showed up as transparent
  pixels in exported PNGs and Syphon output. Every mode now composites alpha as
  `src.a + dst.a * (1 - src.a)`. This also supersedes the narrower `.subtract` rule added in
  [#800](https://github.com/shinyaoguri/metaphor/issues/800) — its result alpha is now the
  same `over` as the other modes
- `textWidth()` now returns the sum of per-character advances — the same ruler
  `text()` uses to place glyphs — instead of the optical bounds rounded up on
  every call. Widths are additive again (`textWidth("ab")` equals
  `textWidth("a") + textWidth("b")`), a trailing space counts just like a
  leading one, and single characters no longer come back up to a pixel too wide.
  `textAlign(.center)` / `textAlign(.right)` align on that same width, dropping
  the 2px of atlas padding that used to leak into it, so measured text and
  aligned text finally agree. `text()` also stops drawing one pixel to the
  right of the requested position: the 1px padding around each glyph bitmap was
  never subtracted back out
  ([#802](https://github.com/shinyaoguri/metaphor/issues/802),
  [#803](https://github.com/shinyaoguri/metaphor/issues/803)).
  Text laid out with `textWidth()` shifts by a pixel or two; kerning is not
  applied, matching Processing.
- The remaining APIs that took a size and aborted the process on a degenerate or
  oversized one now fail the way their signature promises. Each of these built an
  `MTLTextureDescriptor` (or a Swift array) from an unchecked width and height, and
  a bad size ended the process with an assertion instead of being returned — so
  `try` and `guard let` at the call site could not catch it:
  - `createRayTracer(width:height:)` throws
    `MetaphorError.textureCreationFailed` instead of aborting. The guard is in
    `MPSRayTracer.init`, so building one directly is covered too.
  - `noiseTexture(_:width:height:config:)` and the `GKNoiseWrapper` methods it is
    built on — `sampleGrid(width:height:)`, `texture(width:height:)`,
    `image(width:height:)` and
    `colorMappedTexture(width:height:colorStops:)` — return `nil` (or an empty
    array for `sampleGrid`) rather than trapping. `sampleGrid` was the odd one
    out: a negative size trapped in pure Swift, without Metal being involved at
    all.
  - `ciGenerate(_:width:height:)` returns `nil`. The guard is in
    `CIFilterWrapper`'s shared texture pool, so `ciFilter` is covered by the same
    check.
  - `MImage.createImage(_:_:device:)` now also rejects sizes above
    `TextureManager.maxDimension`. [#798](https://github.com/shinyaoguri/metaphor/issues/798)
    closed its lower bound and [#842](https://github.com/shinyaoguri/metaphor/issues/842)
    closed the upper bound everywhere that passes through `TextureManager` — this
    overload builds its own descriptor and was outside both.
  - `ParticleSystem.init` rejects a non-positive `count` explicitly. It already
    surfaced as a thrown `MetaphorError.particle(.bufferCreationFailed)`, but only
    because `makeBuffer(length:)` happened to return `nil`; the contract is now
    the guard rather than Metal's behaviour.
  ([#806](https://github.com/shinyaoguri/metaphor/issues/806))
- `loop()`, `noLoop()`, `redraw()` and `frameRate()` now work inside
  `SketchView` (the SwiftUI embedding path). Its coordinator only wired the
  render callbacks, so `noLoop()` merely flipped `isLooping` to `false` while
  the view kept drawing, and `redraw()` / `frameRate()` did nothing at all.
  The frame clock is now shared with `SketchRunner` as well, so the first
  `deltaTime` after `loop()` no longer carries the wall-clock time spent paused
  ([#808](https://github.com/shinyaoguri/metaphor/issues/808))
- `textToContours()` / `textToPoints()` / `textToShape()` now advance one character
  at a time, exactly as `text()` draws and `textWidth()` measures. The outlines used
  to come from a single `CTLine` over the whole string, which applied kerning, so the
  contours drifted left of the drawn glyphs on kerning pairs — 4.7px on `"AV"` at
  Helvetica 64pt, and further with every pair in a longer string. If you were placing
  particles or shapes on `textToPoints()` output over text drawn with `text()`, they
  now line up. In exchange the outlines no longer get multi-character shaping:
  **ligatures, Arabic joining forms and Indic reordering are not applied** (kerning
  is not either, which is the point). This matches `text()`, keeps `textWidth()`
  additive (`textWidth("ab") == textWidth("a") + textWidth("b")`, #802), and matches
  Processing, which does not kern. Fallback fonts for characters missing from the
  requested family still resolve as before
  ([#821](https://github.com/shinyaoguri/metaphor/issues/821))
- `beginShape3D` shapes no longer apply `fill` twice. The fill color was baked
  into the vertex colors *and* sent again as the shader tint, so a shape drawn
  with `fill(180, 120, 60)` came out as `fill²` — darker than the same shape
  built from `plane()` or any other built-in primitive. Shapes now match the
  primitives, and the color no longer depends on whether a texture is bound or
  shadows are enabled. Two related symptoms are fixed with it: a color passed to
  `vertex(x, y, z, color)` now shows up exactly as given instead of being
  multiplied by the current fill, and `beginShape3D(.points)` now draws each
  point in its own color instead of tinting every point with the first vertex's
  color. Sketches that compensated by lightening their `fill` (or by setting
  `fill(255)` before per-vertex colors) will now render brighter and should drop
  the workaround ([#825](https://github.com/shinyaoguri/metaphor/issues/825))
- `material(_:)` now applies to shapes built with `beginShape3D()` / `vertex()` /
  `endShape3D()`, not just to meshes and built-in primitives. The immediate
  drawing path bound the built-in pipeline unconditionally and never looked at
  the active custom material, so a sketch that shaded a `box()` with a custom
  fragment shader got default shading on a hand-built plate right next to it.
  Worse, the two rendering modes disagreed: the recording path taken when
  shadows are on (or `METAPHOR_COMMAND_RECORD=1`) already routed shapes through
  the mesh path, so *the same sketch changed appearance depending on whether
  `shadows()` was called*. All three shape paths — plain, textured, and
  `beginShape3D(.points)` — now go through the same mesh path as the recording
  mode, so custom pipelines and custom material parameters are picked up once,
  in one place. Sketches that relied on shapes ignoring the current custom
  material must now call `noMaterial()` before drawing them
  ([#826](https://github.com/shinyaoguri/metaphor/issues/826))
- `createCanvas(width:height:)` now works inside `SketchView` (the SwiftUI
  embedding path). Its coordinator never wired `onCreateCanvas`, so the call was
  a complete no-op — neither the offscreen textures nor `width` / `height`
  changed. This path only rebuilds the rendering resolution: the view's size is
  decided by SwiftUI layout, and the blit to screen keeps preserving the aspect
  ratio (letterbox / pillarbox). As part of the fix, the setup closure now runs
  before the first frame instead of inside it, matching `SketchRunner` — calling
  `createCanvas()` mid-frame would have stalled for five seconds on the
  in-flight frame semaphore. A `noLoop()` in setup still lets the first frame
  render before pausing
  ([#828](https://github.com/shinyaoguri/metaphor/issues/828))
- `background(r, g, b, a)` now takes effect in the frame it is called, whatever the alpha.
  When the color differs from the previous frame's, the background cannot ride on the render
  pass clear and is painted as a full-screen quad instead — and that quad went through normal
  alpha blending, where `a = 0` is a no-op by definition. So an offscreen buffer could not be
  emptied with `background(0, 0, 0, 0)`: the same line only worked from the second frame on,
  silently breaking anything that bakes a single frame (static layers, thumbnails, tests)
  ([#829](https://github.com/shinyaoguri/metaphor/issues/829))
- `MergePass(.alpha)` no longer darkens the layer it composites. Its inputs are render
  targets, whose RGB is already premultiplied by alpha (ADR-0012), but the shader multiplied
  by alpha a second time — so a layer drawn with `fill(51, 204, 102, 128)` over a
  `(153, 51, 26)` backdrop came out `(89, 77, 39)` instead of `(102, 128, 64)`. `B over A` is
  now `B.rgb + A.rgb * (1 - B.a)`, and `MergePass.BlendType` documents that both inputs and
  the output are premultiplied ([#831](https://github.com/shinyaoguri/metaphor/issues/831))
- Closing a secondary window created with `createWindow(_:)` and then opening
  another one no longer crashes with `SIGSEGV`. Both the primary and the
  secondary `NSWindow` were left at AppKit's default
  `isReleasedWhenClosed = true`, so closing one released a window that metaphor
  still held a strong reference to
  ([#835](https://github.com/shinyaoguri/metaphor/issues/835))
- `ctx.time` inside a secondary window's draw closure now counts from when the
  sketch started, matching its documentation. Each `SketchWindow` builds its own
  renderer, whose clock started when the window was created, so a window opened
  later reported a time near zero while the primary sketch was already minutes
  in — animations driven by `ctx.time` jumped when a window was reopened. The
  first frame's `deltaTime` stays one frame long
  ([#836](https://github.com/shinyaoguri/metaphor/issues/836))
- Secondary windows no longer drift off-screen when they are closed and
  reopened. The cascade offset came from a counter that only ever incremented,
  so every `createWindow(_:)` after a close started 30pt further down and to the
  right. The slot is now taken from the windows that are actually open, and a
  closed window frees its slot for the next one
  ([#837](https://github.com/shinyaoguri/metaphor/issues/837))
- A tween's registration in `TweenManager` now follows its state machine instead
  of only ever ending at "completed". Three symptoms went away with it:
  - **`start()` works again after a tween finishes.** Completing removed the
    tween from the manager and nothing put it back, so replaying an animation
    left it frozen. A tween now remembers the manager it was added to (weakly —
    the manager holds the tween, not the other way round) and re-registers
    itself on `start()`.
  - **Tweens that are never started no longer pile up.** Only `isComplete` ones
    were evicted, so anything left `.idle` — a `tween(...)` whose `start()` never
    came, or one put back with `reset()` — stayed registered forever, updated
    every frame to no effect and kept alive by the manager's closures. `.idle`
    tweens are now evicted on the next update and come back if `start()` is
    called.
  - **Adding the same tween twice no longer doubles its speed.** `add(_:)`
    appended unconditionally, so a tween registered twice got two `update` calls
    per frame. Duplicates are now ignored.

  `tween(...)` still creates *and* registers, exactly as before
  ([#838](https://github.com/shinyaoguri/metaphor/issues/838))
- `Tween` no longer breaks permanently when given a malformed `deltaTime`.
  `TweenManager.update(_:)` is public and takes whatever the caller computed, and
  a single `NaN` used to be unrecoverable: it poisoned `elapsed`, and because
  both `while elapsed >= duration` and `min(elapsed / duration, 1.0)` pass `NaN`
  straight through, the tween's value stayed `NaN`, `isComplete` was never true
  again, and it was never removed from the manager. A negative delta drove
  `elapsed` below zero and extrapolated past `from`. `update(_:)` now ignores
  non-finite and negative steps and resumes on the next sane frame. The same fix
  covers a hang: an infinitely repeating tween (`repeatCount(0)`) given a huge
  but finite step never left the cycle-consuming `while` loop, because `Float`
  subtraction saturates (`1e9 - 0.5 == 1e9`, since `ulp(1e9)` is 64). That loop
  now detects saturation and treats the remaining cycles as elapsed
  ([#839](https://github.com/shinyaoguri/metaphor/issues/839))
- A degenerate `SketchWindowConfig` no longer aborts the process. `createWindow`
  documents that it returns `nil` on failure, but two cases got past every guard
  and hit a Metal descriptor assertion instead:
  - Dimensions above the 16384 texture limit are now rejected by
    `TextureManager` (the single chokepoint that `createGraphics`,
    `createGraphics3D` and the main canvas all pass through), so they return
    `nil` rather than aborting. The limit is exposed as
    `TextureManager.maxDimension`.
  - `windowScale` must be greater than 0. Zero used to open a 0x0pt window that
    reported `isOpen == true`
  ([#842](https://github.com/shinyaoguri/metaphor/issues/842))
- The canvas-side `pixels` array is now **straight alpha**, like `fill()` and `color()`, so
  `set(x, y, get(x, y))` is the identity on translucent pixels. `loadPixels()` used to hand
  back the premultiplied bytes the canvas stores internally (a `fill(51, 204, 102, 128)` pixel
  read back as `(26, 102, 51, 128)`), while `color(r, g, b, a)` packs straight values — so the
  reading side and the writing side disagreed, and a translucent pixel written into `pixels`
  composited without its alpha and came out too bright. `loadPixels()` now un-premultiplies on
  readback and `updatePixels()` draws the buffer through a fragment that treats it as straight,
  which closes the last gap between `pixels` and `MImage` under ADR-0012
  ([#848](https://github.com/shinyaoguri/metaphor/issues/848))
- Bloom's bright-pass no longer forces alpha to `1.0`. Post-process textures are
  premultiplied alpha (ADR-0012), so the extract pass — which only attenuates RGB — must let
  alpha through; pinning it to `1.0` made fully transparent regions claim to be opaque. The
  built-in `BloomEffect` composites with the original alpha, so nothing rendered by it
  changes, but custom effects reading a bloom-extract result no longer see a bogus alpha.
  `PostEffect` now documents the contract: **input and output are both premultiplied alpha,
  and effects must not overwrite alpha with a constant**
  ([#849](https://github.com/shinyaoguri/metaphor/issues/849))
- `MShape.setTint()` now warns once instead of doing nothing silently. The color
  it records is read by no draw path at all: the 2D shape path draws no textures,
  and a textured 3D shape is tinted by its **fill color** (the instance color the
  shader multiplies the texture by), so there is no tint slot to route it to. The
  shape still drew — just never in the tint color — which made it easy to miss.
  Use `setFill()` to tint a textured 3D shape. The doc summary (and therefore
  `llms.txt`) says it has no effect, so the limitation is visible from the API
  list. Sketch-level `tint()` on `image()` is a separate path and keeps working
  ([#852](https://github.com/shinyaoguri/metaphor/issues/852))
- `fill(gray)` and `stroke(gray)` inside a retained shape definition
  (`createShape()` + `beginShape()`) now go through `colorMode()` like every other
  color call. They divided by a hard-coded `255` and pinned alpha to `1`, so the
  same `fill(128)` produced a different color inside a shape than outside it —
  worst under `colorMode(.rgb, 1.0)`, where `fill(0.5)` came out as `0.5 / 255`
  and the shape rendered essentially black. A shape now captures the color mode
  in effect when `createShape()` was called, alongside the fill, stroke and
  material it already captured. **Sketches that never change `colorMode` are
  unaffected** — the default range is still 0-255, so `fill(128)` is the same
  color it always was. If you set a non-default `colorMode` *and* passed
  pre-divided values to a shape's `fill()`/`stroke()` to work around this, drop
  the workaround and pass the value in your `colorMode` range
  ([#853](https://github.com/shinyaoguri/metaphor/issues/853))
- `createCanvas(width:height:)` called from inside `draw()` no longer stalls the
  sketch for five seconds and silently loses that frame. Resizing drains all
  in-flight frames, which can never succeed from inside a frame that is holding
  one of those slots, so the call previously timed out and then swapped the
  render target out from under the encoder that was still recording. It is now
  rejected up front with a warning and does nothing: the frame finishes on the
  canvas it started with, and `width` / `height` stay unchanged. Call it from
  `setup()` — that contract is unchanged, and calls from outside a frame still
  work exactly as before. `MetaphorRenderer.resizeCanvas(width:height:)` applies
  the same guard for callers that reach past the sketch API, and the new
  `MetaphorRenderer.isRenderingFrame` reports whether a frame is being rendered
  ([#856](https://github.com/shinyaoguri/metaphor/issues/856))
- Secondary windows created with `createWindow()` now respond to `createCanvas()`,
  `loop()`, `noLoop()`, `redraw()` and `frameRate()`. `SketchWindow` wired only its
  render callbacks, and `SketchContext` silently does nothing when a control
  handler is missing, so all five were no-ops on that path — `noLoop()` flipped
  `isLooping` while frames kept coming, and `createCanvas()` left the canvas at
  its original size. This is the same gap `SketchView` had in
  [#808](https://github.com/shinyaoguri/metaphor/issues/808) and
  [#828](https://github.com/shinyaoguri/metaphor/issues/828), now closed on the
  third and last path. Call them through the window's own context — e.g.
  `preview?.context.noLoop()` — and they affect only that window
  ([#857](https://github.com/shinyaoguri/metaphor/issues/857)).
  - Secondary windows run on a timer rather than a display link when headless
    (`METAPHOR_VIEWER=1`) or when `syphonName` is set, so `noLoop()` suspends that
    timer and `frameRate()` reschedules it — pausing the `MTKView` would not have
    stopped either case (and there is no view at all when headless).
  - `createCanvas()` resizes the window to match the new canvas but does not
    re-center it, so the cascade offset between multiple windows survives.
- `Color(hex: String)` now reads an 8-digit alpha of `00` as fully transparent.
  The string initializer used to hand the parsed value to `Color(hex: UInt32)`,
  which tells 6-digit from 8-digit spellings apart **by magnitude**
  (`hex > 0xFFFFFF`). Since `0x00FFFFFF == 0xFFFFFF`, a leading `00` fell into
  the RGB branch and the alpha silently became `1.0` — so `Color(hex: "#00FFFFFF")`
  came back opaque white instead of transparent white. Only alpha `00` was
  affected; `01` and up parsed correctly. The string initializer now splits
  AARRGGBB itself, because the digit count is visible in the spelling.
  - 6-digit spellings are unchanged and stay opaque.
  - `Color(hex: UInt32)` is unchanged: an integer literal keeps no leading
    zeros, so alpha `0x00` cannot be expressed there. Spell such colours with
    the 8-digit string form or use `withAlpha(_:)` — this limitation is now
    stated in its documentation
    ([#870](https://github.com/shinyaoguri/metaphor/issues/870))
- Immediate 3D shapes (`beginShape3D(.triangleStrip)` / `.triangleFan`) now get a
  face normal on **every** vertex when you never call `normal()`. The automatic
  computation used to walk the recorded vertices three at a time, which only
  matches `.triangles`: a strip flipped the normal on every other group of three
  and left the trailing vertices at the default `(0, 1, 0)`, so a ribbon lit from
  the front came out in alternating lit/black bands with a dark tail. The rule now
  reads the tessellated index list instead — the same shared helper the retained
  path uses ([#738](https://github.com/shinyaoguri/metaphor/issues/738)) — so the
  same shape gets the same normals whichever layer you draw it from. Two shapes
  change appearance: a **non-planar** `.polygon` now gets an area-weighted average
  per vertex instead of the first three vertices' face normal applied to all, and
  `.lines` / `.points` keep the default `(0, 1, 0)` instead of a geometrically
  meaningless "face normal" of three points along the polyline. Shapes that call
  `normal()` are untouched
  ([#875](https://github.com/shinyaoguri/metaphor/issues/875))
- Retained shapes (`createShape()` + `beginShape()`) built in `.triangleStrip` or
  `.triangleFan` mode no longer crash the process when the shape ends up holding
  a single 3D vertex. Index construction computed `0..<(count - 2)` and
  `1..<(count - 1)` without a lower bound, so one vertex produced a negative-width
  `Range` and trapped with `Range requires lowerBound <= upperBound`. Vertex
  counts are often decided at run time by generative code, so a loop that happens
  to run once should not take the sketch down. Both modes now match their 2D
  counterparts and simply produce no fill mesh below three vertices
  ([#881](https://github.com/shinyaoguri/metaphor/issues/881))
- Retained shapes built with `createShape()` now fill self-intersecting outlines the same way
  the immediate mode does. `beginShape()` / `polygon()` moved to non-zero winding in
  [#768](https://github.com/shinyaoguri/metaphor/issues/768), but `MShape` kept calling plain
  ear clipping, so the very same five `vertex()` calls came out as a star when drawn directly
  and as a blob when drawn through `shape(star)`. Simple outlines still take the old path and
  are triangle-for-triangle unchanged; `beginContour()` holes are unaffected
  ([#886](https://github.com/shinyaoguri/metaphor/issues/886))
- `MPSImageFilterWrapper` now validates the morphological kernel size before
  handing it to Metal Performance Shaders, so a bad radius no longer takes the
  whole process down. These methods return `Void`, so the failures could not be
  surfaced as a thrown error or a `nil`
  ([#893](https://github.com/shinyaoguri/metaphor/issues/893)):
  - `erode(_:radius:)`, `dilate(_:radius:)`, `encodeErode(...)` and
    `encodeDilate(...)` clamp `radius` to `0...max(width, height) - 1`. A
    negative radius used to reach `MPSImageAreaMin`/`AreaMax` as a huge unsigned
    kernel width and hang forever inside `waitUntilCompleted()`, and a very
    large radius overflowed `radius * 2 + 1` and trapped. The kernels use
    `edgeMode = .clamp`, so at `max(width, height) - 1` the window already
    covers the whole texture and a larger radius cannot change the output — the
    clamp is invisible in the resulting image.
  - `median(_:diameter:)` and `encodeMedian(...)` clamp `diameter` to the odd
    values the device supports (`MPSImageMedian.minKernelDiameter()` through
    `maxKernelDiameter()`, 3 through 127 on Apple Silicon). Anything larger used
    to abort with an MPS assertion; only the lower bound was enforced before.
- Primitive mesh factories now reject non-finite dimensions instead of building a
  mesh whose vertices are all `NaN`. `Mesh.box`, `sphere`, `plane`, `cylinder`,
  `cone` and `torus` throw `MetaphorError.invalidParameter` when a dimension is
  `NaN` or `±infinity`, so `createBoxMesh(.nan, .nan, .nan)` and friends return
  `nil` and no longer park a `"mesh_box_nan_nan_nan"` entry in the mesh cache —
  where every differently-signed `NaN` collapsed onto the same key and the entry
  survived until eviction. Finite dimensions are unchanged, including `0` (a
  flattened mesh) and negative values (a mirrored one); only `detail`-style
  segment counts are clamped, as before
  ([#894](https://github.com/shinyaoguri/metaphor/issues/894))
- The two sample sketches that spelled out an `ortho()` range passed
  `bottom > top`, which flips the picture upside down: the `ortho()` reference
  snippet and the `05-ThreeD/04-Camera` tutorial example. Copying either one
  gave a scene mirrored against `perspective()` and 2D `screenPosition()` — the
  tutorial's floor sat above the columns it was holding up. Both now pass
  `bottom: -height … top: height`, matching the range `ortho()` uses when the
  arguments are omitted ([#903](https://github.com/shinyaoguri/metaphor/issues/903))
- `Graphics` (the `createGraphics()` offscreen buffer) now forwards the 18
  remaining 2D drawing APIs it was missing, so the same code works whether it
  draws onto a sketch or into an offscreen buffer: `beginContour()` /
  `endContour()`, `beginClip()` / `endClip()`, `linearGradient()` /
  `radialGradient()`, `textLeading()`, `textToPoints()` / `textToContours()`,
  `applyMatrix()` (3x3 and the 6-component Processing form) / `resetMatrix()` /
  `shearX()` / `shearY()` / `screenPosition()`, and the separate transform and
  style stacks `pushMatrix()` / `popMatrix()` / `pushStyle()` / `popStyle()`.
  Previously `Graphics` only had the combined `push()` / `pop()`, so an
  offscreen buffer could not stack transforms and styles independently.
  `screenPosition()` reports coordinates inside the buffer (its own `width` ×
  `height` space), not on screen
  ([#908](https://github.com/shinyaoguri/metaphor/issues/908))
- `erode` and `dilate` no longer hang the sketch at large radii.
  `MPSImageAreaMin`/`AreaMax` stop completing once the kernel is 483 wide
  (radius 241): the GPU command never finishes, so `waitUntilCompleted()` blocks
  forever with no assertion, no command-buffer error and no log — measured to be
  independent of the texture size, while radius 240 returns in 12–59 ms.
  Because the radius is only clamped to the longest side of the texture, any
  canvas 242 px or wider could reach it with a perfectly ordinary radius
  (say, one driven from `@Param` or OSC). A radius above 120 is now applied in
  several passes of at most 120 each. Flat-structuring-element erosion and
  dilation decompose exactly — `erode(r1 + r2) == erode(r2) ∘ erode(r1)`, and
  `edgeMode = .clamp` preserves that — so the resulting image is byte-identical
  to what a single pass would have produced, and radii of 120 or less still take
  the single-pass path unchanged
  ([#919](https://github.com/shinyaoguri/metaphor/issues/919))
- `MPSImageFilterWrapper.median(_:diameter:)` and `encodeMedian(...)` no longer
  darken the edges of the image. The kernel was left on `MPSUnaryImageKernel`'s
  default `edgeMode` of `.zero`, so near a border — where more than half of the
  window falls outside the image — the median was taken over the zeros that MPS
  reads there, and the corners came out black. Median picks one of the values in
  its window, so it should never introduce a value the input does not contain.
  The kernel now uses `.clamp`, matching `gaussianBlur`, `erode` and `dilate`
  ([#920](https://github.com/shinyaoguri/metaphor/issues/920))
- `text()` no longer squares its antialiasing coverage. Glyph atlases are premultiplied but
  were composited as if straight, which made semi-transparent text darker and thinner than
  the requested `fill` alpha ([#846](https://github.com/shinyaoguri/metaphor/issues/846))
- `image()`, `copy()`, `previousFrame()` and drawing a `createGraphics()` layer back onto the
  canvas no longer multiply alpha twice. Semi-transparent images and offscreen layers used to
  sink toward the backdrop ([#847](https://github.com/shinyaoguri/metaphor/issues/847))
- `MImage.get()` / `loadPixels()` now return straight (un-premultiplied) values, and
  `set()` / `updatePixels()` premultiply on the way back to the GPU. `set(x, y, get(x, y))` is
  the identity again, and `mask()` — which only replaces the alpha channel — is correct on
  semi-transparent images ([#848](https://github.com/shinyaoguri/metaphor/issues/848))

## [0.9.0] - 2026-08-10

### Breaking Changes

- **`mouseButton` is now a `MouseButton?` instead of an `Int`.** The new enum has `left`, `right` and `middle` cases ([#382](https://github.com/shinyaoguri/metaphor/issues/382)). The old `Int` made the Processing idiom `if mouseButton == LEFT` **compile and always evaluate to `false`**: metaphor's `LEFT` is the left-arrow virtual key code (`UInt16` 123), and Swift permits heterogeneous integer comparison, so nothing diagnosed it. That comparison is now a compile error. Migrate `mouseButton == 0` / `1` / `2` to `mouseButton == .left` / `.right` / `.middle`; no `Int`-typed alias is provided, deliberately, because it would re-open the exact `== LEFT` hole this change closes.
  - The property is **optional**: it is `nil` until the first press, which the old `Int` could not express (`0` meant both "left" and "never pressed"). After a press it keeps the last pressed button even once released — as in Processing — so `mouseReleased()` can still tell which button was let go. Ask `isMousePressed` whether a button is down right now.
  - `MetaphorPlugin.mouseEvent(x:y:button:type:)` takes `button: MouseButton?`, `nil` for the buttonless `.moved` / `.dragged` / `.scrolled` events (it used to receive a meaningless `0`). **This is a protocol requirement**, so a plugin still declaring `button: Int` compiles but silently stops being called, exactly like the `pre` / `post` rename above — update the signature. `InputManager.onMousePressed` / `onMouseReleased` / `onMouseClicked` now hand a `MouseButton` to their closures.
  - The stdin JSON Lines input protocol is **unchanged**: its `button` field stays an integer (`0` / `1` / `2`), per CONTRACT.md contract point 3. The conversion happens inside metaphor, so `metaphor-cli` needs no update.
- **`cylinder`, `cone` and `torus` no longer default their size arguments.** `cylinder(radius:height:detail:)`, `cone(radius:height:detail:)` and `torus(ringRadius:tubeRadius:detail:)` used to default to `radius: 0.5` / `height: 1` / `tubeRadius: 0.2` — world units left over from an earlier design. The default camera is pixel space (one world unit is one pixel), so those defaults drew a one-pixel object that is invisible in practice, and `box` / `sphere` / `plane` already required their sizes. The size arguments are now required at every layer (`Sketch`, `SketchContext`, `Canvas3D`, `Graphics3D`); the quality argument `detail: Int = 24` keeps its default, matching `sphere(_:detail:)` ([#380](https://github.com/shinyaoguri/metaphor/issues/380)). A call that omitted a size no longer compiles — pass pixel sizes, e.g. `cylinder(radius: 50, height: 100)`, `torus(ringRadius: 120, tubeRadius: 40)`. To keep the old geometry exactly, pass the former defaults explicitly (`cylinder(radius: 0.5, height: 1)`). The low-level `Mesh.cylinder` / `Mesh.cone` / `Mesh.torus` builders are unchanged and still default to a unit-sized mesh.
- `translate(x, y)`, `rotate(a)` and `scale(sx, sy)` now apply to the **3D** transform as well as the 2D one, matching Processing's `P3D` semantics ([#325](https://github.com/shinyaoguri/metaphor/issues/325), [#384](https://github.com/shinyaoguri/metaphor/pull/384), ADR-0005 Amendment 2026-08-02). On the 3D matrix they mean a `z = 0` translation, a rotation about z, and a scale that leaves z unchanged. This works because the 3D world is already pixel space — the default camera matches Processing's `P3D` default — so `translate(width/2, height/2)` followed by `box()` now centers the box instead of leaving it at the top-left corner. If a sketch relied on a two-argument transform moving *only* 2D content, wrap that region in `pushMatrix()` / `popMatrix()` (both already save and restore 2D and 3D). Public signatures are unchanged, so this breaks rendering output, not compilation. `shearX`/`shearY` and `applyMatrix(float3x3)` stay 2D-only.
- Removed seven APIs that had been deprecated long enough to meet the ADR-0005 removal condition — each shipped as deprecated in at least one earlier minor release ([#354](https://github.com/shinyaoguri/metaphor/pull/354)). Migrate as follows:
  - `MetaphorPlugin.onBeforeRender(commandBuffer:time:)` → `pre(commandBuffer:time:)`
  - `MetaphorPlugin.onAfterRender(texture:commandBuffer:)` → `post(texture:commandBuffer:)`
  - `Sketch.draw(_ ctx: SketchContext)` → `draw()`, reaching the context through `self` (for example `self._context`)
  - `Sketch.camera` and `SketchContext.camera` taking nine `Float` arguments → `camera(eye:center:up:)` taking `SIMD3`
  - `Physics2D.addGravity(_:_:)` → `setGravity(_:_:)`
  - `SoundFile.volume` → `gain`
- The two removed `MetaphorPlugin` methods were protocol requirements, so a custom plugin that only implements `onBeforeRender` / `onAfterRender` now compiles but is never called. Rename those methods to `pre` / `post` ([#354](https://github.com/shinyaoguri/metaphor/pull/354)).
- **Throwing APIs now throw only their own module's error type.** Previously a number of resource-creation APIs let the underlying framework error escape unchanged — a Metal `NSError` from `makeRenderPipelineState` / `makeLibrary`, a Foundation `NSError` from `String(contentsOfFile:)` / `FileManager`, a MetalKit `NSError` from `MTKTextureLoader`, an AVFoundation `NSError` from `AVAudioFile` / `AVAssetWriter`, or an `NWError` from `NWListener`. Those are now wrapped in `MetaphorError` (or the module's own error type), with the original cause preserved as a string in the case payload. If you were catching a concrete `NSError` / `NWError` from any of the following, catch the metaphor error instead ([#323](https://github.com/shinyaoguri/metaphor/issues/323)):

  | API | Now throws |
  |---|---|
  | `PipelineFactory.build()` / `.buildCompute(device:function:)` | `MetaphorError.pipelineCreationFailed(name:underlying:)` |
  | `ShaderLibrary.register(source:as:)` / `.reload(key:source:)` | `MetaphorError.shaderCompilationFailed(name:underlying:)` |
  | `ShaderLibrary.registerFromFile(path:as:)` / `.reloadFromFile(key:path:)` | `MetaphorError.shaderSourceLoadFailed(path:detail:)`, then the above |
  | `ComputeKernel.init(device:source:functionName:)` / `.init(device:function:)` | `MetaphorError.shaderCompilationFailed` / `.compute(.functionNotFound)` / `.pipelineCreationFailed` |
  | `MImage.init(path:device:)` / `.init(named:device:)` / `.init(nsImage:device:)`, `ResourceLoader.loadImageAsync(...)` | `MetaphorError.image(.loadFailed(source:detail:))` |
  | `Mesh.loadOBJ(device:url:)` | `MetaphorError.mesh(.loadFailed(path:detail:))` |
  | `GIFExporter.endRecord(to:)` / `.endRecordAsync(to:)`, `VideoExporter.beginRecord(...)` | `MetaphorError.export(.fileWriteFailed(path:detail:))` / `.export(.writerFailed(_:))` |
  | `MPSRayTracer.init(device:commandQueue:width:height:)` | `MetaphorError.shaderCompilationFailed` / `.pipelineCreationFailed` |
  | `SoundFile.init(path:)` | `SoundFileError.loadFailed(path:detail:)` |
  | `AudioAnalyzer.start()` | `AudioAnalyzerError.engineStartFailed(detail:)` |
  | `OSCReceiver.start()` | `OSCReceiverError.listenerCreationFailed(port:detail:)` |
  | `GoldenImage.load(pngAt:)` / `.write(pngTo:)` (MetaphorTestSupport) | `GoldenImageError.fileReadFailed(url:detail:)` / `.fileWriteFailed(url:detail:)` |

  Everything reached through those — `loadImage`, `loadSound`, `createComputeKernel`, `createMaterial`, `reloadShader`, `endGIFRecord`, `Canvas2D` / `Canvas3D` / `MetaphorRenderer` initializers, `MergePass.init`, and so on — is covered by the same guarantee. Code that already catches `MetaphorError` (or catches everything) needs no change.

  Carrying those causes required new cases on public error enums (`MetaphorError.shaderSourceLoadFailed`, `MetaphorError.ImageFailure.loadFailed`, `MetaphorError.MeshFailure.loadFailed`, `MetaphorError.ExportFailure.fileWriteFailed`, `SoundFileError.loadFailed`, `AudioAnalyzerError.engineStartFailed`, `OSCReceiverError.listenerCreationFailed`, `GoldenImageError.fileReadFailed` / `.fileWriteFailed`), so an exhaustive `switch` over one of them now needs the extra case or a `default` ([#323](https://github.com/shinyaoguri/metaphor/issues/323)).
- **Five symbols that documented themselves as internal are now `internal`** and no longer appear in the compiled API surface or in `llms.txt` (ADR-0007 Decision 6, [#388](https://github.com/shinyaoguri/metaphor/issues/388)). They were never public API — `docs/api-stability-policy.md` §1 excluded them explicitly — but the access modifier said otherwise, and after the `v0.9.0` freeze removing `public` would require a major release. None of them is referenced by `Examples/`, by [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli), or by anything in `CONTRACT.md`:

  | Removed from the public surface | What to use instead |
  |---|---|
  | `MetaphorRenderer.onCaptureOutput` | `MetaphorPlugin.post(texture:commandBuffer:)` — a plugin's output hook, and unlike this single-slot property it composes with other plugins |
  | `MetaphorRenderer.shadowDeferActive` / `.onRecordFrame` / `.onReplayMain` | No replacement. These three wire up the same-frame shadow path (ADR-0003) between `SketchRunner` and the renderer; driving them by hand was never supported |
  | `MetaphorSyphon.SyphonPlugin` | `MetaphorRenderer.startSyphonServer(name:)` / `.stopSyphonServer()` / `.syphonOutput`, or `SketchConfig(syphon:)` — all still public and unchanged |

  `_metaphorSyphonRegister()`, the last underscore-prefixed `public` symbol in the library, is now `internal` as well. It is the `@_cdecl("metaphor_syphon_register")` entry point that a C load-time constructor calls to register the Syphon output factory (ADR-0001); `@_cdecl` emits the C symbol independently of the Swift access level, so automatic Syphon registration is unaffected — re-verified across debug/release × same-package/cross-package.

### Added

- `CHANGELOG.md` (this file), plus GitHub Release notes generated from it: the release workflow now refuses to publish while `## [Unreleased]` is empty, promotes it to the released version, and puts it above the auto-generated pull request list ([#335](https://github.com/shinyaoguri/metaphor/issues/335))
- `THIRD_PARTY_LICENSES.md`, recording the Simplified BSD license of the [Syphon Framework](https://github.com/Syphon/Syphon-Framework) redistributed as `Syphon.xcframework` ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `SECURITY.md` with a private path for reporting vulnerabilities ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `CONTRIBUTING.md` and GitHub Issue / pull request templates, including routing between this repository and [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli) ([#341](https://github.com/shinyaoguri/metaphor/pull/341))
- Both READMEs now link to the published DocC API reference ([#342](https://github.com/shinyaoguri/metaphor/pull/342))
- `docs/permissions.md` explaining microphone/camera TCC permissions for `swift run` binaries, an English `docs/README.en.md`, expanded README Troubleshooting (Intel Mac, SwiftPM dependency-resolution failures), and `Examples/LEARNING_PATH.md`, a curated "learn in order" route through the example catalog ([#337](https://github.com/shinyaoguri/metaphor/issues/337))
- `filter(_ image: MImage, _ type: FilterType)` on the `Sketch` layer. The GPU filter previously existed only on `SketchContext`, so the documented user-facing surface had no entry for it. Use the GPU version while a sketch is running; the CPU version `MImage.filter(_:)` stays available for standalone images that have no renderer ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `SoundFile.disableAnalysis()`, the missing counterpart to `enableAnalysis(fftSize:)`. It removes the main-mixer tap and releases the analyzer, after which `spectrum` / `analysisVolume` / `isBeat` / `band(_:)` report their neutral values again ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `docs/api-stability-policy.md`, the API stability policy: what counts as public API across the four layers (and what does not), source compatibility with no ABI guarantee, the deprecation window, where rendering output / the Probe wire schema / stdin / environment variables sit under SemVer, the frozen `@_exported import Metal / MetalKit / simd`, supported platforms, and the `0.9.x` freeze discipline. Both READMEs also now state that the project is maintained by one person on a best-effort basis ([#338](https://github.com/shinyaoguri/metaphor/issues/338))
- `docs/processing-migration-guide.md`, a "the Processing X is metaphor's Y" mapping table plus a pitfalls collection (value vs reference types, `@MainActor`, the two color ranges, the 2D/3D transform split, `loadPixels()` pass splitting, `LEFT` being a key code rather than an alignment constant) and an explicit list of Processing APIs that are not implemented yet. Linked from both READMEs ([#336](https://github.com/shinyaoguri/metaphor/issues/336))
- `@Param` declares a tunable sketch property that **persists across restarts** and can be
  changed **without rebuilding**. Values live in a `ParameterStore` (`SketchContext.params`),
  are written atomically to `.metaphor/params/params.json`, and are restored on the next
  launch before `setup()` runs. External tools and AI agents change them by writing
  `.metaphor/params/set-request.json` (`{"id": "<unique>", "values": {…}}`); the next frame
  applies it and echoes `appliedRequestId` / `revision`, with rejected values explained in
  `warnings`. Supported types: `Float` / `Double` / `Int` / `Bool` / `String` (optional
  `choices`) / `Color` / `Vec2` / `Vec3`; `min` / `max` clamp external writes.

  ```swift
  @main final class MySketch: Sketch {
      @Param(min: 10, max: 200) var radius: Float = 50
      @Param(choices: ["add", "multiply"]) var mode: String = "add"

      func draw() { circle(width / 2, height / 2, radius) }
  }
  ```

  Enabled automatically when a sketch declares at least one `@Param` (no CLI needed);
  opt out with `METAPHOR_PARAMS=0`. The file formats are cross-repo contract point 7
  ([CONTRACT.md](https://github.com/shinyaoguri/metaphor/blob/main/CONTRACT.md),
  [#419](https://github.com/shinyaoguri/metaphor/issues/419))
- `gui.params()` draws a live control panel for every `@Param` a sketch declares — one line,
  no wiring. The panel and an AI agent writing `.metaphor/params/set-request.json` are
  symmetric clients of the same `ParameterStore`, so a value dragged on a slider is
  persisted to `.metaphor/params/params.json` and restored on the next launch.

  ```swift
  @main final class MySketch: Sketch {
      @Param(min: 10, max: 200) var radius: Float = 50
      @Param var showGrid: Bool = true
      @Param(choices: ["cool", "warm"]) var palette: String = "cool"

      func draw() {
          gui.params()                              // sliders / toggles / pickers
          circle(width / 2, height / 2, radius)
      }
  }
  ```

  Widgets follow the declared type: `Float` / `Int` become sliders, `Bool` a toggle,
  `Color` an RGB picker, `Vec2` / `Vec3` component sliders, and a `String` with `choices`
  a button that cycles through them. Numbers declared without `min` / `max` get a stable
  auto range derived from their first displayed value. `gui.param("radius")` places a
  single parameter when you want to lay the panel out yourself, and the existing immediate
  mode (`gui.slider("x", &x, …)`) is unchanged. New example:
  `Examples/Samples/ParameterPanel`
  ([#422](https://github.com/shinyaoguri/metaphor/issues/422))
- A Probe snapshot now carries the parameters that produced it. `frame.json` gains an
  additive `params` section — `{"revision": 7, "values": {"radius": 120.0, …}}` — so an AI
  agent reading a frame knows exactly which `@Param` values were in effect, instead of
  reading `.metaphor/params/params.json` separately and hoping nothing changed in between.
  `revision` matches the store's counter, which makes "is this the frame after my
  `set_param`?" a comparison rather than a guess.

  The section is omitted for sketches that declare no `@Param`, and for failure responses.
  Unlike `performance`, it is also written for every frame of a `capture_sequence` run
  (reading the store costs no syscall), so sweeping a parameter during a capture stays
  legible frame by frame. Type, range and `choices` remain canon in `params.json`;
  `frame.json` carries values only. Wire format: `schemaVersion` stays 4 (additive),
  contract point 4 in [CONTRACT.md](https://github.com/shinyaoguri/metaphor/blob/main/CONTRACT.md)
  ([#424](https://github.com/shinyaoguri/metaphor/issues/424))
- `vertex(x, y, z, u, v)` gives a `beginShape3D()` vertex its texture
  coordinates, so `texture(img)` now applies to custom 3D shapes. Until now the
  3D vertex format had no UV channel and a textured `beginShape3D()` silently
  rendered with the current fill; the five shipped `Topics/Textures` examples
  (`TextureQuad` / `TextureCube` / `TextureSphere` / `TextureTriangle` /
  `TextureCylinder`) now show their textures. `u` / `v` are normalized (0…1),
  the UV travels with its vertex through every tessellation mode, and a shape
  whose vertices carry no UV keeps rendering with the fill exactly as before
  ([#433](https://github.com/shinyaoguri/metaphor/issues/433))
- `DynamicMesh.addTexCoord(u, v)` (and `setTexCoord(index:_:)`) gives a dynamic
  mesh its texture coordinates, so `texture(img)` now applies to
  `dynamicMesh(mesh)` as well. Until now `DynamicMesh` carried only
  position / normal / color, and a textured dynamic mesh silently rendered with
  the current fill. `u` / `v` are normalized (0…1), UV stays aligned with its
  vertex through `setVertex` / indexed drawing, and a mesh that never declares a
  texture coordinate keeps rendering with the fill exactly as before. Textures
  also survive the recorded path (shadows / `METAPHOR_COMMAND_RECORD`). New
  sample: `Examples/Samples/DynamicMeshTexture`
  ([#435](https://github.com/shinyaoguri/metaphor/issues/435))
- `drawInstanced(mesh, transforms:)` (and the `colors:` overload) draws one mesh
  at many transforms in a single call. Each instance is placed at
  `currentTransform * transforms[i]`, so it is equivalent to a
  `pushMatrix()` / `applyMatrix(t)` / `mesh(m)` / `popMatrix()` loop — but the
  per-instance state evaluation (batch key, matrix composition, normal matrix)
  happens once instead of N times (20k cubes: ~15ms → ~11ms of CPU encoding in a
  debug build). `colors` sets the fill color per instance; entries beyond
  `transforms` are ignored and missing ones fall back to the current fill.
  Stroke color, material and texture stay shared across instances. Works on the
  recorded path (shadows / `METAPHOR_COMMAND_RECORD`) too, where all instances
  share one draw sequence number. New sample: `Examples/Samples/InstancedCubes`
  ([#442](https://github.com/shinyaoguri/metaphor/issues/442))
- Primitive meshes can now be created from the sketch layer, without reaching for
  `MTLDevice`: `createBoxMesh(_:_:_:)` / `createBoxMesh(_:)` / `createSphereMesh(_:detail:)` /
  `createPlaneMesh(_:_:)` / `createCylinderMesh(radius:height:detail:)` /
  `createConeMesh(radius:height:detail:)` / `createTorusMesh(ringRadius:tubeRadius:detail:)`.
  Each takes the same arguments as the matching drawing primitive (`box`, `sphere`, …) and
  returns the same geometry as a `Mesh` value, ready for `mesh(_:)` and
  `drawInstanced(_:transforms:)`. Repeated calls with the same arguments return the same
  instance, so create meshes in `setup()` rather than per frame
  ([#443](https://github.com/shinyaoguri/metaphor/issues/443))

  ```swift
  // before
  let cube = try? Mesh.box(device: context.renderer.device, width: 12, height: 12, depth: 12)
  // after
  let cube = createBoxMesh(12)
  ```
- `saveState()` / `restoreState(_:)` carry a sketch's own state across a live
  reload, and `SketchConfig(preserveClock: true)` carries `frameCount` and `time`
  with no sketch code at all. Both are optional: the default implementations are
  `nil` / no-op, and a failed decode silently keeps the initial state instead of
  breaking the reload. `encodeState` / `decodeState` wrap `Codable` payloads.
  The state travels through a new file contract (`.metaphor/state/state.json` +
  `save-request.json`, CONTRACT.md point 8) in the same style as Probe and the
  Parameter Store — atomic writes, mtime polling, `id` echo — so it works with
  `metaphor watch` and by hand alike. Enabled automatically in headless
  (`metaphor watch`) runs; `METAPHOR_STATE=1` turns it on for a plain
  `swift run`, `METAPHOR_STATE=0` off. New sample:
  `Examples/Samples/StatePreservation`
  ([#451](https://github.com/shinyaoguri/metaphor/issues/451))

### Changed

- `loadPixels()` on the main canvas now reads back **the canvas as of the call**, matching Processing. Previously it could only return the content committed up to the end of the previous frame, so shapes drawn earlier in the same `draw()` were missing. Calling it mid-`draw()` closes the current render pass, commits it, waits for the GPU, and resumes drawing in a `loadAction = .load` continuation pass — the rendered frame is unchanged, and sketches that never call `loadPixels()` pay nothing. Two consequences to know about: the pass split clears depth, so 3D drawn before and after a `loadPixels()` call is no longer depth-tested against each other; and with shadows enabled the same-frame readback is unavailable (`draw()` runs as a record pass first), in which case the last committed frame is read and a warning is logged once ([#326](https://github.com/shinyaoguri/metaphor/issues/326))

- Published tags and Release assets are now treated as immutable and are enforced as such: `refs/tags/v*` cannot be deleted or moved, every tag's `binaryTarget` URL is health-checked weekly, and a release verifies its own uploaded `Syphon.xcframework.zip` against the checksum in `Package.swift` before telling `metaphor-cli` to pin it. SwiftPM re-fetches that asset on every dependency resolution, so a deleted asset would permanently break the tag for existing users ([#352](https://github.com/shinyaoguri/metaphor/pull/352))
- Every public throwing API now documents the concrete error cases it throws in its `- Throws:` line, and `MetaphorError` documents the contract itself. ADR-0005's "resource creation uses typed throws" is now realised as a documented single-error-type contract rather than the `throws(E)` syntax: typed throws (SE-0413) is a Swift 6.0 feature and the library still supports Swift 5.10, so applying the syntax is deferred until that minimum is raised — at which point it becomes a mechanical change with no behavioural difference ([#323](https://github.com/shinyaoguri/metaphor/issues/323))
- `setRenderGraph(_:)` and `setClearColor(_:_:_:_:)` document their naming explicitly: passing `nil` to the former is how you clear the active render graph (there is no separate `clearRenderGraph()`), and the `clear` in the latter is the Metal noun "clear color", not the deleting `clear*` verb used by `clearPostEffects()` ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `ambientLight()` and `lights()` now document the default ambient level on every layer (`Sketch`, `SketchContext`, `Graphics3D`, `Canvas3D`): the ambient that `lights()` — or the first light you add — installs for you is **30% of the current `colorMode` range**, i.e. `ambientLight(76.5)` in the default 0–255 range. It was previously written as a raw `0.3` in the source, which read as if `ambientLight(0.3)` would reproduce it when in fact that value is 1/255 of it. Rendering is unchanged, bit for bit ([#392](https://github.com/shinyaoguri/metaphor/issues/392))
- **Every module now builds warning-free under Swift 6 strict concurrency**, on both the newest toolchain and the oldest supported one (Swift 5.10 / Xcode 15.4), and CI keeps it that way — `build-and-test` already compiled with `-warnings-as-errors`, `build-swift-5-10` now does too, and a manifest check refuses a new target that forgets the setting. Public signatures are unchanged; the only observable difference is that `MetaphorRenderer`'s two `MTKViewDelegate` methods (`draw(in:)`, `mtkView(_:drawableSizeWillChange:)`) are now `nonisolated` and assert main-actor isolation internally, because the requirement is not main-actor-isolated in the 5.10 SDK. Along the way `@preconcurrency import` went from 29 occurrences to 13 — every one was removed and only those the compiler still demands were put back, each with a comment saying why. This is the groundwork for adopting the Swift 6 language mode once the minimum toolchain is raised ([#328](https://github.com/shinyaoguri/metaphor/issues/328))
- Failure modes are now documented explicitly in three places, with no behavior change: the `SoundFile` usage example shows `do`/`catch` instead of `try!`, which would crash the sketch on a missing or undecodable file; `GPUBuffer`'s subscript states that out-of-range access traps, matching `Swift.Array`; and the gradient-stop noise texture APIs state that fewer than 2 color stops return nil, now locked by tests ([#374](https://github.com/shinyaoguri/metaphor/pull/374))
- Changelog entries now live one-per-file in [`changelog.d/`](https://github.com/shinyaoguri/metaphor/tree/main/changelog.d) instead of being appended to `## [Unreleased]` by every pull request, which made concurrent pull requests conflict on the same lines almost every time. `scripts/changelog.py collect` folds them into `## [Unreleased]` at release time (and `changelog.py release` runs it first), so the published changelog is unchanged — only the way contributors write into it is. Writing under `## [Unreleased]` directly still works

### Deprecated

- The recording APIs are renamed so that every family reads `begin<Media>Record` / `end<Media>Record`, and the two `async` overloads that shared a name with their synchronous counterparts gain an `Async` suffix (ADR-0007, [#322](https://github.com/shinyaoguri/metaphor/issues/322)). The old names still work but now warn; they will be **removed in the next minor release**, so migrate now:

  | Deprecated | Use instead |
  |---|---|
  | `beginSVG(_:)` / `endSVG()` | `beginSVGRecord(_:)` / `endSVGRecord()` |
  | `beginRecord(directory:pattern:)` / `endRecord()` | `beginFrameRecord(directory:pattern:)` / `endFrameRecord()` |
  | `endGIFRecord(_:) async throws` | `endGIFRecordAsync(_:)` |
  | `endVideoRecord() async` (and `VideoExporter.endRecord() async`) | `endVideoRecordAsync()` (and `VideoExporter.endRecordAsync()`) |
  | `dispatch(_:threads:_:)` / `dispatch(_:width:height:_:)` | `dispatch(_:threads:configure:)` / `dispatch(_:width:height:configure:)` |

  The old plain `beginRecord()` was the one that clashed with Processing's `beginRecord()` (which starts *vector* recording, not a PNG sequence) — `beginFrameRecord` / `beginSVGRecord` remove that trap. `beginOfflineRender()` / `endOfflineRender()` keep their names: they switch rendering *mode* rather than start a recording.

  The two `dispatch` changes only add a `configure:` label to the trailing closure, so the usual trailing-closure call site (`dispatch(kernel, threads: n) { ... }`) is unchanged and keeps compiling without a warning. Only calls that pass the closure as an explicit final argument need updating.

### Fixed

- `screenY(x, y, z)` (3D) returned a y coordinate mirrored relative to the 2D `screenY(x, y)`, because `Canvas3D.screenPosition(_:_:_:)` mapped NDC y to pixel space with the same `(ndc + 1) / 2` formula used for x, without accounting for the Y-flip already baked into the view-projection matrix ([#378](https://github.com/shinyaoguri/metaphor/issues/378)). A point above the canvas center now correctly reports a smaller `screenY`, matching the 2D API's left-top-origin, Y-down convention. `screenX(x, y, z)` and `screenZ(x, y, z)` were unaffected.
- With `enableShadows()`, the shadow factor is now applied to **direct light only** (diffuse + specular). Ambient light, emissive colour and the PBR ambient-occlusion factor are no longer folded into the shadow attenuation, in both the Blinn-Phong and PBR paths ([#364](https://github.com/shinyaoguri/metaphor/issues/364)). Previously an emissive material went completely dark inside a shadow, and `ambientOcclusion()` was cancelled there, making shadowed surfaces *brighter* than the lit ones next to them. **Shaded output can change for sketches that call `emissive()` or `ambientOcclusion()` together with `enableShadows()`** — shadowed areas of those materials now keep their emissive glow and their occlusion. Materials that use neither (the default) render exactly as before, bit for bit. `ambientLight()` and `directionalLight()` also document two conventions that are easy to get wrong: ambient takes a value in the current `colorMode` range (0–255 by default, so `ambientLight(0.35)` is essentially black), and a light direction is the direction the light *travels* in a y-down world, so `directionalLight(0, 1, 0)` is the one that shines from above.
- `frameRate(0)` and negative values are now clamped to `1` before reaching `renderer.targetFPS` (which Probe's `frame.json` reports verbatim) and `MTKView.preferredFramesPerSecond`, with a `metaphorWarning` when clamping happens ([#358](https://github.com/shinyaoguri/metaphor/issues/358)). Previously the `max(fps, 1)` clamp was only applied to the timer-loop interval calculation, so the displayLink path (`MTKView.preferredFramesPerSecond`) and the reported `targetFPS` silently received `0` or negative values — `0` means "as fast as possible" for `MTKView`, and Probe consumers (AI agents) would read an invalid frame rate. `frameRate(_:)` still forwards its argument verbatim from `Sketch` through `SketchContext`; the clamp is applied once, at the entry of `SketchRunner`'s internal frame-rate handler, so it covers `targetFPS`, the timer interval, and `MTKView` uniformly.
- `llms.txt` now lists the API you write at a **declaration site** rather than only the API
  that appears in a `Sketch` signature. Two whole families of public symbols were invisible
  to AI agents reading it:

  - **`@Param`** — the property wrapper is spelled at the declaration (`@Param(min: 10,
    max: 200) var radius: Float = 50`) and so appears in no method signature. It is now
    emitted with its `@propertyWrapper` attribute intact
    ([#421](https://github.com/shinyaoguri/metaphor/issues/421))
  - **Extensions on types metaphor does not own** — the PVector-style vector API
    (`normalized()` / `limited(_:)` / `heading()` / `rotated(_:)` / `dist(to:)` /
    `lerp(to:t:)` / `setMag(_:)` and the `mutating` variants on `Vec2` / `Vec3`), the
    `simd_float4x4` helpers, and the `ParamRepresentable` conformances on `Float` / `Int` /
    `Bool` / `String` / `Color`. These exist only because metaphor adds them, so `llms.txt`
    was the one place they could be discovered — and it omitted all of them
    ([#298](https://github.com/shinyaoguri/metaphor/issues/298))

  A symbol documented with a `- Parameters:` block but no abstract also no longer shows the
  first parameter's description as its summary. No API changed — only what the generated
  reference reports about it.
- Ten shipped examples that build 3D geometry with `beginShape()` + `vertex(x, y, z)`
  now use `beginShape3D()` / `endShape3D()`, so they render as solids again instead of
  collapsing into a plane (`Topics/Geometry/{Vertices,ShapeTransform,RGBCube,Toroid}`,
  `Topics/Textures/{TextureQuad,TextureCube,TextureSphere,TextureTriangle,TextureCylinder}`,
  `Demos/Graphics/Patch`). The library behaviour is unchanged — `beginShape()` still
  records into the 2D canvas — but the first `vertex(x, y, z)` inside a 2D `beginShape()`
  now logs a one-shot warning in debug builds pointing at `beginShape3D()`
  ([#387](https://github.com/shinyaoguri/metaphor/issues/387))
- 3D shapes now draw their wireframe in the stroke color instead of blending it
  with the fill color. The stroke pass reused the vertex colors baked in at
  `vertex()` time (the fill color) and multiplied them with the stroke color, so
  a stroke could come out wrong — or vanish entirely when the two colors were
  complementary (a blue fill and a red stroke multiplied to black). Strokes on
  `box()` / `sphere()` and friends were drawn in the fill color for the same
  reason. Wireframes are also depth-biased slightly toward the camera, so the
  lines of a shape that also has a fill are no longer rejected by the depth test
  against their own fill ([#429](https://github.com/shinyaoguri/metaphor/issues/429))
- `dynamicMesh()` now draws its wireframe in the stroke color and depth-biases it
  toward the camera, matching `beginShape3D()` and the mesh primitives. The
  stroke pass was left on the regular pipeline, so it multiplied the per-vertex
  colors set with `addColor()` into the stroke color (a red vertex color and a
  green stroke came out near black), and without the depth bias the lines lost
  the depth test against their own fill and disappeared
  ([#436](https://github.com/shinyaoguri/metaphor/issues/436))
- 3D primitives no longer crash on a non-positive `detail`. `sphere()`,
  `cylinder()`, `cone()`, `torus()` and their `createXxxMesh()` counterparts used
  to hit `Range requires lowerBound <= upperBound` (an untrappable `fatalError`)
  for a negative segment count, and produced degenerate geometry with `inf`/`NaN`
  coordinates for `0`. Segment counts are now clamped at the `Mesh` factories to
  a minimum of 3 (2 for sphere rings), so a `detail` driven from `@Param`, OSC or
  MIDI can pass through zero without killing a live sketch
  ([#445](https://github.com/shinyaoguri/metaphor/issues/445))

## [0.8.0] - 2026-08-01

Processing parity bundle: data IO (`loadJSON` / `saveJSON` / `loadTable` / `saveTable` / `loadStrings` / `saveStrings`), canvas operations (`applyMatrix` / `resetMatrix` / `shearX` / `shearY` / `screenX` / `screenY` / `screenZ` / `keyTyped` / `copy` / `mask` / `resize`), `selectInput` / `selectOutput` / `fileDropped`, PVector-style mutating methods on `Vec2` / `Vec3`, MSAA sample count in `SketchConfig`, OSC sending (`OSCSender`), path-keyed asset caching for `loadImage` / `loadModel`, SVG export (`beginSVG` / `endSVG`), and `README.en.md`. Fixes a first-frame `copy()` reading uninitialized VRAM. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.8.0)

## [0.7.0] - 2026-07-19

Probe `frame.json` gains a `performance` section (measured frame rate, memory, CPU, thermal state) for AI agents observing a running sketch. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.7.0)

## [0.6.0] - 2026-07-19

App Nap is suppressed by default while a sketch runs, so a backgrounded window keeps its frame rate. Fixes an `IOSurface` leak caused by a `CVMetalTexture` retain cycle and a timer/activity leak on teardown; speeds up large `Canvas3D` shapes and in-place Core Image / MPS filters. CI gains a Swift 5.10 (Xcode 15.4) build check. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.6.0)

## [0.5.3] - 2026-07-11

Multi-camera support: device enumeration and selection, closest-match `activeFormat` for a requested resolution, disconnect detection and permission checks, plus an example. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.3)

## [0.5.2] - 2026-07-03

Fixes: 2D physics broadphase missed collisions caused by large constraint moves, a race between Probe sequence directory cleanup and asynchronous writes, `ImageFilterGPU` cache growth on the `encode()` path, and `VideoExporter` state bleeding between consecutive recordings. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.2)

## [0.5.1] - 2026-07-02

`arc()` without an explicit mode now matches Processing (pie fill, arc-only stroke), and circle/arc segment counts adapt to size instead of being fixed at 32. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.1)

### Breaking Changes

- `arc()` called without a mode draws differently than before (Processing-compatible); pass an explicit mode to keep the old shape.

## [0.5.0] - 2026-07-02

A repository-wide correctness and robustness sweep touching every module (drawing, text, particles, post effects, physics, audio, MIDI/OSC, video, ML, RenderGraph, SceneGraph, export), the ADR-0005 API consistency work, camera/light snapshots in the command-recording path, main-canvas `loadPixels()` readback, and a rebuilt project website. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.0)

### Breaking Changes

- The deprecated `make*` bridge factories were removed — use the `create*` equivalents (`createAudioInput()`, `createOSCReceiver()`, `createPhysics2D()`, …), which now validate their arguments and no longer return spurious optionals (ADR-0005 phase 3).

## [0.4.0] - 2026-07-01

The AI-collaboration runtime: Probe image statistics and typed `probe()` values, `capture_sequence` for multi-frame observation, and a `sourceStamp` provenance block (`frame.json` schema v3 → v4). Drawing moves to a unified command stream, so 2D and 3D calls composite in call order. Cross-repository contract guardrails move to a wire-schema source of truth. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.4.0)

### Breaking Changes

- Syphon output moved out of `MetaphorCore` into its own `MetaphorSyphon` module. Users of the `import metaphor` umbrella are unaffected (the output registers itself on load); code importing `MetaphorCore` directly must also import `MetaphorSyphon`.

## [0.3.0] - 2026-06-21

Adds the `MetaphorProbe` plugin (snapshots and state for AI agents), headless rendering and stdin input injection for the live viewer, batched drawing for large circle counts, and a broad fix sweep across MIDI, OSC, audio, GIF export and both canvases. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.3.0)

## [0.2.4] - 2026-05-08

Release-workflow rework: GitHub Flow, a `GITHUB_TOKEN`-only release path, and pre-release tags. No library changes. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.4)

## [0.2.3] - 2026-05-04

Adds the `MetaphorVideo` module for video playback, moves `camera()` to SIMD3 signatures, fixes blend-mode alpha attenuation, and triple-buffers the staging texture used by video export. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.3)

## [0.2.2] - 2026-04-18

Memory-leak and robustness fixes (secondary windows, `CIFilterWrapper` storage, mesh and particle buffer allocation failures, `NoiseTexture` with no color stops) plus API-consistency renames with deprecated aliases: `Physics2D.addGravity()` → `setGravity()`, `SoundFile.volume` → `gain`, argument labels on the MIDI callbacks, and a public `OSCMessage`. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.2)

> **Note** — this release's GitHub Release page carries no assets; its `Package.swift` points at the `v0.2.1` asset instead. Deleting the `v0.2.1` asset would break both tags. See [docs/releasing.md](docs/releasing.md).

## [0.2.1] - 2026-03-08

Release plumbing only. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.1)

## [0.2.0] - 2026-03-08

Adds `PixelBuffer`, multi-window improvements, Core ML examples (face detection, image classification, person segmentation, style transfer) and the project website. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.0)

### Breaking Changes

- iOS support was removed; `metaphor` is macOS-only from this release on.

## [0.1.0] - 2026-01-12

First public release. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0)

[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/shinyaoguri/metaphor/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/shinyaoguri/metaphor/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/shinyaoguri/metaphor/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/shinyaoguri/metaphor/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/shinyaoguri/metaphor/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/shinyaoguri/metaphor/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/shinyaoguri/metaphor/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/shinyaoguri/metaphor/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/shinyaoguri/metaphor/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/shinyaoguri/metaphor/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/shinyaoguri/metaphor/compare/v0.2.4...v0.3.0
[0.2.4]: https://github.com/shinyaoguri/metaphor/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/shinyaoguri/metaphor/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/shinyaoguri/metaphor/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/shinyaoguri/metaphor/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/shinyaoguri/metaphor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0
