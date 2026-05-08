# Live / VJ Loop Prompt

Write a complete metaphor sketch for live performance.

Goal:
- Create a stable realtime visual for [music style / venue / screen format].

Constraints:
- Use `import metaphor`.
- Canvas: [width] x [height].
- Keep a stable frame rate.
- Create resources in `setup()`.
- Prefer parameters that can be adjusted live.
- Add OSC, MIDI, Syphon, audio, or GUI only if requested and available in
  `llms.txt`.
- Include simple keyboard fallbacks for important toggles.

Live controls:
- [parameter 1]: [range / key / MIDI or OSC mapping]
- [parameter 2]: [range / key / MIDI or OSC mapping]

Return:
- The complete Swift file.
- A compact list of controls.
- A note about expected inputs and setup.
