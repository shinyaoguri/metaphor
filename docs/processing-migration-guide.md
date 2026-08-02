# Processing → metaphor migration guide

For people who already write Processing (or p5.js) sketches and want to know what
changes — and what does not — when the same sketch is written against
[metaphor](../README.en.md).

The short version: **the drawing vocabulary is deliberately the same**. `setup()` /
`draw()`, `background()`, `fill()`, `rect()`, `map()`, `noise()`, `mouseX` and the
0–255 color range all mean what you expect. What changes is the language around
them (Swift instead of Java), a handful of names that Swift's type system lets us
make safer (`rectMode(CENTER)` → `rectMode(.center)`), and a short list of
Processing APIs that do not exist yet.

Naming follows [ADR-0007](adr/0007-finalize-public-api-surface.md): *where
Processing or p5.js has a matching word, the Sketch layer keeps Processing's name
and argument order; APIs with no Processing counterpart follow the Swift API
Design Guidelines.* That is why `noFill()` and `loadJSON(_:as:)` sit next to each
other, and it is the rule to predict any name this page does not list.

> Every metaphor API named here was checked against the implementation, and every
> call form was compiled against the library before this page shipped. If you find
> a row that no longer matches, please
> [open an issue](https://github.com/shinyaoguri/metaphor/issues/new/choose) —
> a wrong mapping table is worse than no mapping table.
>
> The canonical signature list is [`llms.txt`](../llms.txt). This page is the
> translation layer on top of it.

## Contents

- [The shape of a sketch](#the-shape-of-a-sketch)
- [API mapping](#api-mapping)
  - [Structure and lifecycle](#structure-and-lifecycle)
  - [Shape](#shape)
  - [Color](#color)
  - [Transform](#transform)
  - [Typography](#typography)
  - [Image](#image)
  - [Pixels](#pixels)
  - [3D, lighting, camera, material](#3d-lighting-camera-material)
  - [Input](#input)
  - [Math, random, noise](#math-random-noise)
  - [Vectors: PVector → Vec2 / Vec3](#vectors-pvector--vec2--vec3)
  - [Data](#data)
  - [Output and export](#output-and-export)
  - [Constants](#constants)
  - [Types: PImage, PGraphics, PShape, PVector](#types-pimage-pgraphics-pshape-pvector)
- [Pitfalls](#pitfalls)
- [Not available yet](#not-available-yet)
- [Where to look next](#where-to-look-next)

## The shape of a sketch

Processing:

```java
void setup() {
  size(640, 360);
}

void draw() {
  background(0);
  fill(255);
  ellipse(mouseX, mouseY, 80, 80);
}
```

metaphor:

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "MySketch")
    }

    func setup() {
        // once, after the canvas exists
    }

    func draw() {
        background(0)
        fill(255)
        ellipse(mouseX, mouseY, 80, 80)
    }
}
```

Three structural differences, and nothing else:

1. **A sketch is a class**, marked `@main`, conforming to `Sketch`. Sketch state
   that Processing would keep in globals becomes stored properties on that class.
2. **`size()` moves into `config`.** `SketchConfig` is Processing's `settings()`
   block — canvas size, title, target frame rate, MSAA, fullscreen — declared
   once instead of called imperatively. (See
   [Structure and lifecycle](#structure-and-lifecycle) for `createCanvas` if you
   prefer the p5.js style.)
3. **`draw()` is required; everything else is optional.** `setup()`, the mouse and
   key callbacks, and `compute()` all have default no-op implementations, so
   implement only the ones you use.

## API mapping

Only the `Sketch`-layer surface is listed — that is the layer you write sketches
against, and it is the documentation canon under
[ADR-0005](adr/0005-sketch-api-consistency.md). Everything here is a method on
your sketch class (so it is callable bare inside `setup()` / `draw()`), except the
free functions noted as such.

### Structure and lifecycle

| Processing | metaphor | Notes |
|---|---|---|
| `void setup()` | `func setup()` | Optional. |
| `void draw()` | `func draw()` | The only required method. |
| `settings()` / `size(w, h)` | `var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "…") }` | Declarative. Also carries `fps`, `msaa`, `fullScreen`, `windowScale`, `syphon`, `plugins`. |
| `size(w, h)` in p5.js style | `createCanvas(width: 640, height: 360)` | Call from `setup()`. |
| `fullScreen()` | `SketchConfig(…, fullScreen: true)` | No function form. |
| `smooth()` / `noSmooth()` | `SketchConfig(…, msaa: 4)` | MSAA sample count; default `4`. `msaa: 1` disables it. |
| `frameRate(60)` | `frameRate(60)` | Setter only — see [Pitfalls](#pitfalls). |
| `frameRate` (the variable) | — | Not implemented ([#273](https://github.com/shinyaoguri/metaphor/issues/273)). |
| `frameCount` | `frameCount: Int` | |
| `millis()` | `millis() -> Int` | Free function. |
| `width` / `height` | `width: Float` / `height: Float` | `Float`, not `int`. |
| `noLoop()` / `loop()` | `noLoop()` / `loop()` | `noLoop()` works from inside `setup()`. |
| `redraw()` | `redraw()` | Renders one frame **synchronously**, rather than scheduling one. |
| `looping` | `isLooping: Bool` | |
| — | `func compute()` | metaphor addition: runs before `draw()` each frame, for GPU compute. |
| `windowResized()` | — | Not implemented; the window is aspect-locked and `width`/`height` never change on their own. |
| `exit()` | — | Not implemented — call `NSApp.terminate(nil)` yourself. |
| `delay()` | — | Not implemented (and undesirable on the main actor). |
| `pixelDensity()` | — | Not implemented; the offscreen texture size is `SketchConfig.width`/`height` and `windowScale` decides how large the window is. |

### Shape

| Processing | metaphor |
|---|---|
| `point(x, y)` | `point(x, y)` |
| `line(x1, y1, x2, y2)` | `line(x1, y1, x2, y2)` |
| `triangle(…)` / `quad(…)` | `triangle(x1, y1, x2, y2, x3, y3)` / `quad(x1, y1, x2, y2, x3, y3, x4, y4)` |
| `rect(x, y, w, h)` | `rect(x, y, w, h)`, plus `rect(x, y, w, h, r)` and `rect(x, y, w, h, tl, tr, br, bl)` |
| `square(x, y, s)` | `square(x, y, size)` |
| `ellipse(x, y, w, h)` | `ellipse(x, y, w, h)` |
| `circle(x, y, d)` | `circle(x, y, diameter)` |
| `arc(x, y, w, h, start, stop)` | `arc(x, y, w, h, startAngle, stopAngle, mode: ArcMode = .default)` |
| `arc(…, PIE / CHORD / OPEN)` | `arc(…, .pie)` / `.chord` / `.open` |
| `bezier(…)` | `bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)` |
| `curve(…)` | `curve(x1, y1, x2, y2, x3, y3, x4, y4)` |
| `beginShape()` / `endShape()` | `beginShape(_ mode: ShapeMode = .polygon)` / `endShape(_ close: CloseMode = .open)` |
| `endShape(CLOSE)` | `endShape(.close)` |
| `beginShape(TRIANGLES)` etc. | `beginShape(.triangles)`, `.triangleStrip`, `.triangleFan`, `.lines`, `.points`, `.polygon` |
| `vertex(x, y)` / `vertex(x, y, u, v)` | `vertex(x, y)` / `vertex(x, y, u, v)`, plus `vertex(x, y, color)` |
| `bezierVertex(…)` / `curveVertex(x, y)` | `bezierVertex(cx1, cy1, cx2, cy2, x, y)` / `curveVertex(x, y)` |
| `quadraticVertex(…)` | — not implemented |
| `beginContour()` / `endContour()` | `beginContour()` / `endContour()` |
| `curveDetail()` / `curveTightness()` | `curveDetail(_ n: Int)` / `curveTightness(_ t: Float)` |
| `rectMode(CORNER/CORNERS/CENTER/RADIUS)` | `rectMode(.corner)` / `.corners` / `.center` / `.radius` — default `.corner` |
| `ellipseMode(…)` | `ellipseMode(.center)` / `.radius` / `.corner` / `.corners` — default `.center` |
| `strokeWeight(w)` | `strokeWeight(_ weight: Float)` |
| `strokeCap(ROUND)` / `strokeCap(SQUARE)` / `strokeCap(PROJECT)` | `strokeCap(.round)` (default) / `strokeCap(.butt)` / `strokeCap(.square)` — **watch the middle one**: metaphor's `.square` extends past the endpoint (Processing's `PROJECT`), and Processing's `SQUARE` is `.butt` |
| `strokeJoin(MITER/BEVEL/ROUND)` | `strokeJoin(.miter)` / `.bevel` / `.round` — default `.miter` |
| `clip(a, b, c, d)` / `noClip()` | `beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float)` / `endClip()` |
| `createShape()` / `PShape` | `createShape() -> MShape`, `createShape(_ kind: ShapeKind) -> MShape` |
| `shape(s, x, y)` | `shape(_ s: MShape, _ x: Float, _ y: Float)` (also `shape(s)` and `shape(s, x, y, w, h)`) |
| `loadShape("f.svg")` | — not implemented ([#288](https://github.com/shinyaoguri/metaphor/issues/288)) |

### Color

The default color mode is **RGB with a 0–255 range, exactly like Processing**, so
`fill(255, 102, 51)` and `background(13)` port unchanged.

| Processing | metaphor |
|---|---|
| `background(0)` / `background(r, g, b)` | `background(_ gray: Float)` / `background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil)` |
| `fill(g)` / `fill(g, a)` / `fill(r, g, b)` / `fill(r, g, b, a)` | `fill(_ gray:)`, `fill(_ gray:_ alpha:)`, `fill(_ v1:_ v2:_ v3:_ a:)` |
| `stroke(…)` | `stroke(…)` — same overload set as `fill` |
| `noFill()` / `noStroke()` | `noFill()` / `noStroke()` |
| `colorMode(RGB, 255)` | `colorMode(.rgb, 255)` |
| `colorMode(HSB, 360, 100, 100)` | `colorMode(.hsb, 360, 100, 100)` |
| `color(r, g, b)` (a `color` value) | `Color(r: 1, g: 0.4, b: 0.2)` — components are **0–1** and ignore `colorMode` |
| `#FF8844` literal | `Color(hex: 0xFF8844)` or `Color(hex: "#FF8844")` |
| `lerpColor(c1, c2, t)` | `lerpColor(_ c1: Color, _ c2: Color, _ t: Float) -> Color` (free function) |
| `color(…)` packed into `pixels[]` | `color(_ r: Float, _ g: Float, _ b: Float) -> UInt32` (free function, 0–255 in, packed `0xAARRGGBB` out) |
| `tint(…)` / `noTint()` | `tint(…)` (same overloads as `fill`) / `noTint()` |
| `blendMode(ADD)` | `blendMode(.additive)`; also `.alpha` `.multiply` `.screen` `.subtract` `.darkest` `.lightest` `.difference` `.exclusion` `.opaque` |
| `red(c)` / `green(c)` / `hue(c)` … | `c.r` / `c.g` — no `hue()`/`saturation()`/`brightness()` extractors |

Note the two distinct color entry points — see
[Two color ranges](#two-color-ranges-0255-numbers-01-color) in the pitfalls.

### Transform

| Processing | metaphor | Applies to |
|---|---|---|
| `pushMatrix()` / `popMatrix()` | `pushMatrix()` / `popMatrix()` | transform only, 2D **and** 3D |
| `push()` / `pop()` | `push()` / `pop()` | transform **and** style, 2D and 3D |
| `pushStyle()` / `popStyle()` | `pushStyle()` / `popStyle()` | style only, 2D and 3D |
| `translate(x, y)` | `translate(_ x: Float, _ y: Float)` | 2D and 3D |
| `translate(x, y, z)` | `translate(_ x: Float, _ y: Float, _ z: Float)` | 3D only |
| `rotate(a)` | `rotate(_ angle: Float)` | 2D and 3D (z-axis on 3D) |
| `rotateX/Y/Z(a)` | `rotateX(_:)` / `rotateY(_:)` / `rotateZ(_:)` | 3D only |
| `scale(s)` | `scale(_ s: Float)` | 2D and 3D |
| `scale(sx, sy)` | `scale(_ sx: Float, _ sy: Float)` | 2D and 3D (z unscaled) |
| `scale(sx, sy, sz)` | `scale(_ x: Float, _ y: Float, _ z: Float)` | 3D only |
| `shearX(a)` / `shearY(a)` | `shearX(_ angle: Float)` / `shearY(_ angle: Float)` | 2D only |
| `applyMatrix(n00…n12)` | `applyMatrix(_ n00: Float, …, _ n12: Float)` (6 components, row-major, Processing-compatible) | 2D only |
| `applyMatrix(PMatrix2D)` | `applyMatrix(_ matrix: float3x3)` | 2D only |
| `applyMatrix(PMatrix3D)` | `applyMatrix(_ matrix: float4x4)` | 3D only |
| `resetMatrix()` | `resetMatrix()` | 2D and 3D |
| `printMatrix()` | — not implemented | |
| `screenX(x, y)` / `screenY(x, y)` | `screenX(_ x: Float, _ y: Float) -> Float`, `screenY(…)`; 3D overloads take `(x, y, z)` | |
| `screenZ(x, y, z)` | `screenZ(_ x: Float, _ y: Float, _ z: Float) -> Float` (normalized depth 0…1) | |
| `modelX/Y/Z(…)` | — not implemented (ADR-0007 follow-up) | |

Angles are **radians** everywhere, as in Processing. There is no `angleMode()`
(that is a p5.js API) — use `radians(deg)` to convert.

### Typography

| Processing | metaphor |
|---|---|
| `text("hi", x, y)` | `text(_ string: String, _ x: Float, _ y: Float)` |
| `text("hi", x, y, w, h)` | `text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float)` |
| `textSize(32)` | `textSize(_ size: Float)` |
| `textFont(f)` with a `PFont` | `textFont(_ family: String)` — an installed font **family name**, e.g. `textFont("Helvetica Neue")` |
| `createFont(…)` / `loadFont(…)` | — not implemented; there is no `PFont` type |
| `textAlign(CENTER, TOP)` | `textAlign(.center, .top)` — `TextAlignH` is `.left/.center/.right`, `TextAlignV` is `.top/.center/.baseline/.bottom` (default `.baseline`) |
| `textLeading(l)` | `textLeading(_ leading: Float)` |
| `textWidth(s)` | `textWidth(_ string: String) -> Float` |
| `textAscent()` / `textDescent()` | `textAscent() -> Float` / `textDescent() -> Float` |

### Image

| Processing | metaphor |
|---|---|
| `PImage` | `MImage` |
| `loadImage("a.png")` | `loadImage(_ path: String, cache: Bool = true) throws -> MImage` |
| `requestImage(…)` | `loadImageAsync(_ path: String, cache: Bool = true) async throws -> MImage` |
| `createImage(w, h, ARGB)` | `createImage(_ width: Int, _ height: Int) -> MImage?` |
| `image(img, x, y)` | `image(_ img: MImage, _ x: Float, _ y: Float)` |
| `image(img, x, y, w, h)` | `image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float)` |
| p5.js `image(img, dx, dy, dw, dh, sx, sy, sw, sh)` | same shape — `image(_ img: MImage, _ dx:_ dy:_ dw:_ dh:_ sx:_ sy:_ sw:_ sh:)`, for sprite sheets and tile maps |
| `imageMode(CORNER/CENTER/CORNERS)` | `imageMode(.corner)` / `.center` / `.corners` — default `.corner` |
| `copy(sx, sy, sw, sh, dx, dy, dw, dh)` | `copy(_ sx:_ sy:_ sw:_ sh:_ dx:_ dy:_ dw:_ dh:)` — reads the offscreen target's **previous** contents, not this frame's drawing so far |
| `filter(BLUR, 4)` on the canvas | `filter(_ image: MImage, _ type: FilterType)` — applies to an image; `FilterType` covers `.blur(4)`, `.gray`, `.invert`, `.threshold(0.5)`, `.posterize(4)`, `.dilate`, `.erode`, `.sharpen(1)`, `.sepia`, `.pixelate(8)`, `.edgeDetect`, plus MPS-accelerated variants |
| `img.get(x, y)` / `img.set(x, y, c)` | `MImage.get(_ x: Int, _ y: Int) -> Color` / `MImage.set(_ x: Int, _ y: Int, _ color: Color)` |
| `img.resize(w, h)` | `MImage.resize(_ width: Int, _ height: Int)` |
| `img.mask(m)` | `MImage.mask(_ maskImage: MImage)` |
| `blend(…)` | — not implemented |
| `createGraphics(w, h)` / `PGraphics` | `createGraphics(_ w: Int, _ h: Int) -> Graphics?`, plus `createGraphics3D(_:_:) -> Graphics3D?` |
| `pg.beginDraw()` / `pg.endDraw()` | `Graphics.beginDraw()` / `Graphics.endDraw(wait: Bool = false)`; draw it with `image(pg, x, y)` |

### Pixels

| Processing | metaphor |
|---|---|
| `loadPixels()` | `loadPixels()` |
| `pixels[y * width + x]` | `pixels[y * Int(width) + x]` — `pixels` is `UnsafeMutableBufferPointer<UInt32>` |
| `color(r, g, b)` written into `pixels[]` | `color(_ r: Float, _ g: Float, _ b: Float) -> UInt32` (free function, 0–255 components) |
| `updatePixels()` | `updatePixels()` |
| `img.loadPixels()` / `img.pixels` | `MImage.loadPixels()` / `MImage.pixels: [UInt8]` — **RGBA bytes**, a different layout from the canvas buffer |

The packed value is `(A << 24) | (R << 16) | (G << 8) | B` — the same
`0xAARRGGBB` integer a Processing sketch manipulates, so tricks like
`pixels[i] ^= 0x00FF_FFFF` (invert, keep alpha) port directly. See
[loadPixels() splits the render pass](#loadpixels-splits-the-render-pass).

### 3D, lighting, camera, material

metaphor's 3D canvas keeps Processing's `P3D` conventions: **pixel coordinates,
origin at the top-left, +Y downward**, and the same default camera Processing
uses — eye at `(width/2, height/2, (height/2)/tan(fov/2))` looking at
`(width/2, height/2, 0)` with a 60° vertical field of view, near and far at
`eyeZ/10` and `eyeZ*10`. So `box(100)` is 100 pixels across and sits at the canvas
center by default, exactly as in Processing, and a `P3D` sketch's coordinates port
over unchanged. `Examples/Basics/Form/Primitives3D` is a literal transcription of
the Processing original with every number left alone.

| Processing | metaphor |
|---|---|
| `box(s)` / `box(w, h, d)` | `box(_ size: Float)` / `box(_ width: Float, _ height: Float, _ depth: Float)` |
| `sphere(r)` | `sphere(_ radius: Float, detail: Int = 24)` |
| `sphereDetail(n)` | — use the `detail:` argument of `sphere(_:detail:)` |
| — | `plane(_ width: Float, _ height: Float)`, `cone(radius:height:detail:)`, `cylinder(radius:height:detail:)`, `torus(ringRadius:tubeRadius:detail:)` — sizes are required arguments (no defaults), and like `box` / `sphere` they are pixel sizes under the default camera |
| `camera(ex, ey, ez, cx, cy, cz, ux, uy, uz)` | `camera(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0))` |
| `perspective(fov, aspect, near, far)` | `perspective(fov: Float = .pi / 3, near: Float = 0.1, far: Float = 10000)` — aspect comes from the canvas |
| `ortho(l, r, b, t)` | `ortho(left:right:bottom:top:near:far:)` — every plane optional, defaulting to the canvas box |
| `beginCamera()` / `endCamera()` / `frustum()` | — not implemented |
| `lights()` / `noLights()` | `lights()` / `noLights()` — `lights()` **clears** the light list first, then installs one directional plus ambient, so call it before your own lights, not after |
| `ambientLight(r, g, b)` | `ambientLight(_ r: Float, _ g: Float, _ b: Float)`, plus `ambientLight(_ strength: Float)` |
| `directionalLight(r, g, b, nx, ny, nz)` | `directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color)` — **direction first, color as a labelled argument** |
| `pointLight(r, g, b, x, y, z)` | `pointLight(_ x: Float, _ y: Float, _ z: Float, color: Color = .white, falloff: Float = 0.1)` — **position first** |
| `spotLight(…)` | `spotLight(_ x:_ y:_ z:_ dirX:_ dirY:_ dirZ:, angle:falloff:color:)` |
| `lightFalloff()` / `lightSpecular()` | — use the `falloff:` / `color:` arguments on the individual lights |
| `specular(…)` / `shininess(n)` / `emissive(…)` | `specular(_ color: Color)` (also grayscale) / `shininess(_ value: Float)` / `emissive(_ color: Color)` |
| `ambient(…)` | — not implemented as a per-material call (only scene-wide `ambientLight`) |
| — | `metallic(_:)`, `roughness(_:)`, `ambientOcclusion(_:)`, `pbr(_ enabled: Bool)` for the PBR path. `roughness(_:)` switches the whole shading model to PBR as a side effect |
| `texture(img)` / `noTexture()` | `texture(_ img: MImage)` / `noTexture()` |
| `textureMode()` / `textureWrap()` | — not implemented |
| `normal(nx, ny, nz)` | `normal(_ nx: Float, _ ny: Float, _ nz: Float)` |
| `beginShape()` in 3D | `beginShape3D(_ mode: ShapeMode = .polygon)` / `endShape3D(_ close: CloseMode = .open)` |
| `loadShape("m.obj")` | `loadModel(_ path: String, normalize: Bool = true, cache: Bool = true) -> Mesh?` (OBJ / USDZ / ABC), drawn with `mesh(_:)` |
| `hint(ENABLE_DEPTH_TEST)` etc. | — no `hint()`; the closest switch is `pbr(_:)` |
| — | `enableShadows(resolution: Int = 2048)` / `disableShadows()` / `shadowBias(_:)`, `orbitControl()`, `orbitCamera` |

At most **8 lights** are active at once; further `pointLight` / `spotLight` /
`directionalLight` calls in a frame are dropped silently.

### Input

| Processing | metaphor |
|---|---|
| `mouseX` / `mouseY` | `mouseX: Float` / `mouseY: Float` |
| `pmouseX` / `pmouseY` | `pmouseX: Float` / `pmouseY: Float` |
| `mousePressed` (the boolean) | `isMousePressed: Bool` |
| `mousePressed()` (the callback) | `func mousePressed()` |
| `mouseReleased()` / `mouseMoved()` / `mouseDragged()` / `mouseClicked()` | same names, all `func …()` with no parameters |
| `mouseWheel(event)` | `func mouseScrolled()` + `scrollX: Float` / `scrollY: Float` |
| `mouseButton == LEFT` | `mouseButton == .left` (`MouseButton?` — `.left` / `.right` / `.middle`, `nil` until the first press) — see [Pitfalls](#pitfalls) |
| `keyPressed` (the boolean) | `isKeyPressed: Bool` |
| `keyPressed()` / `keyReleased()` / `keyTyped()` | same names |
| `key` | `key: Character?` — **optional** |
| `keyCode` | `keyCode: UInt16?` — **optional**, a macOS virtual key code |
| `keyCode == LEFT` | `keyCode == LEFT` — the arrow-key constants carry over |
| — | `isKeyDown(_ keyCode: UInt16) -> Bool` for polling held keys, `isKeyRepeat: Bool` |
| `selectInput()` / `selectOutput()` | `selectInput(_ prompt: String = "Select a file", _ callback: @MainActor (String?) -> Void)` / `selectOutput(…)` |
| drag-and-drop | `func fileDropped(_ paths: [String])` |
| `cursor()` / `noCursor()` | `cursor()` / `noCursor()` |

### Math, random, noise

All of these are **free functions** (not methods on the sketch), so they work
anywhere in the file.

| Processing | metaphor |
|---|---|
| `map(v, a, b, c, d)` | `map(_ value: Float, _ start1: Float, _ stop1: Float, _ start2: Float, _ stop2: Float) -> Float` |
| `lerp(a, b, t)` | `lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T`, plus `SIMD2`/`SIMD3`/`SIMD4` overloads |
| `constrain(v, lo, hi)` | `constrain(_ value: Float, _ low: Float, _ high: Float) -> Float` |
| `norm(v, lo, hi)` | `norm(_ value: Float, _ start: Float, _ stop: Float) -> Float` |
| `dist(x1, y1, x2, y2)` | `dist(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float` (3D overload too) |
| `mag(x, y)` | `mag(_ x: Float, _ y: Float) -> Float` (3D overload too) |
| `sq(v)` | `sq(_ value: Float) -> Float` |
| `sqrt` / `pow` / `abs` / `floor` / `ceil` / `round` / `min` / `max` | Swift's own — `sqrt(x)`, `pow(x, y)`, `abs(x)`, `floor(x)`, `x.rounded()`, `min(a, b)`, `max(a, b)` |
| `radians(d)` / `degrees(r)` | `radians(_ degrees: Float) -> Float` / `degrees(_ radians: Float) -> Float` |
| `random(hi)` / `random(lo, hi)` | `random(_ high: Float) -> Float` / `random(_ low: Float, _ high: Float) -> Float` |
| p5.js `random()` with no arguments | — write `random(1)` |
| `randomSeed(n)` | `randomSeed(_ seed: UInt64)` |
| `randomGaussian()` | `randomGaussian(_ mean: Float = 0, _ sd: Float = 1) -> Float` |
| `noise(x)` / `noise(x, y)` / `noise(x, y, z)` | same three overloads, Perlin, output `0…1` |
| `noiseDetail(4, 0.5)` | `noiseDetail(octaves: 4, falloff: 0.5)` — **labels are required** |
| `noiseSeed(n)` | `noiseSeed(_ seed: UInt64)` |
| `bezierPoint` / `bezierTangent` / `curvePoint` / `curveTangent` | same names, `(a, b, c, d, t) -> Float` |
| `year()` / `month()` / `day()` / `hour()` / `minute()` / `second()` | same names, all `-> Int` |
| — | `saturate(_:)`, `smoothstep(_:_:_:)`, `sine01`/`cosine01`/`sawtooth`/`triangle`/`square` waveforms, and 30 easing functions (`easeInOutCubic` etc.) |

Two behavioral differences worth knowing: `map` returns `start2` instead of a
NaN when `start1 == stop1`, and `random(lo, hi)` sorts its arguments, so a
reversed range does not misbehave.

### Vectors: PVector → Vec2 / Vec3

`Vec2` and `Vec3` are type aliases for `SIMD2<Float>` and `SIMD3<Float>`. They are
**value types** — see [Pitfalls](#pitfalls).

| Processing | metaphor |
|---|---|
| `new PVector(x, y)` | `Vec2(x, y)` or `createVector(x, y)` |
| `new PVector(x, y, z)` | `Vec3(x, y, z)` or `createVector(x, y, z)` |
| `v.add(w)` / `PVector.add(v, w)` | `v += w` / `v + w` |
| `v.sub(w)` / `v.mult(s)` / `v.div(s)` | `v -= w` / `v *= s` / `v /= s` |
| `v.mag()` | `v.magnitude` (a property) |
| `v.magSq()` | `v.magnitudeSquared` |
| `v.normalize()` | `v.normalize()` (mutating) or `v.normalized()` (returns a copy) |
| `v.setMag(m)` | `v.setMag(m)` (mutating) or `v.withMagnitude(m)` |
| `v.limit(m)` | `v.limit(m)` (mutating) or `v.limited(m)` |
| `v.heading()` | `v.heading()` — `Vec2` only |
| `v.rotate(a)` | `v.rotate(a)` (mutating) or `v.rotated(a)` — `Vec2` only |
| `PVector.fromAngle(a)` | `Vec2.fromAngle(_ angle: Float)` |
| `PVector.random2D()` / `random3D()` | `Vec2.random2D()` / `Vec3.random3D()` |
| `v.dist(w)` | `v.dist(to: w)` — note the label |
| `v.dot(w)` / `v.cross(w)` | `v.dot(w)` / `v.cross(w)` (`Vec2.cross` returns a scalar) |
| `v.lerp(w, t)` | `v.lerp(to: w, t: t)` |
| `PVector.angleBetween(v, w)` | `v.angleBetween(w)` |
| `v.copy()` | plain assignment — `Vec2` is a value type |

### Data

| Processing | metaphor |
|---|---|
| `loadStrings("f.txt")` | `loadStrings(_ source: String) throws -> [String]` |
| `saveStrings("f.txt", lines)` | `saveStrings(_ lines: [String], _ path: String) throws` — **p5.js argument order: data first, path second** |
| `loadJSONObject("f.json")` | `loadJSON(_ source: String) throws -> JSONValue`, or `loadJSON(_ source: String, as: T.Type) throws -> T` for a `Decodable` type |
| `saveJSONObject(json, "f.json")` | `saveJSON(_ value: some Encodable, _ path: String, pretty: Bool = true) throws` |
| `loadTable("f.csv", "header")` | `loadTable(_ source: String, format: TableFormat? = nil, header: Bool = true) throws -> Table` |
| `saveTable(table, "f.csv")` | `saveTable(_ table: Table, _ path: String, format: TableFormat? = nil, header: Bool = true) throws` |
| `table.getRowCount()` | `table.rowCount` (a property); likewise `table.columnCount` |
| `table.rows()` | `table.rows: [TableRow]` |
| `table.getRow(i)` | `table.getRow(_ index: Int) -> TableRow?` — optional |
| `row.getString("c")` / `getInt` / `getFloat` | `row.getString(_ column: String)` / `getInt` / `getFloat` / `getDouble`, each with an `Int` index overload too |
| `table.addRow()` | `table.addRow() -> TableRow` (also `addRow(_ values: [String])`) |
| `json.getString("k")` | `json["k"].stringValue` (or `.string` for the optional form) |
| `json.getJSONArray("k")` | `json["k"].arrayValue` |
| `loadBytes` / `saveBytes` | — not implemented |

All load and save functions **throw**, and every one has an `…Async` counterpart
(`loadStringsAsync`, `loadJSONAsync`, `loadTableAsync`, …). `http://` and
`https://` sources are fetched as URLs; anything else is a file path, absolute or
relative to the process working directory. There is no Processing-style `data/`
folder lookup.

### Output and export

| Processing | metaphor |
|---|---|
| `save("out.png")` | `save(_ path: String)` |
| `save()` | `save()` — writes `~/Desktop/metaphor_<timestamp>.png` |
| `saveFrame()` / `saveFrame("f-####.png")` | `saveFrame(_ filename: String? = nil)` — default `~/Desktop/screen-####.png`, numbered by `frameCount` |
| `beginRecord(SVG, "out.svg")` / `endRecord()` | `beginSVGRecord(_ path: String)` / `endSVGRecord()` |
| a PNG sequence | `beginFrameRecord(directory: String? = nil, pattern: String = "frame_%05d.png")` / `endFrameRecord()` — default directory `~/Desktop/metaphor_frames_<timestamp>` |
| — | `beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig())` / `endVideoRecord(completion:)` / `endVideoRecordAsync()` |
| — | `beginGIFRecord(fps: Int = 15)` / `endGIFRecord(_ path: String? = nil) throws` / `endGIFRecordAsync(_:)` |
| — | `beginOfflineRender(fps: Double = 60)` / `endOfflineRender()` for deterministic, non-realtime rendering |

> **These names changed after 0.8.0.** `beginSVG`/`endSVG` and the unprefixed
> `beginRecord`/`endRecord` still exist as deprecated aliases and will be removed
> in the following minor release. Use `beginSVGRecord` and `beginFrameRecord`. The
> rename exists precisely because metaphor's old `beginRecord()` recorded a *PNG
> sequence* while Processing's `beginRecord()` starts *vector* recording — the kind
> of trap that cannot be fixed after 1.0 (ADR-0007). `beginOfflineRender()` keeps
> its name: it switches rendering *mode* rather than starting a recording.

`beginSVGRecord` is meant to be called inside `draw()`, wrapping the frame you
want to export:

```swift
func draw() {
    if wantExport { beginSVGRecord("output/sketch.svg") }
    background(255)
    circle(width / 2, height / 2, 200)
    if wantExport { endSVGRecord(); wantExport = false }
}
```

`image()`, `text()` and gradients are not representable in the SVG writer; they
are skipped with a one-time warning.

### Constants

| Processing | metaphor |
|---|---|
| `PI` / `TWO_PI` / `HALF_PI` / `QUARTER_PI` / `TAU` | same names, all `Float` |
| `LEFT` / `RIGHT` / `UP` / `DOWN` | same names — but they are **arrow-key virtual key codes** (`UInt16`), for use with `keyCode` |
| `RETURN` / `ENTER` / `TAB` / `SPACE` / `BACKSPACE` / `DELETE` / `ESC` | `RETURN` / `ENTER` / `TAB` / `SPACE` / `BACKSPACE` / `DELETE` / `ESCAPE` |
| `SHIFT` / `CONTROL` / `ALT` | `SHIFT` / `CONTROL` / `OPTION` (`ALT` is an alias) / `COMMAND` |
| `CENTER` / `CORNER` / `CORNERS` / `RADIUS` | — no such constants; the mode functions take enums (`.center`, `.corner`, …) |
| `RGB` / `HSB` | `.rgb` / `.hsb` (`ColorSpace`) |
| `BLEND` / `ADD` / `MULTIPLY` / `SCREEN` … | `.alpha` / `.additive` / `.multiply` / `.screen` … (`BlendMode`) |
| `POINTS` / `LINES` / `TRIANGLES` / `TRIANGLE_STRIP` / `TRIANGLE_FAN` | `.points` / `.lines` / `.triangles` / `.triangleStrip` / `.triangleFan` (`ShapeMode`) |
| `CLOSE` | `.close` (`CloseMode`) |
| `PIE` / `CHORD` / `OPEN` | `.pie` / `.chord` / `.open` (`ArcMode`) |
| `BLUR` / `GRAY` / `INVERT` / `THRESHOLD` / `POSTERIZE` / `DILATE` / `ERODE` | `.blur(r)` / `.gray` / `.invert` / `.threshold(t)` / `.posterize(n)` / `.dilate` / `.erode` (`FilterType`) |

### Types: PImage, PGraphics, PShape, PVector

| Processing | metaphor |
|---|---|
| `PImage` | `MImage` |
| `PGraphics` | `Graphics` (2D) / `Graphics3D` |
| `PShape` | `MShape` |
| `PVector` | `Vec2` = `SIMD2<Float>`, `Vec3` = `SIMD3<Float>` |
| `PFont` | — (use `textFont(_ family: String)`) |
| `PShader` | `CustomMaterial` (3D) / `CustomPostEffect` (post-process). No 2D shader type yet |
| `PMatrix2D` / `PMatrix3D` | `float3x3` / `float4x4` (from `simd`) |
| `Table` / `TableRow` | `Table` / `TableRow` |
| `JSONObject` / `JSONArray` | `JSONValue` (one enum covering both) |
| `PApplet` | `Sketch` |

## Pitfalls

### Everything is `Float`, and Swift will not convert for you

Processing promotes `int` to `float` silently. Swift does not, and `width` /
`height` / `mouseX` are all `Float`:

```swift
// Does not compile: mixing Int and Float
let n = 10
circle(width / n, height / 2, 40)

// Fine
let n: Float = 10
circle(width / n, height / 2, 40)
```

Literals are fine (`circle(width / 2, height / 2, 40)` works, because `2` infers
as `Float`); stored `Int` values are not. A `for i in 0..<10` loop counter is an
`Int`, so write `Float(i)` when it reaches a drawing call.

### Two color ranges: 0–255 numbers, 0–1 `Color`

There are two ways to say "white", and they use different scales:

```swift
fill(255)                    // numeric overload — honours colorMode(), default 0...255
fill(.white)                 // Color value — components are always 0...1
fill(Color(r: 1, g: 1, b: 1))
```

`Color(r:g:b:a:)`, `Color(gray:)`, `Color(hue:saturation:brightness:)` and the
named constants (`.white`, `.red`, …) are **not** affected by `colorMode()` —
they are always normalized. The numeric `fill` / `stroke` / `background` /
`tint` overloads are. Mixing `fill(1.0)` (nearly black under the default mode)
with `fill(.white)` in the same sketch is the classic way to confuse yourself;
pick one convention per sketch.

### `Sketch` is `@MainActor`

The `Sketch` protocol is annotated `@MainActor`, so `setup()`, `draw()` and the
event callbacks all run on the main actor. Two consequences:

- Calling a metaphor drawing API from a background task will not compile without
  hopping back to the main actor.
- The `…Async` loaders (`loadImageAsync`, `loadJSONAsync`, …) do the file or
  network I/O off the main thread and return to it, which is why they exist. Use
  them from a `Task { … }` started in `setup()` rather than blocking `draw()`.

Anything stored on your sketch class is main-actor isolated too, so ordinary
sketch state needs no locking.

### Value types vs. reference types (`PVector` is a class, `Vec2` is not)

`PVector` is a Java object: passing it around shares it, and `v.add(w)` mutates
in place. `Vec2` / `Vec3` are `SIMD` **structs** — assignment copies.

```swift
var a = Vec2(1, 2)
var b = a          // a copy, not an alias
b.x = 99           // a is still (1, 2)

// Mutating methods need `var`, not `let`
var v = Vec2(3, 4)
v.normalize()      // in place
let w = v.normalized()   // returns a copy
```

The same applies to storing vectors in an array: `particles[i].position += velocity`
updates the element, because the array element is a value. There is no `copy()`
and no aliasing surprise — but also no way to hand a vector to a helper and have
the helper mutate your copy unless you use `inout`.

### `LEFT` is a key code, not a mouse button

In Processing, `LEFT` is overloaded: a mouse button, a text alignment, and an
arrow key. In metaphor, `LEFT` is **only** the left-arrow virtual key code
(`UInt16` 123). Migrate as follows:

```swift
if mouseButton == .left { … }    // was: mouseButton == LEFT
textAlign(.left)                 // was: textAlign(LEFT)
rectMode(.center)                // was: rectMode(CENTER)
if keyCode == LEFT { … }         // unchanged — this one really is a key code
```

The compiler catches all three mistakes: `textAlign(LEFT)` fails on the type,
`rectMode(CENTER)` fails because there is no `CENTER`, and `mouseButton == LEFT`
fails because `mouseButton` is a `MouseButton?`, not an integer.

> Before v0.9.0, `mouseButton` was an `Int` and `mouseButton == LEFT` **compiled**
> — Swift allows heterogeneous integer comparison, so it silently evaluated to
> `false` forever (`mouseButton` was `0`/`1`/`2`; `LEFT` is `123`). It was the one
> migration bug in this guide that no diagnostic pointed at. If you are porting a
> sketch that was already migrated against an older metaphor, that comparison is
> now a compile error rather than a silent `false` ([#382](https://github.com/shinyaoguri/metaphor/issues/382)).

`mouseButton` is a `MouseButton?` (`.left` / `.right` / `.middle`) and is set on
mouse-down only. It is `nil` until the first press, and afterwards keeps the last
pressed button even after release — exactly like Processing, so `mouseReleased()`
can still tell which button was let go. Use `isMousePressed` to ask whether a
button is down *right now*.

Also note `key` and `keyCode` are **optionals** (`Character?`, `UInt16?`), so
`if key == "a"` works but `key!.isLetter` needs unwrapping.

### 2D and 3D are two canvases, but the transform family drives both

`P3D` in Processing is a renderer swap: the same `translate` / `rotate` / `scale`
drive whichever mode you are in. metaphor draws 2D and 3D on two canvases that
live side by side in the same frame — but the **transform family applies to both**,
so the `P3D` centering idiom ports unchanged
([ADR-0005](adr/0005-sketch-api-consistency.md), Amendment 2026-08-02):

| | 2D canvas | 3D canvas |
|---|---|---|
| `translate(x, y)` | ✅ | ✅ (as `z = 0`) |
| `translate(x, y, z)` | — | ✅ |
| `rotate(a)` | ✅ | ✅ (about z) |
| `rotateX/Y/Z(a)` | — | ✅ |
| `scale(s)` | ✅ | ✅ |
| `scale(sx, sy)` | ✅ | ✅ (z unscaled) |
| `scale(x, y, z)` | — | ✅ |
| `shearX/Y(a)`, `applyMatrix(float3x3)` | ✅ | — |
| `applyMatrix(float4x4)` | — | ✅ |
| `blendMode`, `strokeWeight` | ✅ | — |
| `fill`, `stroke`, `noFill`, `noStroke` | ✅ | ✅ |
| `pushMatrix()` / `popMatrix()`, `resetMatrix()` | ✅ | ✅ |
| `push()` / `pop()`, `pushStyle()` / `popStyle()` | ✅ | ✅ |

This works because the 3D world **is** pixel space: the default camera is reset
every frame to Processing's own `P3D` default, so `translate(width/2, height/2)`
means the same thing on both canvases. `translate(x, y)` on the 3D matrix is a
`z = 0` translation, `rotate(a)` is a rotation about z, and `scale(sx, sy)` leaves
z unscaled.

**What still does not carry over is the other direction:** 3D-only transforms do
not affect 2D drawing. `Canvas2D`'s matrix is a `float3x3` affine, which cannot
represent `rotateX` / `rotateY`, so a `P3D` sketch that rotates a `rect()` in 3D
will render it flat. Draw with 3D primitives (`box`, `sphere`, `beginShape3D`)
when you need that.

Related: starting a shape with the 2D `beginShape()` routes three-argument
`vertex(x, y, z)` calls to the **2D** canvas with `z` dropped. Use `beginShape3D()`
/ `endShape3D()` to build actual 3D geometry.

The save/restore family covers both canvases: `pushMatrix()` / `popMatrix()` save the
transform on **both**, and `push()` / `pop()` save the transform *and* the style on
both. Wrap a region in `pushMatrix()` / `popMatrix()` when you want a 2D-only
transform not to leak into subsequent 3D drawing.

### The 3D camera resets every frame

`camera()`, `perspective()` and `ortho()` are reset to the Processing-style
defaults at the start of every frame. Setting a custom projection in `setup()`
has no effect — call it at the top of `draw()`, the same as Processing.

Style state (`fill`, `stroke`, …) is the opposite: it **persists across frames**,
matching Processing.

### The window is smaller than the canvas by default

`SketchConfig.windowScale` defaults to `0.5`, and it scales the **window**, not the
canvas: `SketchConfig(width: 1920, height: 1080)` renders a 1920×1080 offscreen
texture and shows it in a 960×540 window. `width` and `height` inside `draw()` are
always the texture dimensions, so coordinates are unaffected — but the window looks
half-size until you pass `windowScale: 1.0`. The split is deliberate: it is what
lets a sketch drive a fixed-resolution Syphon output from a small window.

The window is resizable but aspect-locked, and **there is no `windowResized`
callback**. The only way to change the canvas at runtime is
`createCanvas(width:height:)` — and that one belongs in `setup()`: nothing stops
you calling it mid-`draw()`, but it will stall for up to five seconds draining
in-flight frames.

### Sketch state is initialized in `setup()`, not at the declaration

A `.pde` file lets you write `float r = width / 4;` at the top level. Swift does
not: a stored property's initializer runs before `self` exists, so it cannot see
`width` at all — and on the paths where you *can* reach a drawing API early (from
`init()`, say), the rendering context does not exist yet and the call traps with a
message telling you to move it into `setup()` or `draw()`.

Give the properties a placeholder (or make them `Optional`) and fill them in from
`setup()`:

```swift
@main
final class MySketch: Sketch {
    var radius: Float = 0
    var photo: MImage?

    func setup() {
        radius = width / 4               // width is available from here on
        photo = try? loadImage("assets/photo.png")
    }

    func draw() { … }
}
```

Keeping every default also means the compiler synthesizes the `init()` that
`Sketch` requires, so you never write one.

### `loadImage()` in `draw()` is cached, but the first call blocks

`loadImage(_:cache:)` is synchronous and keyed by the standardized absolute path,
so calling it every frame costs a cache lookup after the first frame and returns
the *same* `MImage` instance — but that first frame does a blocking disk read and
texture upload, which shows up as a hitch. Load in `setup()`, or use
`loadImageAsync` from a `Task`. Two caveats: the cache is a 64-entry LRU, so a
sketch cycling through more images than that will re-decode synchronously every
frame; and `cache: false` means *every* call pays full price. The same applies to
`loadModel(_:normalize:cache:)`.

### Loading throws instead of returning `null`

Processing returns `null` and prints to the console. metaphor uses Swift errors:

```swift
func setup() {
    do {
        img = try loadImage("assets/photo.png")
    } catch {
        print("could not load: \(error)")
    }
}
```

`loadImage` and every data API throw `MetaphorError`; Tier 1 modules throw their
own type (`loadSound` throws `SoundFileError`). Whichever it is, a throwing API
only ever throws **its own module's error type** — raw `NSError`s from Metal,
Foundation or AVFoundation are wrapped, with the original cause kept in the case
payload, and each API's `- Throws:` doc names the cases it can produce
([ADR-0005](adr/0005-sketch-api-consistency.md) Amendment).

By contrast, *drawing* calls never throw — bad arguments produce a warning and a
safe no-op, so `draw()` stays free of `try` (ADR-0005). A third group returns an
optional rather than throwing: `createGraphics`, `createImage`, `createBuffer`,
and — inconsistently with `loadImage` — `loadModel`, which returns `Mesh?`.

### `loadPixels()` splits the render pass

`loadPixels()` reads back the canvas **as of the call**, including shapes drawn
earlier in the same `draw()` — the Processing semantics. To do that it closes the
current render pass, commits it, waits for the GPU, and resumes drawing in a
continuation pass. Three things follow:

- It **blocks the main thread** while the GPU catches up (as it does in
  Processing). Sketches that never call it pay nothing.
- The continuation pass clears depth, so **3D drawn before and after a
  `loadPixels()` call is not depth-tested against each other**. 2D is unaffected.
- With `enableShadows()` active, same-frame readback is unavailable (`draw()` runs
  as a record pass first); you get the last committed frame and a one-time
  warning.

`updatePixels()` is a no-op if `loadPixels()` was never called, and `pixels` is an
empty buffer until the first `loadPixels()`.

Related: `copy(…)` reads from the offscreen target's *previous* contents, not the
shapes drawn so far this frame.

### `frameRate()` sets, but nothing reads

`frameRate(_ fps: Int)` changes the target frame rate. There is no `frameRate`
variable to read the measured rate — it is a tracked follow-up
([#273](https://github.com/shinyaoguri/metaphor/issues/273)). To *see* the
current rate, `enablePerformanceHUD()` draws an on-screen overlay; to compute
one, `1 / deltaTime`; and for animation timing prefer `deltaTime` and `time` over
counting frames.

### Fonts are family names, not files

`textFont(_ family: String)` takes an installed font family
(`textFont("Helvetica Neue")`). There is no `PFont`, no `createFont()`, and no
way to load a `.ttf` from disk yet.

### There is no `data/` folder

Relative paths resolve against the process working directory — which, for
`swift run`, is the package directory. Put assets somewhere predictable and use a
path relative to that, or an absolute path. `MImage(named:device:)` is the only
API that looks inside an app bundle.

### `noiseDetail` needs argument labels

`noiseDetail(4, 0.5)` does not compile; write
`noiseDetail(octaves: 4, falloff: 0.5)`. This is the general pattern for the few
places where Swift labels appear: required positional arguments (coordinates,
sizes, colors) stay unlabelled, optional modifiers get labels (ADR-0007).

## Not available yet

| Processing | Status |
|---|---|
| `loadShader()` / `shader()` / `resetShader()` for 2D | Planned, Phase 2 — [Epic #291](https://github.com/shinyaoguri/metaphor/issues/291). Today: `createMaterial` for 3D and `createPostEffect` for post-processing, both taking Metal Shading Language. |
| `loadShape()` (SVG as `PShape`) | Planned, Phase 2 — [Epic #288](https://github.com/shinyaoguri/metaphor/issues/288). Today: `loadModel()` reads OBJ / USDZ / ABC into a `Mesh`; SVG is export-only. |
| `createFont()` / `loadFont()` / `PFont`, `textToPoints()` | Planned, Phase 2 — [Epic #292](https://github.com/shinyaoguri/metaphor/issues/292). Today `textFont(_:)` resolves installed family names only. |
| canvas-wide `filter()` and `blend()` | Planned, Phase 2. Today `filter(_ image: MImage, _ type: FilterType)` filters an image, and post-process effects (`addPostEffect`) cover the whole frame. |
| `PDF` export | Demand-gated, Phase 4 — [Epic #288](https://github.com/shinyaoguri/metaphor/issues/288). |
| the `frameRate` variable | Not implemented — [#273](https://github.com/shinyaoguri/metaphor/issues/273). |
| `modelX()` / `modelY()` / `modelZ()` | Not implemented (ADR-0007 follow-up). `screenX/Y/Z` exist. |
| `quadraticVertex()`, `printMatrix()`, `beginCamera()` / `endCamera()`, `frustum()`, `textureMode()`, `textureWrap()`, `sphereDetail()`, `lightFalloff()`, `lightSpecular()`, `ambient()`, `hint()`, `pixelDensity()`, `windowResized()`, `exit()`, `delay()`, `loadBytes()` / `saveBytes()` | Not implemented. |

The phases refer to
[docs/design/roadmap-processing-unity.md](design/roadmap-processing-unity.md),
which tracks Processing parity as an explicit goal. If something you rely on is
missing from both this table and the mapping tables above, please
[open an issue](https://github.com/shinyaoguri/metaphor/issues/new/choose) —
parity gaps are the most useful thing to report.

## Where to look next

**The Examples tree mirrors Processing's own.** Categories and sample names under
[`Examples/Basics/`](../Examples/Basics/) and [`Examples/Topics/`](../Examples/Topics/)
follow Processing's official example hierarchy, so if you know the Processing
sample you can usually guess the path. Of the 278 example packages, 254 ship the
**original `.pde` right next to the Swift port**, plus a reference render — the
fastest way to see how a construct translates is to read both:

```
Examples/Basics/Form/ShapePrimitives/
├── ShapePrimitives.pde          ← the original Processing sketch
├── ShapePrimitives/App.swift    ← the metaphor port
├── ShapePrimitives.png          ← reference render
└── Package.swift
```

Each example is a self-contained SwiftPM package:

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

Good starting pairs for a migrant: `Basics/Structure/SetupDraw`,
`Basics/Form/ShapePrimitives`, `Basics/Transform/RotatePushPop`,
`Basics/Form/Primitives3D` (a literal `P3D` transcription),
`Topics/Vectors/AccelerationWithVectors` (the `PVector` → `Vec2` shape of things),
and `Topics/Simulate/Flocking`.

- [`docs/ai/examples-index.md`](ai/examples-index.md) — all 278 samples with tags
  and a difficulty rating. The companion
  [`examples-index.json`](ai/examples-index.json) records, per sample, which
  Processing APIs the original featured, so you can search *by the Processing name
  you are looking for*:
  ```bash
  jq -r '.examples[] | select(.featured | index("PVector")) | .path' docs/ai/examples-index.json
  ```
- [`Examples/LEARNING_PATH.md`](../Examples/LEARNING_PATH.md) — a curated order to
  work through them in.
- [`llms.txt`](../llms.txt) — the full public API surface in one file; the
  canonical answer for any signature.
- [`llms-sketch.txt`](../llms-sketch.txt) and
  [`docs/ai/for-sketch-authors.md`](ai/for-sketch-authors.md) — writing sketches
  with an AI assistant.
- [ADR-0005](adr/0005-sketch-api-consistency.md) and
  [ADR-0007](adr/0007-finalize-public-api-surface.md) — why the API looks the way
  it does (Japanese).
