# Third-Party Licenses

metaphor redistributes third-party material in two places:

1. **`Syphon.xcframework`** — a compiled binary attached to each GitHub Release
   and consumed via a `binaryTarget` in `Package.swift`.
2. **Three fonts** — `.ttf` files carried in the repository under `Examples/`
   and `Tests/`, three of which are also copied into built example bundles.

This file reproduces the copyright notice and the license of each. The full SIL
Open Font License 1.1 text that covers the fonts is in [OFL.txt](OFL.txt) at the
repository root, reproduced verbatim from
[SIL](https://openfontlicense.org/documents/OFL.txt).

## Syphon-Framework

- **Project**: https://github.com/Syphon/Syphon-Framework
- **License**: Simplified BSD License (2-clause BSD)
- **Distributed as**: compiled `Syphon.xcframework` binary, attached to
  metaphor's GitHub Releases

The source is vendored as the `Vendor/Syphon-Framework` git submodule and
compiled by `scripts/build-syphon.sh`.

```
Syphon Framework License:

Copyright 2010 bangnoise (Tom Butterworth) & vade (Anton Marini).
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

* Neither the name of the Syphon Project nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Bundled fonts

Eleven `.ttf` files are checked into this repository. They are three distinct
fonts — every copy of a given font is byte-identical, as the SHA-256 below
shows. All three are licensed under the **SIL Open Font License, Version 1.1**;
the license text is in [OFL.txt](OFL.txt).

The attribution recorded here is transcribed from each font's own `name` table
(nameID 0 `copyright`, 8 `manufacturer`, 9 `designer`, 13 `licenseDescription`),
not from a secondary source.

`Tests/metaphorTests/FontLicenseTests.swift` re-derives this section from the
files on disk, so a font added without a matching entry — or an entry whose
SHA-256 has gone stale — fails `make test`.

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
