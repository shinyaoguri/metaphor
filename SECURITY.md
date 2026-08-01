# Security Policy

## Supported Versions

metaphor is pre-1.0 (currently `v0.8.x`) and follows [GitHub Flow](CLAUDE.md)
with a single long-lived branch (`main`). Only the **latest published release**
is supported with security fixes; older releases do not receive backports.
Once v1.0.0 ships, this policy will be revisited (e.g. backporting fixes to the
latest major version).

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub Issues.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/shinyaoguri/metaphor/security)
   of this repository.
2. Click **"Report a vulnerability"** to open a private advisory.

This lets us discuss and fix the issue with you before any public disclosure.

If the vulnerability affects `metaphor-cli`
([shinyaoguri/metaphor-cli](https://github.com/shinyaoguri/metaphor-cli))
specifically, please report it there instead (or in addition, if it's unclear
which repository is affected — see [CONTRACT.md](CONTRACT.md) for how the two
repositories relate).

We aim to acknowledge reports within a few days and will keep you updated as
we investigate and address the issue.
