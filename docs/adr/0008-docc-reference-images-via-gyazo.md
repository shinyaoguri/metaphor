# ADR-0008: DocC リファレンスの画像を Gyazo の外部 URL で参照する（リポジトリにコミットしない）

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: リポジトリオーナー（本 PR）
- **PR / Commit**: 本 PR

## Context

#531 で、DocC が出す API リファレンスの各ページに実行結果の画像・動きを載せる計画を進めている（p5.js のリファレンスに倣う）。対象は `Sketch+*.swift` の公開関数 253 本で、**今後まとまった量の画像が継続的に増えていく**。置き場を先に決める必要があった。

### 先行する決定（#511）とその前提

置き場については #511 で一度決着している — 「**恒久ドキュメントの画像はリポジトリ内。Gyazo は Issue・PR の証跡専用**」。外部化するとしても第一候補は Gyazo ではなく GitHub 内の別リポジトリ、という結論だった。

ただしこの決定は `docs/tutorial/` をスコープにしており、**容量問題をアニメーション WebP で解いたうえで成立している**:

- 動きの証跡を GIF にすると最悪ケース 8.1 MB / 本（全画面ノイズ・48 フレーム）で「数年で確実に赤信号」
- アニメーション WebP は同条件で 188 KB（**GIF の 1/43**）。これにより Examples 220 本へ展開しても 8〜41 MB / 世代に収まり、リポジトリ内で成立する
- mp4 は GitHub の Markdown が相対パスの動画を再生しないため不採用

### DocC ではその前提が崩れる

`docc convert` に実際に食わせて確認した:

| 形式 | DocC での扱い |
|---|---|
| png / jpg / svg / **アニメーション GIF** | 使える |
| **WebP** | **使えない。`Resources/` に置いても警告すら出ずに参照ごと消える**（存在しないアセットなら `warning: Resource 'x' couldn't be found` が出るのに、WebP は無言で落ちる） |
| mp4 | `@Video` ディレクティブでのみ可（`![]()` 不可・GIF を `@Video` に渡すのも不可） |

つまり **#511 が採った解決策（WebP）を DocC には適用できない**。DocC で動きを見せる手段は実質 GIF だけになり、GIF は #511 自身が「既定にすると数年で赤信号」と結論した形式である。253 本規模かつ撮り直しが世代ごとに全バイト積む（動きの証跡は再現的に撮れない）ことを踏まえると、リポジトリ内で成立しない。

### 外部 URL が DocC で機能することの確認

「DocC は外部 URL を扱えない」という思い込みがあったが、実測では**動く**:

- `![alt](https://i.gyazo.com/<hash>.png)` は警告なく変換を通り、render JSON に `type: image` の reference として**絶対 URL のまま**残る
- Swift-DocC-Render 側のパス正規化は `n.startsWith("/")` のときだけ `baseUrl` を前置する実装で、絶対 URL はそのまま `<img src>` になる
- 本番と同じ `--transform-for-static-hosting --hosting-base-path metaphor` でも同様
- Gyazo の直リンク（`i.gyazo.com/<hash>.png`）は HTTP 200 / `image/png` を返す
- なお生の `<img>` タグは HTML ごと sanitize され消える（外部 URL を使うなら `![]()` 記法一択）

## Considered Options

### Option A: リポジトリ内（`Sources/metaphor/metaphor.docc/Resources/`）— DocC 標準の方式
- Pros: DocC の設計どおり。`~dark` / `@2x` バリアントで配色・Retina の出し分けが効く。参照切れが `docc convert` の warning になり CI で捕まる。`.doccarchive` が自己完結し、Xcode の Developer Documentation やオフラインでも画像が出る。既存の撮影パイプライン（`generate-tutorial-shots.py` + `manifest.json` の `sourceHash`）の陳腐化検出がそのまま効く。
- Cons: **動きを載せる手段が GIF しかない**（WebP 不可）。GIF は静止画の 21〜50 倍で、撮り直すたび全量が履歴に積む。253 本規模では成立しない。静止画だけに限れば成立するが、それでは #531 の目的（動きを見せる）を果たせない。

### Option B: Gyazo の外部 URL（採用）
- Pros: 本体リポジトリが一切太らない。形式の制約から解放され、GIF を容量を気にせず使える。URL は不変・追記型で無期限保存のため、URL を書いたコミットと画像が 1:1 で固定される（古い版のドキュメントを開けば当時の画像が出る）。`gyazo-capture` スキルが既にあり手軽。#529（`docs.yml` が `images/` をコピーしていない）が DocC 画像のブロッカーでなくなる。
- Cons: 下記 Consequences の Negative に記載。特に fork・外部コントリビュータと、`.doccarchive` の自己完結性を失う点。

### Option C: GitHub 内の別リポジトリ（例 `metaphor-assets`）+ GitHub Pages
- Pros: 本体が太らない・URL 不変という Gyazo の利点を保ったまま、fork とコントリビュータの問題が起きない（リポジトリ権限で共有できる）。ディレクトリ構造と git 履歴で逆引き・棚卸しができる。CI から `GITHUB_TOKEN` で自動化でき、障害点が GitHub の内側に留まる。#511 が外部化の第一候補としていた案。
- Cons: push が要る（CI で自動化は可能）。リポジトリをもう 1 つ増やし、その運用・権限・Pages 設定を維持する必要がある。Gyazo に比べて着手の手数が多い。

