- The headless status item is now a *last resort* rather than an always-on HUD:
  it stays out of the menu bar while the live viewer (`metaphor watch`) is
  attached — the parent window already shows the same picture and the same
  numbers — and appears the moment nobody is watching any more, so **its very
  presence means "this process is unobserved"**. Runs with no parent window
  (`metaphor mcp`, Syphon output, a plain headless launch) keep showing it as
  before, and `metaphor watch` no longer flickers an item in and out of the menu
  bar on every rebuild
  ([#1071](https://github.com/shinyaoguri/metaphor/issues/1071)).
