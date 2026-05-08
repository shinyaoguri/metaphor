# Shader Effect Prompt

Write or modify a metaphor sketch that uses a shader effect.

Goal:
- Create [describe the effect: bloom-like glow, chromatic smear, feedback,
  posterized color, displacement, custom material].

Constraints:
- Use `import metaphor`.
- Prefer built-in post effects or drawing APIs first.
- Use custom MSL only when it clearly improves the result.
- Keep shader source compact and valid Metal Shading Language.
- Create shader resources in `setup()`, not in `draw()`.
- If a shader compile error is provided, fix the exact error without changing
  the artistic goal.

Inputs:
- Current sketch: [paste App.swift if modifying].
- Error output: [paste compiler/runtime/shader error if any].

Return:
- The complete Swift file.
- Any custom shader source embedded in the file.
- A brief note on editable parameters.
