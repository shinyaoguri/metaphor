- The test that guards Processing attribution under `Examples/` no longer counts credited
  files by matching a list of author names
  ([#1191](https://github.com/shinyaoguri/metaphor/issues/1191)). That approach could only
  recognise authors already written down, so ten of them — Rusty Robison, Martin Gomez,
  Hernando Barragán, Denis Grutze, Marius Watz, Joan Soler-Adillon, Dave Bollinger, Paul
  Bourke, Philip Rideout and GeneKao — were never counted, and the recorded census was
  wrong from the day it was written. Credit lines are not uniform either: beside
  `by Daniel Shiffman.` the tree held `Illustration by George Brower.`,
  `// C code by Paul Bourke` and bare `// Daniel Shiffman` with no introducing phrase.
- Three checks replace it, and they assert an invariant rather than a count: no bundled
  `.pde` carries the *shape* of a credit line, no bundled original names an author of a
  removed sketch, and no bundled `.json` declares an `author`. The bundled totals stay
  locked so that adding an original turns the suite red until someone confirms it is public
  domain. Nothing to do when upgrading — these run in `make test`.
- Processing originals no longer count as inputs when deciding whether an example's
  reference render is stale. A package's top-level `.pde` and `.json` are neither compiled
  nor declared as resources, so they cannot change the picture; leaving them in the
  fingerprint meant adding or removing one made `make example-shots ARGS="--check"` ask for
  a GPU re-capture that would produce an identical image. Files under `data/` are still
  counted, since sketches read those.
