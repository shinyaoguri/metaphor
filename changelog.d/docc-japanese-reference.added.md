- The API reference is now published in Japanese as well, at
  [`/reference/ja/`](https://shinyaoguri.github.io/metaphor/reference/ja/documentation/metaphor/),
  alongside the English one. English doc comments stay the canonical source; the Japanese
  pages are a generated artifact built by applying a translation ledger
  (`docs/reference/i18n/ja.json`) to the DocC output, so declarations, parameter tables and
  code samples are never touched. Passages without a translation yet are shown in English.
  Each page carries a language link in its header. See
  [ADR-0011](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0011-docc-english-canon-japanese-generated.md)
  for the reasoning and the known limits (DocC's own UI labels stay English, and the link
  goes to the other language's top page rather than the current page).
