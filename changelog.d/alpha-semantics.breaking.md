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
