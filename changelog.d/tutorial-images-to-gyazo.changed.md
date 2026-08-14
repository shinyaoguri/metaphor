- The tutorial's 65 images no longer live in the repository. They are hosted on
  Gyazo, and `docs/tutorial/` now carries only the prose and a ledger
  (`docs/tutorial/images/manifest.json`) recording the immutable URL and content
  hash each section points at. Nothing changes for readers: the tutorial site
  still serves locally optimized images (Astro fetches and re-encodes them at
  build time, animation intact), and the Markdown still renders on GitHub. What
  changes is how a retake works — `make tutorial-shots` now captures, uploads,
  and rewrites the URLs in the prose for you, so never edit an image URL by
  hand. Assets are append-only: a retake publishes a new URL and leaves the old
  one alive, so checking out an older revision still shows the pictures that
  revision was written against. Two consequences worth knowing: images do not
  render offline, and a fork cannot replace one without a maintainer uploading
  it. Rationale and the measurements behind it are in
  [ADR-0010](../docs/adr/0010-tutorial-images-via-gyazo.md)
  ([#511](https://github.com/shinyaoguri/metaphor/issues/511))
