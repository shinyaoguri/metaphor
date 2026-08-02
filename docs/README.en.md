# docs/ — Documentation Map

**English** | [日本語](README.md)

metaphor's documentation is organized by "who's reading, and why." Start with
this table.

## Entry Points By Reader

| Reader | Goal | Read |
|---|---|---|
| Writing sketches | Build artwork with metaphor | [README](../README.en.md) → [ai/for-sketch-authors.md](ai/for-sketch-authors.md) → [ai/examples-index.md](ai/examples-index.md) |
| Working through Examples in order | Want a starting sequence, not a 278-entry index | [Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md) (curated route using the existing difficulty tags) |
| Coming from Processing / p5.js | Look up "the Processing X is metaphor's Y" | [processing-migration-guide.md](processing-migration-guide.md) (API mapping tables, pitfalls, what is not implemented yet) |
| Writing a sketch that uses the microphone or camera | Understand the permission dialog, and what to do if it was denied | [permissions.md](permissions.md) (how TCC works and how to recover) |
| Building with AI | Iterate while an AI agent observes the running sketch | [README "Collaborating with AI"](../README.en.md#collaborating-with-ai-observation--manipulation--iteration) → [metaphor-cli's "Collaborating with AI"](https://github.com/shinyaoguri/metaphor-cli#collaborating-with-ai) → [ai/prompts/](ai/prompts/) |
| Developing the library itself | Change metaphor's own code | [DEVELOPMENT.md](../DEVELOPMENT.md) → [ai/README.md](ai/README.md) (implementation/debugging notes, invariants) → [adr/](adr/) |
| AI agents | Working in this repository | [CLAUDE.md](../CLAUDE.md) (entry point) → delegates to individual files |
| Cross-repo changes | Touching the metaphor ⇄ metaphor-cli contract | [CONTRACT.md](../CONTRACT.md) |
| Cutting a release | Ship a release | [releasing.md](releasing.md) |

## Directory Layout

- **[ai/](ai/)** — AI-assistance documentation
  - [ai/README.md](ai/README.md) — Implementation/debugging notes and invariants (for library developers and AI agents)
  - [ai/for-sketch-authors.md](ai/for-sketch-authors.md) — Guide for writing sketches together with AI
  - [ai/install-scenarios.md](ai/install-scenarios.md) — How AI assistance behaves across install scenarios
  - [ai/examples-index.md](ai/examples-index.md) / `.json` — Full example index (**generated**; do not hand-edit)
  - [ai/prompts/](ai/prompts/) — Prompt templates by use case (audio-reactive / shader, etc.)
- **[processing-migration-guide.md](processing-migration-guide.md)** — Processing / p5.js migration guide: API mapping tables by category, the pitfalls that bite, and the Processing APIs that are not implemented yet (with roadmap links)
- **[permissions.md](permissions.md)** — Microphone/camera TCC permissions: how permission requests work for a `swift run` binary, recovering from a denial, and how Info.plist is (and isn't) involved
- **[adr/](adr/)** — Architecture Decision Records: an append-only log of design decisions. See [adr/README.md](adr/README.md) for the format
- **[design/](design/)** — Design docs for in-progress / past projects. The implementation and [CONTRACT.md](../CONTRACT.md) are the source of truth for settled specs; these documents stay Japanese (see the language boundary below)
  - [design/roadmap-processing-unity.md](design/roadmap-processing-unity.md) — Roadmap for attracting Processing / Unity users (living document, Epic list)
  - [design/live-tooling-params.md](design/live-tooling-params.md) — Design draft for the Parameter Store / stateful reload / inspector
  - [design/v1-release-plan.md](design/v1-release-plan.md) — v1.0.0 release readiness plan (review findings, prep tracks, release criteria)
- **[releasing.md](releasing.md)** — Release procedure (driven by a PR's `release:*` label), plus CHANGELOG promotion and release-note generation

The repository root also has [CHANGELOG.md](../CHANGELOG.md) (user-facing change
history, Keep a Changelog format, English; a user-impacting pull request
updates `## [Unreleased]`), and Examples has
[Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md) (a curated "learn in
order" route built from the existing difficulty tags).

## English Translation Scope (Wave 1 · Issue #286)

As a track running alongside the roadmap's Processing/Unity user-acquisition
effort (Epic I), English documentation is maintained within this scope:

- **Provided in English**: [README.en.md](../README.en.md) (the entry point, including the 60-second start and Getting Started; cross-linked with README.md), inline code comments under `Examples/**`, the `description` field in `docs/ai/examples-index.md` (the source example metadata is English), this page ([docs/README.en.md](README.en.md), added for Issue #337), and [permissions.md](permissions.md) / [Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md) / [processing-migration-guide.md](processing-migration-guide.md) (new, English-only)
- **Stays Japanese** (not translated): all of [adr/](adr/) (a record of design decisions; translating every ADR is a non-goal), [design/](design/), and developer/agent-facing internal docs such as [CLAUDE.md](../CLAUDE.md) and [ai/README.md](ai/README.md)
- **Future waves**: Wave 2 = translating public API doc comments (synergizes with cli #86), Wave 3 = the website (#74). Filed as issues when work starts on each

## Source Of Truth

| If you want to know | Source of truth |
|---|---|
| Public API signatures | [`llms.txt`](../llms.txt) (generated) |
| Rationale for a design decision | [adr/](adr/) |
| The metaphor ⇄ metaphor-cli contract | [CONTRACT.md](../CONTRACT.md) and `contract/*.schema.json` |
| Codebase conventions | [CLAUDE.md](../CLAUDE.md) and [ai/README.md](ai/README.md) |
| Setup and build | [DEVELOPMENT.md](../DEVELOPMENT.md) |
