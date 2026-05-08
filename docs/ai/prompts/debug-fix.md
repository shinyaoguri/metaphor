# Debug / Fix Prompt

Fix this metaphor sketch.

Context:
- I am using metaphor with `import metaphor`.
- I want to preserve the existing visual intent.
- Do not rewrite the whole sketch unless the structure is fundamentally broken.

Inputs:
- Current `App.swift`:

```swift
[paste code here]
```

- Error output or observed behavior:

```text
[paste compiler/runtime output or visual issue here]
```

Instructions:
- Identify the likely cause.
- Use only metaphor APIs from `llms-sketch.txt` / `llms.txt`.
- Move resource creation out of `draw()` if needed.
- Keep the fix minimal and explain the change briefly.

Return:
- The corrected complete Swift file.
- A short explanation of the fix.
