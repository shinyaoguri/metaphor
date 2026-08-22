# metaphor ribbon 3D model

Procedural 3D reconstruction of the selected spiral-ribbon logo concept.

## Files

- `generate_metaphor_ribbon.py` — editable mesh and preview generator
- `metaphor-ribbon.obj` / `metaphor-ribbon.mtl` — colored interchange model
- `metaphor-ribbon.stl` — watertight geometry for modeling and printing tools
- `metaphor-ribbon-preview.png` — orthographic preview at the current camera angle

## Regenerate

The script requires Python, NumPy, and Pillow.

```bash
python3 generate_metaphor_ribbon.py \
  --yaw -11 \
  --pitch 7 \
  --roll 0 \
  --twist-turns 1
```

Camera angles affect only the preview. `--twist-turns` changes the mesh.

The ribbon centerline uses the five cubic segments traced from the selected
upper-left logo panel. Its width decreases by 34% from left to right, while the
cross-section thickness decreases by 18%. The front surface is ivory and the
back surface is silver.
