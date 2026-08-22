# Releasing (metaphor & metaphor-cli)

How releases are cut for **metaphor** (this repo) and the downstream
**metaphor-cli**. The summary lives in [CLAUDE.md](../CLAUDE.md) under *Branching
Workflow*; this file is the full procedure.

## Mechanism

Releases go through a single `workflow_dispatch` trigger on the **Release**
workflow. No PAT required — the workflow re-enters CI on its own release branch
using `workflow_dispatch` (which is exempt from the `GITHUB_TOKEN` recursion
guard).

> v0.12.0 から本体のリリースは **Syphon.xcframework の asset を持たず、metaphor-cli への pin dispatch も行いません**
> （#792 / [ADR-0014](adr/0014-viewer-frame-ipc-and-syphon-plugin.md)）。Syphon のビルド・asset・self-pin は独立パッケージ
> [metaphor-syphon](https://github.com/shinyaoguri/metaphor-syphon) の Release が担い、本体のタグは Swift のソースだけを指します。
> v0.11.0 以前のタグが持つ asset の扱いは「[配布防御](#配布防御タグと-release-asset)」に残してあります。

`release.yml` はリリースロジックの唯一の在処（バージョン定数の bump、タグ、GitHub Release）で、
その引き金を引くものが 3 つあります。**どれも `release.yml` 自体は変えず、
「出すかどうか」と「どれだけ上げるか」だけを決めます**:

| 引き金 | いつ | 何を決めるか |
|---|---|---|
| [`release-train.yml`](../.github/workflows/release-train.yml) | 毎週月曜 09:00 JST | 通常運用。`main` の履歴から bump を導く |
| [`release-on-merge.yml`](../.github/workflows/release-on-merge.yml) | `release:now` などのラベル付き PR がマージされた瞬間 | express（hotfix・major） |
| `release.yml` の `workflow_dispatch` | 手動 | prerelease（beta/rc）と復旧 |

バージョン bump のコミットは `git commit` ではなく GitHub の GraphQL
`createCommitOnBranch` で作ります（[`scripts/signed-commit.py`](../scripts/signed-commit.py)）。
main は**署名必須**（ruleset、2026-08-04 追加）で runner に署名鍵が無いため、
`git commit` した unsigned コミットではリリース PR をマージできず、**CI が終わったあとで**
止まります（2026-08-10 の v0.9.0 で実際に起きました。当時は 10 分の Syphon ビルドも無駄になりました）。
API 経由のコミットは GitHub 自身が署名するので、Actions に ruleset の bypass を
与える（＝他のすべてのルールも回避できるようになる）ことなくルールを満たせます。

## 週次リリーストレイン（the normal path）

**通常、リリースのために何もしません。** 毎週月曜 09:00 JST に
[`release-train.yml`](../.github/workflows/release-train.yml) が発車し、
前回の stable タグ以降に `main` へ入ったコミットから bump を決めて、
出すべきものがあるときだけ **Release** ワークフローを 1 本 dispatch します。

| 前回タグ以降に入ったもの | その週の発車 |
|---|---|
| `feat` が 1 本でもある | **minor** |
| `fix` / `perf` だけ | **patch** |
| `docs` / `chore` / `ci` / `refactor` / `test` だけ | **出ない**（次に feat/fix が入った週へ同乗） |
| 破壊的変更（後述） | **minor**（`0.x` の間。`1.0.0` 以降は**停車**して人を呼ぶ） |

判定は [`scripts/release-bump.py`](../scripts/release-bump.py) にあり、手元でも
同じ答えを確認できます:

```bash
python3 scripts/release-bump.py --explain
```

`main` は squash merge のみで、PR タイトルは Conventional Commits を
`ci.yml` が lint 済み。つまり `main` の各コミット subject は PR タイトルそのもので、
type がそのまま信用できます。**トレインは状態を持ちません** — マージ時に何も記録せず、
毎回履歴から bump を導き直すので、貼り忘れるラベルも、ずれるキューもありません。
週次の run が落ちても、翌週が同じ履歴から同じ結論に到達します。

### なぜトレインなのか

- **ラベル駆動は実際に機能していなかった。** v0.8.0 以降、`release:*` ラベルが付いた
  PR は 40 連続で 0 件、その間に feat 9 本・fix 10 本・`changelog.d/` 13 件が
  滞留しました。`gh pr merge --auto` は required checks が green になった瞬間に
  マージするので、ラベルを貼る安定した瞬間が構造的に存在しません。
- **マージごとのリリースは粒度が細かすぎる**（metaphor-cli はこの方式）。同じ 9 日間で
  19 リリースになる計算で、ライブラリの版数としては細かすぎます（v0.11.0 までは
  リリースのたびに Syphon.xcframework asset を焼いて metaphor-cli へ pin bump を
  dispatch していたので、下流にも 19 リリースが連鎖するところでした）。

### 破壊的変更は `0.x` のうちは minor に載せる（`1.0.0` から停車）

PR タイトルの `!` マーカー（`feat(core)!: ...`）か `changelog.d/*.breaking.md` を
見つけると、トレインは bump を**最低でも minor へ引き上げ**、`::warning::` で
「この minor には破壊的変更が乗っている」と内訳つきで注記して発車します。`0.x` の破壊は
minor に載せる規約だからです（[api-stability-policy.md](api-stability-policy.md) の
「Where each kind of change lands」表が正典・[ADR-0009](adr/0009-unfreeze-api-until-1-0.md)）。
`refactor(api)!:` のように**単独ではリリースを起こさない type**でも、破壊がある週は
minor が出ます — 旧名の削除が「どのリリースにも乗らない」状態を作らないためです。

**`1.0.0` 以降は同じマーカーが major を意味する**ので、そのときトレインは
**発車せず fail** します。major は自動で決めず、`release:major` で人が明示的に出します
（1.0 への昇格自体に非技術条件があり、技術判断だけで到達してはいけない —
[v1-release-plan.md](design/v1-release-plan.md)）。どちらの規約が効くかは
**直近の stable タグから読む**ので、`v1.0.0` が出た瞬間に自動で厳しくなります
（`release-bump.py` を人が直す必要はありません）。

破壊のたびに要求されるものは版に関係なく同じで、CHANGELOG の `### Breaking Changes` と
移行表です。それは PR 側で `changelog.d/*.breaking.md` として書きます。

停車はもう 1 つ、`changelog.d/` が空のまま feat/fix が溜まったときにも起きます
（発車前の `changelog.py check` で止まる）。ただしこちらはもう滅多に起きません —
feat/fix/perf の PR にエントリが無ければ per-PR CI がその場でブロックするようになったので
（Issue #461）、月曜のトレインまで持ち越されるのは `no-changelog` を貼った
PR ばかりが続いた週だけです。**停車に気付ける前提は GitHub の Actions 失敗通知**
なので、リリース系ワークフローの失敗が手元に届く設定になっているかは一度確認しておきます。

## 急ぐとき（express: `release:now`）

月曜を待てない hotfix は、PR にラベルを貼ってマージすれば即座に出ます
（[`release-on-merge.yml`](../.github/workflows/release-on-merge.yml)）。

| ラベル | bump |
|---|---|
| `release:now` | PR タイトルから推定（`feat` → minor / `fix`・`perf` → patch / それ以外 → patch） |
| `release:patch` / `release:minor` / `release:major` | そのラベルどおり。**major を出す唯一の手段** |

ラベルの無い PR は普通にマージされ、次のトレインに乗ります（＝通常運用）。
Release ワークフロー自身が開く "Release vX.Y.Z" PR は無ラベルなので、
express を再帰的に起こしません（ループ無し）。

> **express を使うときだけ、auto-merge を arm する *前* にラベルを貼る。** `--auto` で
> arm した PR は green の瞬間にマージされ、`release-on-merge.yml` はマージ時点の
> ラベルしか見ません。貼り損ねても失われるのは即時性だけで、変更は次のトレインに
> 乗ります（急ぐなら Release ワークフローを手で `workflow_dispatch`）。

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
- **リリースは auto-merge と衝突しない。** マージ時点で決まることは何も無く、
  次のトレインが `main` の履歴から bump を導きます。arm する前に何かを貼る必要が
  あるのは express（`release:now`）のときだけです。
- **Only required checks gate the merge.** Required = the single aggregate
  gate **`ci-gate`** (Issue #411). It `needs:` every job in `ci.yml`
  (`build-and-test`, `build-swift-5-10`, `website-build`, `examples-detect`,
  `examples-diff-build`), always runs, and fails if any of them failed —
  skipped jobs count as success. (`asset-health.yml` never runs on PRs — it is
  a weekly cron. `docs.yml` only runs on `push: main`; the Astro build it
  performs *is* covered per-PR by `website-build`, but the DocC build and the
  Pages deploy are not — Issue #491.) Consequences worth knowing:
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
`Sources/metaphor/metaphor.docc/GettingStarted.md`, `llms.txt`,
`website/src/components/Hero.astro`.

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
| **PR ごと**(`ci.yml` の *Lint changelog.d entries*) | `changelog.py lint` — 置かれたファイルの**名前と中身だけ**を検証(カテゴリ typo・区切りなし・`.md` 以外・空ファイル)。**エントリの有無は問わない**。`build-and-test` のステップとして走り、その失敗は required check `ci-gate` が fail に畳むのでマージをブロックする | **PR がマージ不能**。typo を書いた本人がその場で直す(Issue #405 — 以前はリリース時まで発覚しなかった) |
| **PR ごと**(`ci.yml` の *Require a changelog.d entry for user-facing PRs*) | `require-changelog-entry.py` — 有無の方を見る。PR タイトルの type が**単独でリリースを起こす**(`feat` / `fix` / `perf`。判定は `release-bump.py` の `BUMP_BY_TYPE` を import して共有)か `!` 付きなら、`changelog.d/` にファイルを追加していることを要求する。判断は書き手に残っており、`no-changelog` ラベルを貼れば通る | **PR がマージ不能**。エントリを足すか `no-changelog` を貼る。どちらもタイトル・ラベルを API から読むので `gh run rerun --failed <run-id>` だけで通る(Issue #461 — 以前は下の 2 つで週明けに発覚していた) |
| 発車前(`release-train.yml` の *Require CHANGELOG entries*) | 同じ `changelog.py check`。bump が決まった週だけ走る | **トレインが fail**。dispatch されないので Release ワークフローは起動しない。エントリを足して手で `workflow_dispatch`(dry_run=false)するか、翌週に乗せる |
| ジョブ冒頭(*Require CHANGELOG entries*) | `changelog.py check` — `changelog.d/` にエントリがあるか、`## [Unreleased]` の中身が空でないこと(両対応)。ファイル名の不備(カテゴリ不明・区切りなし・`.md` 以外・空ファイル)もここで弾く | **リリース中断**。タグ発行前なので損失なし |
| *Push release branch*(stable のみ) | `changelog.py release <version>` — まず `changelog.d/*.md` を `## [Unreleased]` へ集約してファイルを削除し、続けて `## [X.Y.Z] - YYYY-MM-DD` へ昇格、空の Unreleased を上に開き、末尾のリンク定義を更新。**削除も含めて**バージョンバンプと同じコミットに入る(`git add ... changelog.d`) | 同上(タグ前) |
| *Compose release notes* | `changelog.py notes <section>` — 該当節を `## Highlights` として `$RUNNER_TEMP/release-body.md` に書く。`unreleased` 指定時は未集約の `changelog.d/` も表示用に畳み込む。`Create Release` は `body_path` でこれを読む | **落とさない設計**。notes は常に exit 0 で、最悪ハイライトが出ないだけ(タグ発行後に落ちるステップを増やさないため) |

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

## リリースは Homebrew に届いて完了(下流への波及)

> 3 リポジトリ（metaphor / metaphor-cli / homebrew-tap）の依存関係・付番規則・
> 資格情報まで含めた全体地図は [release-pipeline.md](release-pipeline.md)。
> 本節はこのリポジトリ視点での要約です。

v0.12.0 以降、本体のタグを打った時点で**ライブラリのリリースは完結**しています。
metaphor-cli は本体に SwiftPM 依存せず（Syphon.framework の同梱も無い）、スケッチ側が
`.package(url:from:)` で本体の版を解決するだけなので、本体のリリースが下流のリリースを
起こすことはありません。下流はそれぞれ自分の都合で出ます:

| 下流 | いつ出るか | 本体との結びつき |
|---|---|---|
| [metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) | 自分のマージごと（`release-on-merge.yml`） | `metaphor new` が生成時に本体の最新 Release を `from:` の下限に使う（リリースビルドは `BuildInfo.defaultMetaphorVersion` を最新安定版へ pin）。本体の**最小版**は `BuildInfo.minimumMetaphorVersionForViewer` が持ち、`doctor` / `watch` が案内する |
| [metaphor-syphon](https://github.com/shinyaoguri/metaphor-syphon) | 自分のタグ駆動 | 本体を `from:` で参照し、本体 `main` への互換ビルドを自前の CI で毎晩確認。本体の minor が plugin / provider API を壊したときだけ追随リリースが要る |
| homebrew-tap | metaphor-cli のリリースから Formula 更新 PR（bottle 込みで main へ） | 本体は関与しない |

metaphor-cli → homebrew-tap の 1 段は metaphor-cli の `release-pipeline-audit.yml`
（`scripts/audit-release-pipeline.py`）が毎日確かめ、48 時間経っても届いていなければ Issue を
立てます。手順・GitHub App に必要な権限・bottle の扱いは metaphor-cli の `docs/homebrew.md` が正本です。

v0.11.0 までは本体のリリースが `repository_dispatch` で metaphor-cli の Syphon pin bump PR を起こし、
cli のリリース → tap まで 4 段が連鎖していました（段 1 の資格情報が一度も設定されず `v0.9.0` まで
黙って skip していた事故も含め、経緯は metaphor-cli の [ADR 0003](https://github.com/shinyaoguri/metaphor-cli/blob/main/docs/decisions/0003-syphon-pin-automation.md)
→ [ADR 0014](https://github.com/shinyaoguri/metaphor-cli/blob/main/docs/decisions/0014-viewer-frame-ipc-drops-syphon-bundle.md)）。

## 配布防御(タグと Release asset)

> **v0.12.0 以降のタグは Release asset を持たない**（root の `Package.swift` に binaryTarget が無い。
> `scripts/check-no-binary-targets.sh` が CI で守る）。以下は **v0.11.0 以前のタグの asset を守る**ための規則で、
> それらの asset は今後も消さない（`from: "0.x"` の利用者が resolve できなくなる）。週次の
> `asset-health.yml` は binaryTarget を持つタグだけを検査し、持たないタグは SKIP と報告する。

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
| リリース時（v0.11.0 まで） | 公開した asset を実際にダウンロードし、Package.swift に書いた checksum と照合 | 旧 `release.yml` の *Verify published Syphon asset* ステップ（v0.12.0 で撤去。metaphor-syphon の Release が同等の検証を持つ） |
| 週次(月曜 05:00 JST) | 全 `v*` タグの binaryTarget URL が 200 を返すか | `.github/workflows/asset-health.yml` → `scripts/check-release-assets.sh` |
| 毎日(16:00 JST) | metaphor-cli の最新リリースが homebrew-tap の Formula まで届いたか（本体は対象外） | metaphor-cli `release-pipeline-audit.yml` → `scripts/audit-release-pipeline.py` |

手元でも同じチェックを走らせられる:

```bash
./scripts/check-release-assets.sh          # 全 v* タグ
./scripts/check-release-assets.sh v0.8.0   # 特定タグだけ
```

### 事故ったときの復旧

- **asset が消えた / 上がらなかった**: タグを触らずに asset を貼り直す。
  Release への asset 追加はタグ操作ではないので ruleset に阻まれない。

  ```bash
  gh release upload <tag> Syphon.xcframework.zip --clobber
  ```

  元の zip が手元に無い場合、そのタグの checkout にある `Vendor/Syphon-Framework`
  submodule と `scripts/build-syphon.sh`（v0.11.0 以前のタグにだけ存在。現行 `main` には無い）で
  再ビルドしても、Package.swift の checksum と一致する保証はない(ビルド非決定性)。
  **まず既存 asset を消さないことが唯一の防御**。
- **どうしてもタグ操作が必要**: bypass actor は設定していないので、
  リポジトリ設定 → Rules → *tag protection* の Enforcement を一時的に
  Disabled にしてから操作し、直後に Active へ戻す(意図的・記録が残る手順にしてある)。
