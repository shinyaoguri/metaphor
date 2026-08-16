- `MShape.fill(gray, alpha)` and `MShape.stroke(gray, alpha)`, so a retained
  shape definition can set a translucent gray the way the sketch-level
  `fill(_:_:)` / `stroke(_:_:)` already could. Both values are read in the
  shape's `colorMode()` range
  ([#853](https://github.com/shinyaoguri/metaphor/issues/853))
