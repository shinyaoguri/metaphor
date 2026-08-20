- `updatePixels()` now draws the pixel buffer 1:1 on the pixel grid. The 2D
  projection offsets integer coordinates by half a pixel (so `strokeWeight(1)`
  lands crisply on one pixel), which left the full-screen quad half a texel off:
  every fragment sampled a texel *boundary*, and `filter::linear` blended the
  four neighbours at 25% each. Changing a single pixel produced a blur across
  four, and `loadPixels()` → `updatePixels()` feedback smeared a little more
  every frame. Uniform edits (`pixels[i] ^= 0x00FF_FFFF` and friends) were
  unaffected, which is why it went unnoticed
  ([#812](https://github.com/shinyaoguri/metaphor/issues/812))
