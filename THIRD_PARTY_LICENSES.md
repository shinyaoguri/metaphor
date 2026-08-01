# Third-Party Licenses

metaphor redistributes one third-party binary artifact as part of its GitHub
Releases: **Syphon.xcframework**, built from the
[Syphon-Framework](https://github.com/Syphon/Syphon-Framework) source (vendored
as the `Vendor/Syphon-Framework` git submodule and compiled by
`scripts/build-syphon.sh`). The resulting `Syphon.xcframework` is attached as a
binary asset to each GitHub Release and consumed via a `binaryTarget` in
`Package.swift`.

This file reproduces, verbatim, the license under which Syphon-Framework is
distributed.

## Syphon-Framework

- **Project**: https://github.com/Syphon/Syphon-Framework
- **License**: Simplified BSD License (2-clause BSD)
- **Distributed as**: compiled `Syphon.xcframework` binary, attached to
  metaphor's GitHub Releases

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
