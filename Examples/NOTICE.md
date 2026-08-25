# Examples — Attribution Notice

Most examples in this directory are Swift/Metal ports of sketches from the
[Processing](https://processing.org/) example collection. The tree mirrors
Processing's own hierarchy, so the matching path under
[processing/processing-examples](https://github.com/processing/processing-examples)
is the original for any given port.

That repository ships no license file. One sentence in its README is the only
license statement it makes:

> The examples without a credit line were written by Casey Reas or Ben Fry and
> they are in the public domain. ... The copyrights for other credited files
> remains with the original authors.

So a sketch **without** a credit line carries a public-domain dedication from its
own copyright holders. A sketch **with** one — Daniel Shiffman's included — keeps
its author's copyright, and upstream grants nothing alongside it. Attribution
does not cure that, so those originals are **not bundled here**: 144 `.pde` and
61 `.json` across 95 example packages were removed in
[#1191](https://github.com/shinyaoguri/metaphor/issues/1191).

Removal is by package rather than by file, because a Processing sketch is a set
of tabs — `Flocking/Boid.pde` carries no credit line of its own but belongs to a
sketch whose main tab does.

What that means when reading the tree:

- **158 packages ship the original `.pde` beside the port.** Those are the
  public-domain ones, and reading the two side by side is the fastest way to see
  how a construct translates.
- **The other 95 point at the original instead.** Their `App.swift` opens with
  the upstream URL:

  ```swift
  // Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Color/Brightness
  // The original .pde is not bundled — see Examples/NOTICE.md.
  ```

The `<Name>.json` beside each example is metaphor's own metadata — the 61 that
replaced a removed original were written from the Swift port, not carried over
from upstream's wording.

The Swift ports themselves, the Metal shaders written for them, and the
reference renders `make example-shots` captures are metaphor's own work, covered
by the repository's [MIT license](../LICENSE).

[THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) has the counts, the
authors named by the removed sketches, and the checks that keep credited
originals from coming back.

Reference: https://github.com/processing/processing-examples
