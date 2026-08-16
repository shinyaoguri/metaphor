- `Physics2D.step(_:iterations:)` now warns (DEBUG) when `iterations` is negative
  instead of dropping the step in complete silence. The silence was not a design
  choice: `MetaphorPhysics` is a Tier 1 module and simply could not reach the
  shared logger
  ([#805](https://github.com/shinyaoguri/metaphor/issues/805))
