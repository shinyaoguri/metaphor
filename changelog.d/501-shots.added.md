- **83 example packages that had no picture now ship one**, shot by actually running
  the sketch headless through the Probe (`make example-shots`). Together with the 162
  images carried over from the Processing originals, every `supported` example outside
  `Examples/Tutorial/` now either has a result image or says in writing why it cannot
  have one. Two declarations carry that: `no-capture.txt` (the picture depends on a
  camera, an external video, or hardware we cannot assume — plus, for now, the handful
  of sketches whose drawing is broken, each naming the issue that tracks it) and
  `probe-input.jsonl` (the sketch needs mouse or keyboard input before it draws
  anything worth looking at — that input is fed to the sketch during the shot). A new
  [`docs/ai/examples-shots.config.json`](../docs/ai/examples-shots.config.json) holds
  per-example exceptions to *when* the frame is grabbed, for sketches that settle into
  their picture on a different schedule than the 1.5 second default
  ([#501](https://github.com/shinyaoguri/metaphor/issues/501))
