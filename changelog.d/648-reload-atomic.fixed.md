- `reloadShader(key:source:)` / `reloadShaderFromFile(key:path:)` no longer
  destroy the working shader when the new source fails to compile
  ([#648](https://github.com/shinyaoguri/metaphor/issues/648)). They used to
  drop the registered library *before* compiling, so a single typo left the key
  with no library at all: every later `function(named:from:)` returned nil and
  the sketch drew nothing until it was restarted. The new source is compiled
  first and swapped in only on success.
