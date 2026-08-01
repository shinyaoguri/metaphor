# Releasing (metaphor & metaphor-cli)

How releases are cut for **metaphor** (this repo) and the downstream
**metaphor-cli**. The summary lives in [CLAUDE.md](../CLAUDE.md) under *Branching
Workflow*; this file is the full procedure.

## Mechanism

Releases go through a single `workflow_dispatch` trigger on the **Release**
workflow. No PAT required — the workflow re-enters CI on its own release branch
using `workflow_dispatch` (which is exempt from the `GITHUB_TOKEN` recursion
guard).

## Label-driven releases (the normal path)

Releases are cut by **labeling a PR**, not by a separate branch:

1. On the PR you want to ship, add one label: `release:patch` / `release:minor`
   / `release:major`.
2. Merge it (squash). `release-on-merge.yml` reads the label and dispatches the
   **Release** workflow with that bump, which builds, bumps versions, tags, and
   publishes:
   - **metaphor** → git tag + GitHub Release (SPM) + Syphon-pin dispatch to metaphor-cli.
   - **metaphor-cli** → tarballs + Homebrew formula pushed to `shinyaoguri/homebrew-tap`.
3. A PR **without** a `release:*` label merges normally and does **not** release.
   (The Release workflow's own "Release vX.Y.Z" PR is unlabeled, so it never
   re-triggers a release — no loop.)

Pre-releases (beta/rc) are cut manually via the Release workflow's
`workflow_dispatch` (`bump=prerelease` etc.).

## Manual dispatch inputs

| Input | Purpose |
|-------|---------|
| `bump` | `patch` / `minor` / `major` / `prerelease` |
| `prerelease_label` | `beta`, `rc`, etc. Empty for stable. Ignored when `bump=prerelease`. |

## Common operations

| Goal | Inputs | Resulting tag |
|------|--------|---------------|
| Stable patch | `bump=patch`, label empty | `v0.2.4` |
| Start a beta cycle | `bump=minor`, `label=beta` | `v0.3.0-beta.1` |
| Iterate the beta | `bump=prerelease` | `v0.3.0-beta.2` |
| Promote to RC | `bump=minor`, `label=rc` | `v0.3.0-rc.1` |
| Graduate to stable | `bump=minor`, label empty | `v0.3.0` |

Pre-release tags (anything containing `-`) are automatically marked as
Pre-release on GitHub. The `Package.swift` `from:` example in the README is only
updated for stable releases.

## 配布防御(タグと Release asset)

公開済みのタグと Release asset は **不変** として扱う。理由は SwiftPM の
`binaryTarget(url:)` にある — 依存解決のたびに Release asset(`Syphon.xcframework.zip`)
を実際に取りに行くため、**asset を消すとそのタグは恒久的に resolve 不能**になる。
新規利用者だけでなく、そのバージョンを使っている既存利用者も同時に壊れる。
タグの付け替えも同様に、Package.swift に書かれた checksum との対応が崩れる
(あるいは checksum ごと差し替わる)サプライチェーン改変になる。

### 守るべきこと

- **Release asset は削除しない。** 古いバージョンの整理・容量削減目的でも消さない。
  Release ページを非公開(draft)にするのも不可 — asset URL が 404 になる。
- **タグは削除・付け替えしない。** `refs/tags/v*` は ruleset
  ([tag protection](https://github.com/shinyaoguri/metaphor/rules))で
  deletion / update / non-fast-forward を禁止済み。新規タグの作成のみ許可されるので、
  release.yml のタグ push は通る。
- リリースをやり直したくなっても、タグを消して振り直すことはできない。
  **次のパッチバージョンを切る**のが正しい対処。

### v0.2.2 の既知の欠損(触ってはいけない箇所)

`v0.2.2` の Release には asset が 1 つも無い。当時アップロードに失敗したまま
タグが打たれたためで、`v0.2.2` の Package.swift は **`v0.2.1` の asset URL を
参照している**(間借り)。

つまり **`v0.2.1` の asset を消すと v0.2.1 と v0.2.2 の 2 つのタグが同時に壊れる**。
また、死活監視は「タグ名と同名の Release に asset があるか」ではなく
「そのタグの Package.swift が実際に参照している URL が 200 を返すか」で見る必要がある
(前者だと v0.2.2 を誤検知する)。

### 監視と自動チェック

| いつ | 何を | どこ |
|------|------|------|
| リリース時 | 公開した asset を実際にダウンロードし、Package.swift に書いた checksum と照合 | `release.yml` の *Verify published Syphon asset* ステップ(metaphor-cli への pin 通知より前に落ちる) |
| 週次(月曜 05:00 JST) | 全 `v*` タグの binaryTarget URL が 200 を返すか | `.github/workflows/asset-health.yml` → `scripts/check-release-assets.sh` |

手元でも同じチェックを走らせられる:

```bash
./scripts/check-release-assets.sh          # 全 v* タグ
./scripts/check-release-assets.sh v0.8.0   # 特定タグだけ
```

### 事故ったときの復旧

- **asset が消えた / 上がらなかった**: タグを触らずに asset を貼り直す。
  Release への asset 追加はタグ操作ではないので ruleset に阻まれない。

  ```bash
  gh release upload <tag> Frameworks/Syphon.xcframework.zip --clobber
  ```

  元の zip が手元に無い場合、そのタグの Syphon submodule を
  `./scripts/build-syphon.sh` で再ビルドしても、Package.swift の checksum と
  一致する保証はない(ビルド非決定性)。**まず既存 asset を消さないことが唯一の防御**。
- **どうしてもタグ操作が必要**: bypass actor は設定していないので、
  リポジトリ設定 → Rules → *tag protection* の Enforcement を一時的に
  Disabled にしてから操作し、直後に Active へ戻す(意図的・記録が残る手順にしてある)。
