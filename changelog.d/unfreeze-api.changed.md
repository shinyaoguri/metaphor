- **The API freeze announced with `v0.9.0` has been withdrawn.** Design work was
  still outstanding when it shipped — renamed APIs whose old spellings are still
  deprecated-but-present, and undecided Processing-compatibility semantics — and
  the freeze made that work unreachable
  ([ADR-0009](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0009-unfreeze-api-until-1-0.md),
  [#477](https://github.com/shinyaoguri/metaphor/issues/477)). Until `1.0.0`, a
  breaking change may ship in a **minor** release when the design justifies it:
  - Deprecation stays the default path — a symbol is marked
    `@available(*, deprecated, renamed:)` in one published release before it is
    removed — and every breaking change still gets a `### Breaking Changes`
    entry with a migration table.
  - Nothing changes for runtime contracts (Probe wire schema, stdin protocol,
    contract environment variables) or for rendering-output disclosure.
  - Pin `.upToNextMinor(from: "0.9.0")` if you would rather not take breaking
    changes automatically. `v1.0.0` is where the freeze actually begins.
