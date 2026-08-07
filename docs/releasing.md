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

> **auto-merge を使うときは、arm する *前* にラベルを貼る。** `--auto` で arm した
> PR は required checks が green になった瞬間にマージされるので、armed → green →
> merge の隙間にラベルを付け損ねると無ラベルのままマージされ、リリースは走らない
> (`release-on-merge.yml` はマージ時点のラベルしか見ない)。取り返すには Release
> ワークフローを手で `workflow_dispatch` する。

Pre-releases (beta/rc) are cut manually via the Release workflow's
`workflow_dispatch` (`bump=prerelease` etc.).

## Merging PRs (auto-merge)

Instead of waiting for CI and merging manually:

```
gh pr merge <number> --squash --auto
```

GitHub merges automatically once the required checks on the PR's own head
pass. Consequences and rationale:

- **No need to keep branches up to date.** The ruleset's
  `strict_required_status_checks_policy` is **off** (2026-08-02): a `BEHIND`
  PR merges as-is, so concurrent PRs no longer serialize on
  update-branch → CI re-run → merge. Textual conflicts still block the merge
  (GitHub's `DIRTY` state), and semantic conflicts between independently green
  PRs are caught by the `push: main` CI run right after the merge — if main
  goes red, fix forward with a follow-up PR.
- Release labeling is unaffected: auto-merge performs a normal squash merge,
  so `release-on-merge.yml` (`pull_request: closed`) fires as before. Label
  **before** arming (see the note above).
- **Only required checks gate the merge.** Required = the single aggregate
  gate **`ci-gate`** (Issue #411). It `needs:` every job in `ci.yml`
  (`build-and-test`, `build-swift-5-10`, `examples-detect`,
  `examples-diff-build`), always runs, and fails if any of them failed —
  skipped jobs count as success. (`docs.yml` and `asset-health.yml` never run
  on PRs — `push: main` and a weekly cron respectively.) Consequences worth
  knowing:
  - A PR that does not touch `Examples/` merges as soon as the fast jobs are
    green (`build-and-test` ~6 min); `examples-diff-build` is skipped and the
    gate folds the skip into success. A PR that *does* touch `Examples/`
    waits for the changed examples to build (up to 60 min) — a PR that breaks
    an example no longer merges.
  - Individual jobs must **not** be made required directly. Conditional jobs
    report nothing to the legacy Statuses API when skipped, and this
    personal-repo ruleset appears to evaluate `required_status_checks` against
    legacy statuses — a skipped required job would leave the PR pending
    forever. `ci-gate` sidesteps this by always running and always reporting;
    adding a new job only requires appending it to `ci-gate`'s `needs:`, not
    touching the ruleset.
  - Checks that must block *fast* are still written as **steps inside
    `build-and-test`** — the PR-title Conventional-Commits lint and the
    `changelog.d` lint both live there, failing within seconds instead of
    after a full build.
- A true **merge queue** would be strictly better (it tests each PR merged
  onto latest main before merging), but the `merge_queue` ruleset rule is
  rejected on user-owned repositories (422 "Invalid rule", verified
  2026-08-02) — it is an organization-plan feature. `ci.yml` already carries
  the `merge_group` trigger and legacy-status bridges, so if this repo ever
  moves to an organization, enabling the queue is a ruleset-only change.

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
形式。**ユーザー影響のある PR は CHANGELOG.md を直接編集せず、[`changelog.d/`](../changelog.d/README.md)
に 1 変更 = 1 ファイル(`<slug>.<category>.md`)を置く**運用(towncrier 方式)。理由は
conflict — 全 PR が `## [Unreleased]` の同じ行を触ると、並行 PR がほぼ毎回衝突していた。
新しいファイルは誰とも衝突しない。集約(collect)・昇格・Release 本文への転記は
`scripts/changelog.py` が行い、`release.yml` から 3 か所で呼ばれる。

| いつ | 何を | 失敗したら |
|------|------|-----------|
| **PR ごと**(`ci.yml` の *Lint changelog.d entries*) | `changelog.py lint` — 置かれたファイルの**名前と中身だけ**を検証(カテゴリ typo・区切りなし・`.md` 以外・空ファイル)。**エントリの有無は問わない**(内部作業は正当にエントリ無し)。`build-and-test` のステップとして走り、その失敗は required check `ci-gate` が fail に畳むのでマージをブロックする | **PR がマージ不能**。typo を書いた本人がその場で直す(Issue #405 — 以前はリリース時まで発覚しなかった) |
| ジョブ冒頭(*Require CHANGELOG entries*) | `changelog.py check` — `changelog.d/` にエントリがあるか、`## [Unreleased]` の中身が空でないこと(両対応)。ファイル名の不備(カテゴリ不明・区切りなし・`.md` 以外・空ファイル)もここで弾く | **リリース中断**。Syphon ビルド前・タグ発行前なので損失なし |
| *Push release branch*(stable のみ) | `changelog.py release <version>` — まず `changelog.d/*.md` を `## [Unreleased]` へ集約してファイルを削除し、続けて `## [X.Y.Z] - YYYY-MM-DD` へ昇格、空の Unreleased を上に開き、末尾のリンク定義を更新。**削除も含めて**バージョンバンプと同じコミットに入る(`git add ... changelog.d`) | 同上(タグ前) |
| *Compose release notes* | `changelog.py notes <section>` — 該当節を `## Highlights` として `$RUNNER_TEMP/release-body.md` に書き、Syphon checksum を足す。`unreleased` 指定時は未集約の `changelog.d/` も表示用に畳み込む。`Create Release` は `body_path` でこれを読む | **落とさない設計**。notes は常に exit 0 で、最悪ハイライトが出ないだけ(タグ発行後に落ちるステップを増やさないため) |

設計上の約束:

- **集約はリリース時。** マージ時ではない。`main` の `CHANGELOG.md` は前回リリース時点の姿で、
  次に何が出るかは `changelog.d/` を見る(`changelog.py collect` を手元で回せば結果を確認できる)。
- **出力は決定的。** カテゴリは `breaking` → `added` → `changed` → `deprecated` → `removed` →
  `fixed` → `security` の固定順、同一カテゴリ内はファイル名順。既存の `## [Unreleased]` の
  中身は保存し、同名の見出しがあれば末尾に追記する。
- **ゲートは中断であって警告ではない。** 「何が変わったか」を書けないリリースは出さない。
  ただし止まるのは冒頭ステップなので、直して再 dispatch するだけでよい。
- **本当にユーザー影響が無いリリース**(asset の焼き直し等)は、その旨を明示的に書けば通る。
  `changelog.d/no-user-facing-changes.changed.md` に:

  ```markdown
  - _No user-facing changes._
  ```

- **昇格は stable のみ。** prerelease(`-beta.N` 等)は `changelog.d/` も `## [Unreleased]` も
  消費せず、Release 本文にはその時点の pending をプレビュー表示する。サイクル中の変更は
  stable へ昇格したときに一括で 1 節になる。
- リリース済みの節は手で編集しない。`## [Unreleased]` への直接記入は残してあるが(移行期と
  hotfix 用の逃げ道。`check` / `collect` / `notes` は両対応)、通常は `changelog.d/` を使う。

手元で挙動を確かめる(実ファイルは触らない):

```bash
python3 scripts/changelog.py lint                        # per-PR CI と同じ判定(名前と中身のみ)
python3 scripts/changelog.py check                       # リリースゲートと同じ判定(有無も見る)
rm -rf /tmp/sim && mkdir /tmp/sim
cp -R CHANGELOG.md changelog.d /tmp/sim/
python3 scripts/changelog.py --path /tmp/sim/CHANGELOG.md --dir /tmp/sim/changelog.d collect
diff -u CHANGELOG.md /tmp/sim/CHANGELOG.md               # 集約結果の確認
python3 scripts/changelog.py --path /tmp/sim/CHANGELOG.md --dir /tmp/sim/changelog.d release 0.9.0 --date 2026-09-01
python3 scripts/changelog.py --path /tmp/sim/CHANGELOG.md --dir /tmp/sim/changelog.d notes 0.9.0   # Release 本文の Highlights
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
