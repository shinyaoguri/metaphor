- **`background()` is a replacement, not a composite.** The full-screen quad it falls back to
  is now drawn with blending off, matching what the render pass clear has always done, so both
  paths agree on the meaning (ADR-0012, and Processing's own `SRC` composite). Two consequences
  for existing sketches: `blendMode()` no longer affects `background()`, and a translucent
  background replaces the canvas instead of veiling it — `background(0, 0, 0, 20)` now leaves
  an almost fully transparent canvas rather than fading the previous frame. To fade, draw a
  full-screen `rect()` with the fade color instead
  ([#829](https://github.com/shinyaoguri/metaphor/issues/829))
