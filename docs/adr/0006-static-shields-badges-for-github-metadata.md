# ADR-0006: GitHub メタデータ参照バッジを静的化する（shields.io 動的バッジの不安定性回避）

- **Status**: Accepted
- **Date**: 2026-07-03
- **Deciders**: PR で確定
- **PR / Commit**: 本 PR

## Context

README 冒頭のバッジのうち、license バッジは `img.shields.io/github/license/...`、version バッジは `img.shields.io/github/v/release/...` という **shields.io の動的バッジ**を使っていた。これらは shields.io が未認証で GitHub API を叩いて値を取得する。

shields.io は世界中の利用者で GitHub API の匿名レート制限（60 req/h）を共有しており、これを超過すると GitHub 依存バッジが一斉に `invalid` を表示する。実際に README でも version / license の 2 つだけが断続的に `invalid` になる事象が観測された（GitHub 側のデータ — PUBLIC / v0.5.2 リリース / MIT 認識 — はいずれも正常で、リポジトリ側の問題ではない）。

一方、同じ README でも Swift / Platform バッジは `img.shields.io/badge/...` の**静的バッジ**、CI バッジは GitHub Actions の `badge.svg` 直参照で、いずれもこの不安定性の影響を受けない。

## Considered Options

### Option A: 放置する（動的バッジのまま）
- Pros: リリース連動が自動。手を加えない。
- Cons: レート制限に依存し、断続的に `invalid` 表示が出続ける。バッジは第一印象であり、壊れて見える不利益が大きい。

### Option B: license を静的バッジ化する
- Pros: GitHub API 依存を断ち、`invalid` が出ない。MIT は事実上不変で更新頻度ゼロ。Swift / Platform と表現も揃う。
- Cons: 将来ライセンスを変えた場合は手で更新が必要（ただし極めて稀）。

### Option C: version も静的化する
- Pros: version バッジも安定する。
- Cons: リリースのたびに手更新が必要。リリース連動の自動性という価値を失う。頻度の高いトレードオフになるため、安定性のためだけに払うコストが見合わない。

## Decision

license バッジのみ静的化する（Option B）。`img.shields.io/github/license/...` → `img.shields.io/badge/license-MIT-green`。

version バッジはリリース連動の自動性を優先して動的のまま残す（Option C は却下）。version の `invalid` は一時的なレート制限に起因し、時間が経てば復帰するため放置で許容する。

## Consequences

### Positive
- license バッジが GitHub API 非依存になり、`invalid` 表示が解消。更新頻度は実質ゼロ。
- README のバッジ表現が静的系（Swift / Platform / License）で揃う。

### Negative / Trade-offs
- ライセンス変更時は README のバッジを手で更新する必要がある（発生頻度は極めて低い）。
- version バッジは依然として動的で、レート制限時に一時的に `invalid` になりうる。これは意図的なトレードオフ。

### Follow-ups / 残課題
- 将来 version の安定性が問題になるなら、リリースワークフローで README のバッジを自動更新する方式を別途検討する。

## References
- `README.md` 冒頭のバッジ定義
- shields.io の GitHub API 匿名レート制限（60 req/h、全利用者で共有）
