# AI Guide For Sketch Authors

This file is for people making content with metaphor, not for maintainers of
the library internals.

## What To Give An AI Assistant

For best results, provide:

- The creative goal: mood, motion, subject, and interaction.
- The target format: realtime window, still image, loop, video export, live VJ.
- Constraints: canvas size, FPS, color palette, audio/video/OSC/MIDI inputs.
- Assets: filenames, dimensions, and where they live.
- References: one or two existing examples to imitate or modify.

Useful starter prompt:

```text
Write a complete metaphor App.swift sketch.
Goal: <describe the visual or interaction>.
Constraints:
- import metaphor
- canvas: 1280x720
- keep draw() realtime safe
- load resources in setup()
- use only APIs present in llms.txt or llms-sketch.txt
Return the complete Swift file.
```

## Good Sketch Structure

- `config`: canvas size, title, render loop mode, Syphon if needed.
- properties: long-lived state, resources, arrays, user parameters.
- `setup()`: load assets, create audio/video/physics/particles/shaders.
- `compute()`: GPU compute or particle update when needed.
- `draw()`: clear background, update animation state, render.
- input callbacks: small state changes, toggles, recording controls.

## Creative Patterns

- **Generative 2D**: arrays of points, flow fields, easing, blend modes.
- **Audio reactive**: FFT bands mapped to scale, color, density, displacement.
- **Image feedback**: render to offscreen graphics, apply post effects, blend
  prior-frame texture when the sketch enables feedback.
- **Live/VJ**: expose parameters, listen to OSC/MIDI, keep a stable frame rate.
- **Exported loops**: use deterministic `time` or frame-index math so frame 0
  and the final frame connect cleanly.

## Common Mistakes To Ask AI To Avoid

- Loading files inside `draw()`.
- Recreating audio/video/physics/shader/particle resources every frame.
- Using APIs from Processing or p5.js that do not exist in metaphor.
- Hardcoding all positions for one canvas size when `width` / `height` would be
  more robust.
- Writing large custom Metal shaders before trying built-in drawing and effects.
- Adding complicated architecture for a single-file sketch.

## Iteration Loop

1. Ask for a minimal working sketch first.
2. Run it with `metaphor run` or `swift run`.
3. If it fails, paste the exact compiler/runtime output back to the assistant.
4. If it runs but looks wrong, capture a screenshot and describe the desired
   change in visual terms.
5. Ask for one improvement at a time: motion, color, interaction, performance,
   export, or polish.
