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

**どのラベルを貼るか**は [api-stability-policy.md](api-stability-policy.md) の
「Where each kind of change lands」表が正典（公開 API の削除・改名 = major、追加と
deprecation = minor、描画結果や実行時契約の破壊的変更 = minor 以上で `Breaking
Changes` 記載、最小サポート引き上げ = minor）。

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
Pre-release on GitHub. The `from:` install snippet is bumped only for stable
releases, across every file that carries it: `README.md`, `README.en.md`,
`Sources/metaphor/metaphor.docc/GettingStarted.md`, `llms.txt`.

That file set lives in two places that must always change together — the sed in
`release.yml`'s *Push release branch* step, and `version_docs` in
`scripts/validate-ai-docs.sh` (check #6, which compares every entry against
`README.md`). Adding a file to only one side deadlocks releases: listed in the
validator alone, it is checked but never bumped; listed in the sed alone, it is
bumped but free to drift back.

## CHANGELOG とリリースノート(Issue #335)

[CHANGELOG.md](../CHANGELOG.md) は [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
形式で、**ユーザー影響のある PR が `## [Unreleased]` に 1 行足す**運用。リリース時の
昇格と Release 本文への転記は `scripts/changelog.py` が行い、`release.yml` から
3 か所で呼ばれる。

| いつ | 何を | 失敗したら |
|------|------|-----------|
| ジョブ冒頭(*Require CHANGELOG entries*) | `changelog.py check` — `## [Unreleased]` が存在し、中身が空でないこと | **リリース中断**。Syphon ビルド前・タグ発行前なので損失なし |
| *Push release branch*(stable のみ) | `changelog.py release <version>` — `## [Unreleased]` を `## [X.Y.Z] - YYYY-MM-DD` へ昇格し、空の Unreleased を上に開き、末尾のリンク定義を更新。バージョンバンプと同じコミットに含める | 同上(タグ前) |
| *Compose release notes* | `changelog.py notes <section>` — 該当節を `## Highlights` として `$RUNNER_TEMP/release-body.md` に書き、Syphon checksum を足す。`Create Release` は `body_path` でこれを読む | **落とさない設計**。notes は常に exit 0 で、最悪ハイライトが出ないだけ(タグ発行後に落ちるステップを増やさないため) |

設計上の約束:

- **ゲートは中断であって警告ではない。** 「何が変わったか」を書けないリリースは出さない。
  ただし止まるのは冒頭ステップなので、直して再 dispatch するだけでよい。
- **本当にユーザー影響が無いリリース**(asset の焼き直し等)は、その旨を明示的に書けば通る:

  ```markdown
  ### Changed

  - _No user-facing changes._
  ```

- **昇格は stable のみ。** prerelease(`-beta.N` 等)は `## [Unreleased]` を消費せず、
  Release 本文にはその時点の Unreleased をプレビュー表示する。サイクル中の変更は
  stable へ昇格したときに一括で 1 節になる。
- リリース済みの節は手で編集しない(Unreleased だけを触る)。

手元で挙動を確かめる(実ファイルは触らない):

```bash
python3 scripts/changelog.py check                       # ゲートと同じ判定
cp CHANGELOG.md /tmp/sim.md
python3 scripts/changelog.py --path /tmp/sim.md release 0.9.0 --date 2026-09-01
diff -u CHANGELOG.md /tmp/sim.md                         # 昇格結果の確認
python3 scripts/changelog.py --path /tmp/sim.md notes 0.9.0   # Release 本文の Highlights
```

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
