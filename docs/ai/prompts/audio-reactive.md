# Audio Reactive Sketch Prompt

Write a complete metaphor `App.swift` sketch that reacts to audio.

Goal:
- Create [describe the visual] driven by [microphone / sound file / FFT bands].

Constraints:
- Use `import metaphor`.
- Canvas: [width] x [height].
- Create audio resources once in `setup()`.
- Do not load files or allocate large buffers inside `draw()`.
- Map audio features to visible parameters such as size, color, density,
  displacement, camera motion, or bloom.
- If the exact audio API is uncertain, use only symbols found in `llms.txt`.

Visual direction:
- Energy mapping: [bass expands circles / mids distort lines / highs sparkle].
- Palette: [colors].
- Responsiveness: [subtle / punchy / smoothed].

Return:
- The complete Swift file.
- A short explanation of which audio values drive which visuals.
