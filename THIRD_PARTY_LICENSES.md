# Third-Party Licenses

metaphor redistributes third-party material in one place: **three fonts** —
`.ttf` files carried in the repository under `Examples/` and `Tests/`, three of
which are also copied into built example bundles.

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
