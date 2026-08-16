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
