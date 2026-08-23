- Headless (offscreen) runs now show up on screen instead of being invisible. A
  sketch started with `METAPHOR_VIEWER=1` has no window and used to appear
  nowhere — no Dock icon, no menu bar item — while still holding an App Nap
  assertion and driving the GPU, so there was no way to tell whether one (or
  five) were running, or how to stop them. Such a run now puts a status item in
  the menu bar showing the sketch name, metaphor version and PID, resolution,
  target and measured fps, frame count and elapsed time, and where the frames go
  (`Output: none — nobody is watching these frames` when the live viewer has
  disconnected and nothing else is observing), plus a Quit item that terminates
  the process through the normal shutdown path.
  - Pick a different surface with `SketchConfig(headlessIndicator:)` —
    `.menuBar` (default), `.dock` (Dock icon and ⌘-Tab, with a minimal app menu
    so ⌘Q works), `.both`, or `.hidden` for the previous behaviour.
  - The environment variable `METAPHOR_HEADLESS_INDICATOR`
    (`menubar` / `dock` / `both` / `none`) overrides the config without a
    rebuild, the same way `METAPHOR_FPS` overrides `fps`.
  - Windowed runs are unaffected.