## Decision

**Option B（Gyazo の外部 URL）を採る。** DocC に載せる画像は Gyazo へ上げ、`![alt](https://i.gyazo.com/<hash>.png)` の形で参照する。リポジトリにはコミットしない。

決め手は、DocC が WebP を扱えないことで #511 の容量対策が使えず、かつ今後 253 本規模で画像が増え続けるため、リポジトリ内（Option A）が現実的でないこと。Option C との比較では、既に運用中の Gyazo 導線をそのまま使える手軽さを優先した。

**本 ADR は #511 の決定を DocC スコープに限って更新する。** `docs/tutorial/` の画像は #511 のまま（リポジトリ内・アニメーション WebP）で変更しない。

## Consequences

### Positive
- 本体リポジトリのサイズが画像で増えなくなる（現状 pack 27.66 MB のうち履歴上の画像 blob が 21.6 MB ≒ 78% を占めており、この増加軸を止められる）
- DocC で動きを見せる手段が GIF に限られる制約が、容量の問題ではなくなる
- URL が不変・追記型なので、撮り直しても過去の版のドキュメントは当時の画像を指したまま壊れない
- #529 の `images/` / `videos/` コピー漏れが DocC 画像のブロッカーでなくなる（ただし `theme-settings.json` が公開サイトで効いていない問題は残るので #529 自体は依然必要）

### Negative / Trade-offs
- **ダーク / Retina の出し分けができない。** 外部 URL の asset variants は `1x` / `light` 固定になる（`~dark` / `@2x` はローカルアセット専用の解決規則のため）
- **`.doccarchive` が自己完結しない。** Xcode の Developer Documentation に取り込んだときやオフラインでは画像が表示されない。DocC が想定する主要な閲覧形態の 1 つを捨てることになる
- **リンク切れが無言。** ローカルアセットなら `docc convert` が warning を出し CI で捕まえられるが、外部 URL は死んでも変換は成功する。検出は別途仕組みを作らないとゼロになる
- **fork・外部コントリビュータが同じ場所に画像を置けない。** 個人の Gyazo アカウントに依存するため、寄稿者は PR で画像を差し替えられず、メンテナのアップロードを待つことになる。#511 が Gyazo を退けた主因であり、Epic #314（v1.0 に向けて外部の貢献を増やす）とは緊張関係にある
- **逆引き・棚卸しができない。** ディレクトリ構造が無く、撮り直すたびに孤児 URL が溜まる。どの URL がどの API のものか追う手段を別に持つ必要がある
- 本体とは別のサービス・アカウント・規約への依存が増える（画像自体は Probe から再生成できるので、消えても撮り直せる点は救い）
- 同一 URL を画像とリンクの両方で使うと DocC の reference が衝突し、**画像側が壊れる**（実測で確認）。同じ URL を `[こちら](...)` のように併記しない

### Follow-ups / 残課題
- **URL 台帳を持つ**（どの API のどの URL か、撮影時のソースハッシュは何か）。`docs/tutorial/images/manifest.json` の `sourceHash` に相当する仕組みを外部 URL 向けに用意しないと、棚卸しと陳腐化検出の両方が失われる
- **リンク切れの CI 検出**を用意する（doc コメント中の Gyazo URL を抽出して死活チェック）
- **撮影から Gyazo Upload API までの自動化**（`generate-tutorial-shots.py` の仕組みを #531 の素材生成に向ける際に統合する）。手で撮ったスクリーンショットを置かない規約はチュートリアルと揃える
- ダーク配色前提のスケッチをどう見せるか（出し分けができないため、片方に寄せるか背景を固定するかを決める）
- 将来 fork・外部貢献が実際に増えたら Option C（別リポジトリ）への移行を再検討する。URL 参照方式のままなので移行コストは URL の一括置換に留まる

## References

- #531 — API リファレンスに実行結果の画像・動きを載せる（本 ADR の適用先）
- #511 — ドキュメント画像の置き場と形式の先行検討（本 ADR が DocC スコープで更新する）
- #529 — `docs.yml` が DocC 出力の `images/` `videos/` `theme-settings.json` を取りこぼす
- #507 / PR #517 — チュートリアルの動きの証跡をアニメーション WebP で撮る実装
- `docs/tutorial/README.md` — チュートリアル側の撮影規約（本 ADR では変更しない）
- `scripts/generate-tutorial-shots.py` — Probe + ヘッドレス実行による撮影パイプライン
- [DocC: Adding Images](https://github.com/swiftlang/swift-docc/blob/main/Sources/docc/DocCDocumentation.docc/adding-images.md)
- [Gyazo Help: How long are images stored](https://help.gyazo.com/How%20long%20are%20images%20stored%20on%20the%20Gyazo%20servers%3F-5de75e1e040e1d0017df4358)
