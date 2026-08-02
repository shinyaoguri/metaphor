# metaphor

**English** | [日本語](README.md)

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-DocC-8A2BE2)](https://shinyaoguri.github.io/metaphor/documentation/metaphor/)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**The feel of Processing × Apple Silicon native × an AI that creates while observing "what's on screen right now".**

`metaphor` is a Swift + Metal creative coding runtime. Write `setup()` / `draw()` and a window opens. One continuous API covers 2D / 3D rendering, GPU compute, post-effects, audio & video, OSC / MIDI, Core ML, ray tracing, and Syphon output. And with **Probe + live viewer + local MCP**, an AI agent can observe rendering results and internal state, building the same artwork together with you.

<table>
  <tr>
    <td align="center"><a href="Examples/Topics/Fractals%20and%20L-Systems/Tree"><img src="Examples/Topics/Fractals%20and%20L-Systems/Tree/Tree.png" alt="Tree" width="270"></a><br><sub>Fractal Tree</sub></td>
    <td align="center"><a href="Examples/Topics/Cellular%20Automata/GameOfLife"><img src="Examples/Topics/Cellular%20Automata/GameOfLife/GameOfLife.png" alt="Game of Life" width="270"></a><br><sub>Game of Life</sub></td>
    <td align="center"><a href="Examples/Basics/Lights/Mixture"><img src="Examples/Basics/Lights/Mixture/Mixture.png" alt="3D Lights" width="270"></a><br><sub>3D Lights (Blinn-Phong)</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="Examples/Topics/Fractals%20and%20L-Systems/Mandelbrot"><img src="Examples/Topics/Fractals%20and%20L-Systems/Mandelbrot/Mandelbrot.png" alt="Mandelbrot" width="270"></a><br><sub>Mandelbrot</sub></td>
    <td align="center"><a href="Examples/Topics/Drawing/Pattern"><img src="Examples/Topics/Drawing/Pattern/Pattern.png" alt="Pattern" width="270"></a><br><sub>Generative Pattern</sub></td>
    <td align="center"><a href="Examples/Topics/Simulate/Flocking"><img src="Examples/Topics/Simulate/Flocking/Flocking.png" alt="Flocking" width="270"></a><br><sub>Flocking</sub></td>
  </tr>
</table>

```swift
import metaphor

@main
final class Hello: Sketch {
    var config: SketchConfig { SketchConfig(width: 800, height: 600) }

    func draw() {
        background(13)
        fill(255, 102, 51)
        circle(mouseX, mouseY, 120)
    }
}
```

## Get started in 60 seconds

```bash
brew install shinyaoguri/tap/metaphor   # Install CLI
metaphor new MySketch                   # Create a sketch from template
cd MySketch
metaphor run                            # Resolve, build, and launch all at once
```

Replace `metaphor run` with `metaphor watch` to rebuild on every file save while keeping the live viewer window open. The CLI (installation methods, all commands, templates) is provided by **[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli)**. If you want to use only the library without the CLI, see [SwiftPM as a dependency](#swiftpm-as-a-dependency).

## Why metaphor?

1. **AI can fix "what's on screen right now" while looking at the rendered frame.** Most LLMs can only read source code, but metaphor's Probe plugin writes frame images and internal state, and `metaphor mcp` passes them to AI agents as MCP tools. AI can run **observe → edit → re-observe → verify** loops on its own—the differentiation isn't Swift/Metal itself, but this observation loop. → [Collaborating with AI](#collaborating-with-ai-observation--manipulation--iteration)
2. **Processing's feel, Metal's speed.** Laying out circles automatically batches them into **GPU instancing** (10,000 circles = 1 draw call). A million-particle GPU particle system is one line: `createParticleSystem`. Vocabulary like `fill` / `push` / `translate` feels the same in 2D and 3D.
3. **All of Apple's graphics frameworks included, end-to-end.** Metal / MPS (including ray tracing) / Core ML & Vision / Core Image / AVFoundation / GameplayKit Noise / Core MIDI / Syphon—all available through one unified API from a single `Sketch`. Includes shader hot-reload, OSC / MIDI, Performance HUD for live/VJ work, and video / GIF / still-image export plus deterministic rendering (fixed-FPS high-res baking).

## Capabilities

| Domain | Key Features |
|---|---|
| 2D Drawing | Primitives, paths, concave polygons (with holes), text, images, blend modes |
| 3D Drawing | Primitives / custom meshes / OBJ·USDZ·ABC loaders, camera, lights (PBR + Blinn-Phong), shadow maps |
| GPU Compute | Custom MSL kernels, indirect draw, 1M-particle GPU particles |
| Post-process | Bloom, blur, edge detect, custom MSL shaders, FBO feedback |
| Audio | Mic input, FFT, beat detection, sound file playback |
| Video | Camera input, video playback, video / GIF export |
| Input | OSC, MIDI input & output, mouse, keyboard, orbit camera |
| ML | Core ML, Vision (classification / detection / pose / segmentation / OCR / face, etc.) |
| Advanced | RenderGraph, SceneGraph, 2D physics, Syphon output, MPS ray tracing |

## Your first sketch

The `App.swift` generated by `metaphor new` follows Processing's model: initialize in `setup`, call `draw` every frame.

```swift
import metaphor

@main
final class MySketch: Sketch {
    // Window size, title, and other configuration
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "MySketch")
    }

    // Called once at startup
    func setup() {
        // Initialization & resource loading
    }

    // Called every frame
    func draw() {
        background(13)
        fill(255, 102, 51)
        circle(mouseX, mouseY, 96)
    }
}
```

| Lifecycle | Called when |
|---|---|
| `setup()` | Once at startup |
| `compute()` | Every frame, before `draw` (for GPU compute) |
| `draw()` | Every frame |
| `mousePressed()` / `mouseDragged()` / `mouseScrolled()`, etc. | Mouse events |
| `keyPressed()` / `keyReleased()` | Keyboard events |

Use `noLoop()` to draw one frame and stop, `loop()` to resume, and `frameRate(n)` to specify FPS.

### Common functions

```swift
// --- 2D shapes
circle(x, y, diameter)
rect(x, y, w, h)
line(x1, y1, x2, y2)
triangle(x1, y1, x2, y2, x3, y3)
arc(x, y, w, h, start, stop)
text("hello", x, y)

// --- 3D shapes
box(size)
sphere(radius)
plane(w, h)
cylinder(radius: 0.5, height: 1)
torus(ringRadius: 0.5, tubeRadius: 0.2)

// --- Style (color defaults to 0–255, same as Processing; can be changed with colorMode)
background(r, g, b)
fill(r, g, b);  fill(gray)
stroke(r, g, b); strokeWeight(2)
noFill();  noStroke()
blendMode(.additive)

// --- Transforms (push/pop for stack)
push()
translate(x, y);  translate(x, y, z)
rotate(angle);    rotateX(a); rotateY(a); rotateZ(a)
scale(s)
pop()

// --- State / Utilities
mouseX, mouseY, frameCount, deltaTime, width, height
random(0, 1);  noise(x, y);  map(v, 0, 1, 100, 200)
```

The full API is in [`llms.txt`](llms.txt). To browse types and methods, see the **[API reference (DocC)](https://shinyaoguri.github.io/metaphor/documentation/metaphor/)** ([project site](https://shinyaoguri.github.io/metaphor/)). When hunting for "the Processing equivalent of X," [Examples](#examples) has quick answers.

Coming from Processing or p5.js? Start with **[docs/processing-migration-guide.md](docs/processing-migration-guide.md)** — API mapping tables by category (`size()` → `SketchConfig`, `PVector` → `Vec2`, `rectMode(CENTER)` → `rectMode(.center)`, …), the pitfalls that bite (value vs. reference types, `@MainActor`, the two color ranges, the 2D/3D transform split), and what is not implemented yet.

## Collaborating with AI (observation → manipulation → iteration)

metaphor is designed so AI agents can develop while **observing a running sketch**. Register `metaphor mcp` as an MCP server with your AI client (Claude Code / Cursor, etc.), and the agent can fetch rendering results and internal state, verify rebuild outcomes, and autonomously iterate through "observe → edit → re-observe → verify" cycles.

| Tool | Role |
|---|---|
| `snapshot` | Returns image (PNG) and internal state of the current frame (`frameCount` / `time` / `probe()` values / color & region stats / warnings) |
| `capture_sequence` | Captures a sequence of frames, returns contact sheet image and per-frame manifest (observe motion / rhythm / transitions) |
| `input` | Sends mouse & keyboard input to the running sketch |
| `build_status` | Returns success/failure and errors from the most recent `swift build` |
| `api_reference` | Returns metaphor API documentation (usage guide / all APIs / sample index). Consult before using new APIs |

When a human runs `metaphor watch`, the AI's `metaphor mcp` **attaches to the same running sketch** (shared session). The human edits while watching the live viewer; AI cooperates via file edits and `snapshot`.

The observation mechanism itself is metaphor's **Probe** plugin. To pass internal state to AI, declare it in `draw()` like `probe("count", n)` (example: [`Examples/Samples/ProbeSnapshot`](Examples/Samples/ProbeSnapshot)).

We've also included static context to help **AI write metaphor-style code**.

- [`llms-sketch.txt`](llms-sketch.txt) — Compact AI context for sketch authors. How to write `setup()` / `draw()`, common APIs, operations to avoid.
- [`llms.txt`](llms.txt) — Full API reference in one file for LLMs. **Paste it into your AI's context** and it will write metaphor code in proper style.
- [`docs/ai/`](docs/ai/) — [Guide for sketch authors](docs/ai/for-sketch-authors.md), [sample index](docs/ai/examples-index.md), [prompts by use case](docs/ai/prompts/), [how it works across install scenarios](docs/ai/install-scenarios.md).

Setup instructions (`claude mcp add` / `.mcp.json`) and shared-session workflows are in **[metaphor-cli's "Collaborating with AI"](https://github.com/shinyaoguri/metaphor-cli#collaborating-with-ai)**. Design rationale is in [docs/design/ai-mcp-server.md](docs/design/ai-mcp-server.md) / [docs/design/shared-session.md](docs/design/shared-session.md).

## Examples

[Examples/](Examples/) includes 270+ samples: Processing's official examples ported to Swift / Metal, plus metaphor-specific showcases. Each sample is a standalone SwiftPM package.

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

- [Basics/](Examples/Basics/) — Processing standard examples ported (Form / Color / Image / Lights / Math / Transform …)
- [Topics/](Examples/Topics/) — Topic-organized (Curves / Shaders / Simulate / Fractals / GUI, etc.)
- [Demos/](Examples/Demos/) — Performance-focused demos
- [Samples/](Examples/Samples/) — metaphor-specific (RayTracing / SceneGraph / Syphon / Plugins / Probe, etc.)
- [ML/](Examples/ML/) — Vision / CoreML integration

To find "what you want to do," [docs/ai/examples-index.md](docs/ai/examples-index.md) (all samples with tags and difficulty) is handy.

## Comparison with other tools

In one sentence, metaphor's niche is **"Processing's feel × Apple Silicon native × AI observes, manipulates, and iterates"**. By targeting macOS, we fill a gap between web and game engines, and node-based VJ tools: a code-first runtime where AI can collaborate.

- **vs Processing / p5.js** — Same `setup` / `draw` feel. Instead, you get native Metal GPU compute, PBR, Core ML, and million-particle loads. Cross-platform is their strength.
- **vs openFrameworks** — Swift and SPM make dependency resolution and builds fast; Metal is first-class. Win / Linux and C++ addon libraries favor openFrameworks.
- **vs Unity** — Code-first, run from a single `App.swift` immediately, no license fee. Full game development and editor GUI need Unity.
- **vs TouchDesigner** — Version-controlled code base friendly to AI development workflows. Node-based for improvisation and non-programmer collaboration favors TouchDesigner.

**Choose metaphor if**: collaborating with AI on artwork / building on macOS / unlocking Apple Silicon performance (Metal·Core ML·MPS·Syphon) / live performance with Syphon·OSC·MIDI.

**Not a fit if**: Windows·Linux·mobile·Web target / node-based improvisation / full-featured game development.

## SwiftPM as a dependency

You can also add `metaphor` as a normal Swift Package dependency without the CLI (e.g., embedding in Xcode or existing projects).

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.8.0"),
]
```

On the target side:

```swift
.executableTarget(
    name: "MySketch",
    dependencies: [.product(name: "metaphor", package: "metaphor")]
)
```

The library fully works this way (you can even generate code via AI with `llms.txt`). But the MCP loop that lets AI observe "what's on screen right now" needs the CLI (`metaphor mcp`). We recommend `metaphor new` for first-time use—`Package.swift`, templates, resource directories, AI guides, and update paths come built-in.

## Requirements

- Apple Silicon Mac
- macOS 14.0+
- Xcode 15.4+ / Swift 5.10+ (minimum supported; CI validates builds with Xcode 15.4 on every PR. When GitHub Actions retires the macos-14 runner and CI can no longer verify, we'll consider raising the minimum.)

## Troubleshooting

If you have [metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) installed, run `metaphor doctor` first — it checks your Swift/Xcode versions, template availability, and whether `Syphon.framework` loaded, which covers the most common setup problems in one shot.

- **It won't build or run on my Intel Mac** — metaphor targets **Apple Silicon only** (see [Requirements](#requirements)); there's no Intel code path and none is planned. `swift build` isn't gated against Intel at the package-manifest level, so it may appear to build, but running is untested and unsupported — expect Metal feature or performance failures at runtime rather than a clean build error.
- **`swift build` / `swift run` fails while resolving dependencies** (a checksum mismatch, "unable to download", or a 404 fetching `Syphon.xcframework.zip`) — The `Syphon` binary target is fetched from a pinned GitHub Release asset URL in `Package.swift`. Try clearing SwiftPM's cache and re-resolving: `swift package purge-cache && swift build` (or delete `.build` in your sketch's directory). If that doesn't help, check whether something between you and `github.com` (a corporate proxy or firewall) is blocking the release asset download — published tags and their assets are protected and health-checked weekly, so a 404 on a current release would be a bug worth [reporting](#feedback--issue-reports).
- **`make build` fails / Syphon.xcframework is missing** — On first run, execute `make setup` to initialize submodules and build Syphon.xcframework. Check status with `make check`.
- **Live viewer (`metaphor watch`) is black** — That's a CLI issue. See [metaphor-cli Troubleshooting](https://github.com/shinyaoguri/metaphor-cli#troubleshooting).
- **Can't observe "what's on screen" from AI** — Verify `metaphor watch` is running and `metaphor mcp` is executing in the same directory.
- **Microphone or camera doesn't work, or the permission dialog never appeared** — See [docs/permissions.md](docs/permissions.md) for how TCC permissions work for a `swift run` binary (the dialog is attributed to your terminal app, not your sketch) and how to recover from a denied prompt.
- **`llms.txt` is stale / CI says stale** — After changing public APIs, run `make llms-txt` and commit. Pre-push hooks and CI verify freshness.

## Feedback / Issue reports

metaphor is still evolving. If you spot bugs or ideas for improvement, **please report or propose them in [Issues](https://github.com/shinyaoguri/metaphor/issues), no matter how small**. Feedback like "this doc explanation is unclear" or "the error message should be friendlier" is also welcome.

Bug reports are most helpful with:

- Environment (macOS / Xcode / Swift versions, output of `metaphor doctor` if available)
- Reproduction steps or minimal sketch code (ideally reproduces in one of the [Examples/](Examples/))
- Expected vs. actual behavior

Problems with the CLI (`metaphor new` / `metaphor watch` / MCP, etc.) belong in [metaphor-cli Issues](https://github.com/shinyaoguri/metaphor-cli/issues). When in doubt, file here and we'll route it appropriately.

If using through an AI agent, same process—ask the agent to "report this as a GitHub Issue with repro steps," and it can file with full details.

## Library development

Library development (setup, testing, Syphon.xcframework handling, generated-file management, release procedure) is in [DEVELOPMENT.md](DEVELOPMENT.md). For the full documentation map, see [docs/README.en.md](docs/README.en.md). When maintaining with an AI agent, start at [CLAUDE.md](CLAUDE.md).

## Acknowledgements

Most samples in [Examples/](Examples/) are Swift / Metal ports of [Processing](https://processing.org/) sample sketches (public domain) by Casey Reas, Ben Fry, and Daniel Shiffman. See individual file headers for attribution.

- Processing: https://processing.org/
- Processing examples: https://github.com/processing/processing-examples

For the copyright notice and full license text of `Syphon.xcframework`
(Simplified BSD License), redistributed as a GitHub Release asset, see
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
