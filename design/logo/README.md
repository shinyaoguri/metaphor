# metaphor mark

These SVGs are direct vector traces of the upper-left panel in
`exec-96de9e20-0f03-4474-8499-a3ee41ef1037.png`.

The earlier SVG inferred a new centerline and did not match the selected image.
The current version instead extracts the actual raster contours:

1. Crop the original upper-left `630 × 630` panel without rescaling.
2. Select the largest light connected component as the ribbon silhouette.
3. Select the two neutral-gray connected components as the undersides.
4. Trace their pixel boundaries and simplify them at a subpixel tolerance.

- `metaphor-mark.svg` — transparent traced mark
- `metaphor-mark-construction.svg` — the same paths on a dark background, with
  the extracted contour lines visible
- `metaphor-mark-geometric.svg` — simplified production candidate using only
  circular arcs (`A`) and straight lines (`L`)
- `metaphor-mark-geometric-construction.svg` — the same geometric mark with its
  contours highlighted

## Colors

- Main face: `#f4ede4`
- Underside: `#d2d2d7`
- Construction background: `#071426`

The source generated image is organically curved rather than an exact set of
compass arcs. A strict circle-only reconstruction necessarily changes its
silhouette. The traced pair prioritizes fidelity; the geometric pair prioritizes
smoothness, simplicity, and compass-like construction.
