# Examples — Attribution Notice

The examples in this directory are Swift/Metal ports of sketches from the
[Processing](https://processing.org/) example collection. Each port keeps the
original `.pde` beside it, and where upstream had one, the `.json` metadata that
describes it.

Upstream draws exactly one line, and it is the only license statement it makes:

> The examples without a credit line were written by Casey Reas or Ben Fry and
> they are in the public domain. ... The copyrights for other credited files
> remains with the original authors.

So the sketches **without** a credit line are public domain. Everything **with**
one — Daniel Shiffman's included — keeps its author's copyright, and upstream
grants no license along with it. See each file's header comment for the specific
attribution, and
[THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) for the counts, the full
list of credited authors, and where that leaves this repository
([#1191](https://github.com/shinyaoguri/metaphor/issues/1191)).

The Swift ports themselves, the Metal shaders written for them, and the
reference renders `make example-shots` captures are metaphor's own work, covered
by the repository's [MIT license](../LICENSE).

Reference: https://github.com/processing/processing-examples
