# Third-Party Licenses

metaphor redistributes third-party material in four categories, and they are
covered very differently:

| Category | What it is | Status |
|---|---|---|
| **Fonts** | Eleven `.ttf` under `Examples/` and `Tests/` — three distinct fonts | SIL Open Font License 1.1, attributed in full below |
| **Processing example originals** | 314 `.pde` sketches and 181 `.json` metadata files kept beside each ported example | Most are public domain; the credited ones carry **no license grant at all** — see [Processing example originals](#processing-example-originals) |
| **Example media** | 213 image, video, model and data files under `Examples/**/data/` and `Examples/**/Resources/` | Provenance not yet recorded — tracked in [#939](https://github.com/shinyaoguri/metaphor/issues/939) |
| **Public-domain texts** | `dracula.txt` (two copies) and `frankenstein.txt` | Project Gutenberg transcriptions of works long in the public domain — see [Public-domain texts](#public-domain-texts) |

Not third-party: the 271 reference renders `Examples/**/<Name>.png`, which
`make example-shots` captures from metaphor's own ports.

**What `LICENSE` (MIT) actually covers** is metaphor's own work: everything under
`Sources/`, the Swift ports and Metal shaders written for this repository
(`Examples/**/*.swift`, `Examples/**/*.metal`), `Tests/`, `scripts/`, `docs/` and
the reference renders above. It does not, and cannot, relicense the third-party
material listed here.

This file reproduces the copyright notice and the license of each. The full SIL
Open Font License 1.1 text that covers the fonts is in [OFL.txt](OFL.txt) at the
repository root, reproduced verbatim from
[SIL](https://openfontlicense.org/documents/OFL.txt).

The compiled `Syphon.xcframework` (Simplified BSD) used to be attached to this
repository's releases. Since v0.12.0 it is built, attached and licensed by the
separate package [metaphor-syphon](https://github.com/shinyaoguri/metaphor-syphon)
(see its `THIRD_PARTY_LICENSES.md`); metaphor itself ships no binary artifact
([ADR-0014](docs/adr/0014-viewer-frame-ipc-and-syphon-plugin.md)).

## Bundled fonts

Eleven `.ttf` files are checked into this repository. They are three distinct
fonts — every copy of a given font is byte-identical, as the SHA-256 below
shows. All three are licensed under the **SIL Open Font License, Version 1.1**;
the license text is in [OFL.txt](OFL.txt).

The attribution recorded here is transcribed from each font's own `name` table
(nameID 0 `copyright`, 8 `manufacturer`, 9 `designer`, 13 `licenseDescription`),
not from a secondary source.

This section is written by hand, but it is not trusted: at `make test` time
`Tests/metaphorTests/FontLicenseTests.swift` walks the source tree and checks
every font it finds against the text below. A font added without an entry — or
an entry whose SHA-256 has gone stale — turns the test suite red.

### Source Code Pro (Regular)

- **Version**: 1.017 (`Version 1.017;PS Version 1.000;hotconv 1.0.70`)
- **Copyright**: Copyright 2010, 2012 Adobe Systems Incorporated
  (http://www.adobe.com/), with Reserved Font Name 'Source'. All Rights
  Reserved. Source is a trademark of Adobe Systems Incorporated in the United
  States and/or other countries.
- **Designer**: Paul D. Hunt
- **Manufacturer**: Adobe Systems Incorporated
- **Reserved Font Name**: `Source`
- **License**: SIL Open Font License 1.1
- **Upstream**: https://github.com/adobe-fonts/source-code-pro
- **SHA-256**: `2967dd73df838d2a2d390a638c6d7cfe9cd60c5ee2e162d8a1c10a70ea742b5c`

Eight copies:

```
Examples/Basics/Data/CharactersStrings/data/SourceCodePro-Regular.ttf
Examples/Basics/Data/DatatypeConversion/data/SourceCodePro-Regular.ttf
Examples/Basics/Typography/Letters/Letters/Resources/SourceCodePro-Regular.ttf
Examples/Basics/Typography/TextRotation/TextRotation/Resources/SourceCodePro-Regular.ttf
Examples/Topics/Advanced Data/CountingStrings/data/SourceCodePro-Regular.ttf
Examples/Topics/Advanced Data/HashMapClass/data/SourceCodePro-Regular.ttf
Examples/Topics/Advanced Data/XMLYahooWeather/data/SourceCodePro-Regular.ttf
Examples/Topics/Interaction/Tickle/data/SourceCodePro-Regular.ttf
```

### Space Mono (Regular)

- **Version**: 1.000 (`Version 1.000;PS 1.003;hotconv 1.0.81`)
- **Copyright**: Copyright 2016 Google Inc. All Rights Reserved.
- **Designer**: Colophon Foundry / Benjamin Critton
- **Manufacturer**: Colophon Foundry
- **Reserved Font Name**: none declared
- **License**: SIL Open Font License 1.1
- **Upstream**: https://github.com/googlefonts/spacemono
- **SHA-256**: `4c322514d265062aa3f7fbd81f5b79391ccb74268e6a20600061e0ce33234f41`

The font is a Colophon Foundry design, but the copyright holder recorded in the
file is **Google Inc.** — `Space Mono is a trademark of Google.` (nameID 7).

Two copies:

```
Examples/Basics/Typography/Words/Words/Resources/SpaceMono-Regular.ttf
Tests/metaphorTests/Fixtures/SpaceMono-Regular.ttf
```

### Merriweather (Light)

- **Version**: 1.003
- **Copyright**: Copyright (c) 2011, Sorkin Type Co (www.sorkintype.com) with
  Reserved Font Name "Merriweather".
- **Designer**: Eben Sorkin
- **Manufacturer**: Sorkin Type Co.
- **Reserved Font Name**: `Merriweather`
- **License**: SIL Open Font License 1.1
- **Upstream**: https://github.com/SorkinType/Merriweather
- **SHA-256**: `da1d0dddc30cf80a017f8886bfd77fde0caa5c8021a376c8ebba5a7c09f4c2b8`

The copyright field (nameID 0) names Sorkin Type Co and the year 2011; the
license description (nameID 13) names the designer and an earlier year —
`Copyright (c) 2010 by Eben Sorkin (eben@eyebytes.com), with Reserved Font Name
Merriweather.` Both are reproduced here because the font ships both.

One copy:

```
Examples/Topics/Advanced Data/XMLYahooWeather/data/Merriweather-Light.ttf
```

### Reserved Font Names

OFL 1.1 clause 3 forbids a **Modified** Version of the font software from using
a Reserved Font Name as its primary font name. metaphor ships all three fonts
unmodified — byte-identical to the upstream release — so the clause does not
bite today, but anyone re-cutting `Source Code Pro` or `Merriweather` (for
example subsetting them into a texture atlas file that is then redistributed as
a font) must rename the result. `Space Mono` declares no Reserved Font Name.

### Where the license text ships

OFL 1.1 clause 2 requires each redistributed copy to carry the copyright notice
and the license. `OFL.txt` at the repository root covers every copy in the
source tree, and three byte-identical copies ride along in the example bundles
that actually load a font at runtime:

```
OFL.txt
Examples/Basics/Typography/Letters/Letters/Resources/OFL.txt
Examples/Basics/Typography/TextRotation/TextRotation/Resources/OFL.txt
Examples/Basics/Typography/Words/Words/Resources/OFL.txt
```

Those three packages declare `resources: [.copy("Resources")]`, which copies the
whole directory, so the license lands in `<Target>.bundle` next to the `.ttf`
without any `Package.swift` change. The remaining copies live in `data/`
directories that no target declares as resources, so they are only ever
redistributed as part of this repository — where the root `OFL.txt` applies.

## Processing example originals

Each ported example keeps the Processing sample it came from beside the Swift
port: the original `.pde` sketch and, where upstream had one, the `.json`
metadata that describes it (`generated by scripts/generate-examples-index.py`
reads the latter). They come from
[processing/processing-examples](https://github.com/processing/processing-examples).

That repository's README draws a line this file has to repeat, because it is the
only license statement upstream makes:

> The examples without a credit line were written by Casey Reas or Ben Fry and
> they are in the public domain. ... The copyrights for other credited files
> remains with the original authors.

So the uncredited files are public domain, and **the credited ones are not
licensed at all** — upstream reserves their copyright without granting anything.
Attribution alone does not cure that, which is why this section states the
position rather than pretending it is resolved.

The counts, as the tree stands:

| | Total | Carrying a credit line |
|---|---:|---:|
| `.pde` | 314 | 95 |
| `.json` | 181 | 54 |

The credited `.pde` authors, as their own headers name them:

| Author | Files |
|---|---:|
| Daniel Shiffman | 42 |
| Ira Greenberg | 14 |
| Andres Colubri | 8 |
| Keith Peters | 7 |
| Simon Greenwold | 5 |
| Geraldine Sarmiento | 3 |
| George Brower | 3 |
| Robert Hodgin | 3 |
| David Pena | 2 |
| Jakub Valtar | 2 |
| James Paterson | 2 |
| Mike Davis | 2 |
| inigo quilez | 1 |
| Gillian Ramsay | 1 |
| Golan Levin | 1 |

The column sums to 96 rather than 95 because one sketch credits two authors.

They are kept because the original sketch beside the port is what makes the
Examples tree readable to someone arriving from Processing
([`docs/processing-migration-guide.md`](docs/processing-migration-guide.md)).
Whether that is worth redistributing unlicensed files is an open question,
tracked in [#1191](https://github.com/shinyaoguri/metaphor/issues/1191).

## Public-domain texts

Two Project Gutenberg transcriptions ship as sample data for the string-handling
examples:

```
Examples/Topics/Advanced Data/CountingStrings/data/dracula.txt
Examples/Topics/Advanced Data/HashMapClass/HashMapClass/Resources/dracula.txt
Examples/Topics/Advanced Data/HashMapClass/HashMapClass/Resources/frankenstein.txt
```

*Dracula* (Bram Stoker, 1897) and *Frankenstein* (Mary Wollstonecraft Shelley,
1818) are long out of copyright. The files retain Project Gutenberg's header,
whose terms apply to the transcription and to the "Project Gutenberg" trademark,
not to the works themselves.

## Removed: shaders that declared an MIT-incompatible license

Seven GLSL files used to ship under `Examples/**/data/`, each declaring in its
own header a license that MIT cannot absorb, and one `.pde` did the same. They
were removed in [#1190](https://github.com/shinyaoguri/metaphor/issues/1190);
this record stays so the removal is not silently forgotten.

| License | Files | Rights holder |
|---|---|---|
| GPLv2 | `Topics/Shaders/GlossyFishEye/data/Glossy{Vert,Frag}.glsl` | Dave Griffiths (Fluxus Shader Library, 2007) |
| LGPL-2.1 | `Demos/Graphics/LowLevelGLVbo{Interleaved,Separate}/data/{vert,frag}.glsl` | Ben Fry and Casey Reas (Processing core, 2011-12) |
| CC BY-NC-SA 3.0 | `Topics/Shaders/Landscape/data/landscape.glsl`, `Topics/Shaders/Landscape/Landscape.pde` | inigo quilez (Shadertoy ["Elevated"](https://www.shadertoy.com/view/MdX3Rr), 2013); Processing port by Raphaël de Courville |

CC **BY-NC** is non-commercial only, which collides head-on with MIT's grant of
"the rights to ... sell copies". The GPLv2 headers point at a `COPYING` file that
was never shipped, so the redistribution did not even meet GPLv2's own terms.

The other 21 `.glsl` in the tree declared no license, but shared the same
provenance and the same unresolved question, and nothing read them at runtime —
metaphor is Metal, and the only example that calls `loadShader()` reads a `.metal`
file it wrote itself. All 28 went together rather than leaving a category behind
with no way to tell the safe ones from the rest.
