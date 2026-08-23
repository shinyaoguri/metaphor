- The headless status item's menu now answers "which process is this?" and lets
  you take the picture with you: the sketch name is a heading with **the
  directory the process is running in** beneath it (the `.metaphor/` base, so
  `METAPHOR_STATE_DIR` is honoured — the only way to tell two runs of the same
  sketch apart), and a new **Save Frame** (⌘S) writes the current frame to
  `output/metaphor_<timestamp>.png`, falling back to `~/Desktop` when that
  directory is not writable (a `.app` launched from Finder runs with `/` as its
  base). The save does **not** draw a new frame, so it works on a `noLoop()`
  sketch, and the menu keeps showing where the file went
  ([#1077](https://github.com/shinyaoguri/metaphor/issues/1077)).
