# ADR-0013: 専用エディタを作らず、既存エディタ + コンパニオンへ投資する

- **Status**: Accepted
- **Date**: 2026-08-18
- **Deciders**: @shinyaoguri
- **PR / Commit**: (この ADR を含む PR)

## Context

metaphor の開発環境は VSCode / Xcode を想定しているが、「**より特化した専用エディタを作るべきか**」は
繰り返し浮かぶ問いで、根拠がどこにも残っていない。近いことを言っている記述は
[`docs/design/roadmap-processing-unity.md`](../design/roadmap-processing-unity.md) の非目標の 1 行だけだった。

> フルゲームエンジン・エディタアプリ化（シーンシリアライズ形式・prefab・Play/Edit 分離は作らない。インスペクタはビューアの付帯機能）

これは**ゲームエンジンとしての Play/Edit 分離を作らない**という宣言であって、
「コードエディタを自作するか」には答えていない。しかも「エディタアプリ化しない」を素直に読むと
「エディタ連携もしない」に読めてしまい、実際に進めている VSCode 連携
（[metaphor-cli#125](https://github.com/shinyaoguri/metaphor-cli/issues/125) = テンプレートへの `.vscode/` 同梱・**完了**、
[metaphor-cli#126](https://github.com/shinyaoguri/metaphor-cli/issues/126) = VSCode 拡張・open）と矛盾して見える。
根拠ごと記録しないと 6 ヶ月後にまた蒸し返る。

### 「専用エディタ」は一枚岩ではなく 4 層

議論が空回りするのは、「専用エディタ」が独立した 4 層の束だからである。metaphor の現状を重ねると:

| 層 | 中身 | 現状 | 自作の要否 |
|---|---|---|---|
| ① テキスト編集・補完・診断 | Swift の補完 / 型推論 / エラー表示 / 定義ジャンプ | SourceKit-LSP（VSCode / Xcode が既に提供） | **自作しない** |
| ② プロジェクト管理・実行・ライブリロード | 雛形生成 / ビルド / 再起動 / 監視 | `metaphor new` / `run` / `watch`（roundtrip p50 986ms）で**完成済み** | 不要 |
| ③ 実行中スケッチの観測・操作 | ビューア窓 / パラメータ GUI / 状態の可視化 / AI の観測 | ライブビューア + `gui.params()` + Probe + MCP 7 ツールで**大部分あり** | **ここだけが metaphor 固有の価値** |
| ④ 未経験者のオンボーディング | ターミナル無しで最初の絵を出す | 未対応（`brew` + ターミナル前提） | 条件付き（下記ゲート） |

「専用エディタが欲しい」と感じるとき、実際に足りないのは ③ の厚みと ④ であって、① ではない。
そして ③ は**エディタではなくコンパニオンウィンドウで解ける** — 現に
[`live-viewer.md`](../design/live-viewer.md) と [`shared-session.md`](../design/shared-session.md) はその設計で動いている。

### 前提が動いた: 論拠の重心は「エディタ税」から「AI 制作能力」へ移った

本 ADR のもとになった検討（[#559](https://github.com/shinyaoguri/metaphor/issues/559)・2026-08-12）は、
作らない理由の筆頭に「**エディタ税なしが Unity ユーザー獲得の売り文句そのものだから**」を置いていた。
しかしその 3 日後、ロードマップの**決定 7**（2026-08-15・`roadmap-processing-unity.md` の「戦略的判断」）が
**Unity 移行者獲得の市場仮説を降ろした**。獲得の売り文句を守ることは、もう判断の決め手にならない。

同じ決定 7 が代わりに置いたのは「**AI 制作能力（AI authoring）を中心目標にする**」である。
これは逆方向に効く — AI コーディングエージェント（Claude Code / Cursor / Copilot）が
**VSCode とターミナルのエコシステムに住んでいる**という事実は、二番手の補足論拠から
**中心目標そのものを守る論拠**へ昇格した。結論（作らない）は変わらないが、**論拠の順序は入れ替わる**。

### 先例が示す分岐条件

| プロジェクト | 専用エディタ | 成立した理由 |
|---|---|---|
| Processing (PDE) | あり | 専用言語処理系とセット。教育用途で「1 ファイル・1 ボタン」が本質 |
| p5.js Web Editor | あり | **Web だから成立**（インストールゼロ・URL 共有）。ネイティブでは再現不能 |
| Godot | あり（本体） | **GDScript という専用言語**とシーンフォーマットがセット |
| TouchDesigner / Max / vvvv | あり | **ノードグラフというパラダイムそのもの**がエディタ |
| openFrameworks / Cinder / Siv3D / nannou | **なし** | 既存言語 + 既存 IDE。ジェネレータとライブラリに集中 |

**専用言語かパラダイムを持つプロジェクトだけが専用エディタで勝っている**。metaphor は
「普通の Swift をそのまま書く」設計（`swift run` でも動く / SwiftPM パッケージとして既存プロジェクトに
組み込める）なので、下段のグループに属する。

## Considered Options

### Option A: テキスト編集を含む統合 IDE を自作する

- Pros: ① 〜 ④ を一つの体験にまとめられる。オンボーディングを完全に制御できる。
  metaphor に最適化した補完・スニペット・エラー表示を作り込める
- Cons: ① を自前で持つのは不可能なので、結局 SourceKit-LSP を呼ぶことになる。すると実体は
  「LSP クライアント + テキストバッファ + 設定 + 更新 + 署名 + notarize + クラッシュ対応」の再実装で、
  **Swift ツールチェーンの更新に永久に追随し続ける負債**が乗る（Processing PDE が補完の弱さを
  長年抱えているのは、まさにこの層を自前で持ったコスト）。さらに AI エージェントが住む
  エコシステムの外へ自分から出ることになり、中心目標（決定 7）と正面衝突する

### Option B: 既存エディタに委ね、投資は「実行中のスケッチを触るコンパニオン」へ向ける（採用）

- Pros: ① の負債をゼロにしたまま ③ に集中でき、③ が唯一 metaphor 固有の価値。
  現アーキテクチャ（編集はファイル / 共有は `watch` / 観測は Probe のファイル IPC）が
  **エディタ非依存に設計済み**なので、資産をそのまま活かせる。VSCode 連携（`.vscode/` 同梱・拡張）は
  数日〜2 週間で実用価値が出る一方、Option A は初版まで数ヶ月 + 恒久メンテ
- Cons: ターミナルを越えられない未経験者（④）には届かない。VSCode 側の不調
  （[#578](https://github.com/shinyaoguri/metaphor/issues/578) の補完全滅など）を自分でコントロールできず、
  他人の実装の上に体験が乗る

### Option C: `.app` ランチャーを先に作る（テキスト編集は外部エディタに委ねる GUI ラッパー）

- Pros: ④ に効く。プロジェクト作成 + テンプレートギャラリー + 実行 + ビューアだけなら
  実質 `metaphor-cli` の GUI ラッパーで、Option A より費用が一桁小さく、失敗しても捨てられる
- Cons: **④ が実在の壁だという証拠がまだ無い**。現在の利用者は全員ターミナルを越えている。
  証拠なしに作ると、維持コストだけが残る

### Option D: 判断を保留し、非目標の 1 行のままにする

- Pros: 何もしなくてよい
- Cons: 現状そのもの。同じ議論が繰り返し立ち上がり、しかも 1 行が「エディタ連携もしない」と
  誤読されて cli#125 / #126 と矛盾して見える

## Decision

**Option B を採る。テキスト編集を含む専用エディタ（統合 IDE）は作らない。① と ② は既存エディタと
`metaphor-cli` に委ね、投資は ③「実行中のスケッチを触るコンパニオン」へ向ける。
ただし VSCode を公式の想定環境として整える投資（`.vscode/` 同梱・VSCode 拡張）は in scope。**

決め手は次の順（**強い順**。この順序は #559 起票時の草案から入れ替えてある — 筆頭だった
「エディタ税なし = Unity 獲得の売り文句」は決定 7 で市場仮説ごと降りたため、従へ下げた）:

1. **AI 制作能力が中心目標で、AI エージェントは既存エディタとターミナルに住む**（決定 7）。
   専用エディタを作ることは、中心目標のエコシステムから自分で出ていくことに等しい
2. **現アーキテクチャがエディタ非依存に設計済みで、これは捨てる理由のない資産**。
   `shared-session.md` は「VSCode で編集 / ターミナルで `metaphor watch` / Claude Code(MCP) から同じ実行中
   スケッチを観測」を前提に組まれていて、**エディタが何であっても成立する**
3. **① の自作は個人開発では返ってこない投資**（Option A の Cons）
4. **今のボトルネックはエディタではない**。v1.0 昇格条件は技術条件 + GitHub スター 100 超
   （[v1-release-plan.md](../design/v1-release-plan.md)）で、獲得曲線に効いているのは website（[#74](https://github.com/shinyaoguri/metaphor/issues/74)）・
   英語版チュートリアル（[#548](https://github.com/shinyaoguri/metaphor/issues/548)）・公開 API doc コメントの英語化（[#334](https://github.com/shinyaoguri/metaphor/issues/334)）の側。
   エディタが効き始めるのは「使いたいのにターミナルが越えられない人」が実在するようになった後で、順番が逆になる
5. **先例の分岐条件**（専用言語かパラダイムを持つプロジェクトだけが専用エディタで勝っている）
6. **「エディタ税なし」の摩擦の低さ自体は価値として残る**。ただし Unity 移行者獲得の売り文句としては
   もう数えない（決定 7）

### 「エディタアプリ化しない」と「エディタ連携をしない」は別物

非目標が禁じるのは **① テキスト編集の自作**であって、既存エディタを metaphor 向けに整えることではない。
本 ADR にあわせて `roadmap-processing-unity.md` の非目標を精緻化する。

- 旧: フルゲームエンジン・エディタアプリ化（…）
- 新: フルゲームエンジン化・**テキストエディタの自作**（… **VSCode 拡張・エディタ連携は in scope**）

### 投資先（3 段の階段）

| 段 | 中身 | 状態 |
|---|---|---|
| Step 0 | `metaphor new` のテンプレートに `.vscode/` を同梱し、VSCode を公式の想定環境として宣言する | [cli#125](https://github.com/shinyaoguri/metaphor-cli/issues/125) **完了** |
| Step 1 | VSCode 拡張を薄く作る（`new` / `run` / `watch` / `snapshot` をエディタから）。Swift 拡張の上に載せるだけで ① には触らない | [cli#126](https://github.com/shinyaoguri/metaphor-cli/issues/126) open |
| Step 2 | ③ の厚み — D6 ノードインスペクタ（Epic [#290](https://github.com/shinyaoguri/metaphor/issues/290) / [#294](https://github.com/shinyaoguri/metaphor/issues/294) H3）・ライブビューアのパラメータパネルとエラーオーバーレイ・Epic [#415](https://github.com/shinyaoguri/metaphor/issues/415) K の構造化支援 | 既定路線の継続（方向転換不要） |
| Step 3 | `.app` ランチャー（Option C） | **ゲート付き・着手しない** |

### 判断を覆すゲート

決め打ちにせず、次のどれかが観測されたら再検討する。**満たすまで Step 3 に着手しない。**

1. ターゲットが「プログラミング未経験のアーティスト」へ移り、`brew` + ターミナル + SwiftPM が
   越えられない壁だと**実データで**確認された（例: 対面ワークショップで N 人中 M 人が最初の絵に到達できなかった）
2. Swift ではなく **metaphor 独自の記述レイヤ**（DSL・スクリプト層）を持つ判断をした
3. ノードグラフ等、**テキストでない編集パラダイム**を採ると決めた

ただし 1 の場合でも最初の一手は Option A ではなく Option C（`.app` ランチャー）である。

## Consequences

### Positive

- 「専用エディタを作るべきか」の議論が根拠ごと settled になり、蒸し返しのたびに再導出しなくてよい
- 非目標の記述が cli#125 / #126 と矛盾しなくなる。「エディタ連携は in scope」が明文化され、
  VSCode 拡張を進めるのに毎回説明が要らない
- 投資先が ③ に固定される。ライブビューア・Parameter Store・インスペクタが
  「エディタの代わり」ではなく**本命**であることが位置付けとして明確になる
- ① を持たないので Swift ツールチェーンの更新に追随する義務が発生しない

### Negative / Trade-offs

- **開発体験の一部を他人の実装に預ける**。VSCode / SourceKit-LSP 側が壊れると
  metaphor の体験も壊れる（[#578](https://github.com/shinyaoguri/metaphor/issues/578) が現に発生中）。回避策の同梱で対処するが、根治はできない
- **④ 未経験者のオンボーディングは空いたまま**。ターミナルを越えられない層には届かない。
  ゲート 1 が観測されるまで意図的に空けておく
- Xcode と VSCode の二刀流になるため、**どちらをいつ使うかを利用者に説明する責任が残る**
  （日常は VSCode + `metaphor watch`、GPU デバッグ = フレームキャプチャ・シェーダプロファイラ時だけ Xcode）

### Follow-ups / 残課題

- **README / チュートリアル 01 への二刀流の明記は [#578](https://github.com/shinyaoguri/metaphor/issues/578) 待ち**。現在
  README の VSCode 言及は 0 件、チュートリアル 01 の動作環境表も「Swift 5.10 以降（Xcode 15.4 以降）」だけで、
  **いま「日常は VSCode」と書くと補完が全滅する環境を推奨することになる**。本リポジトリに
  `.sourcekit-lsp/` はまだ無い（2026-08-18 実測）。#578 で回避策が入ってから書く
- Step 1（[cli#126](https://github.com/shinyaoguri/metaphor-cli/issues/126)）は metaphor-cli 側が持つ。本リポジトリの作業ではない
- [#501](https://github.com/shinyaoguri/metaphor/issues/501)（example のスクリーンショット 162 枚がどこからも参照されていない）は、
  VSCode 拡張のサンプル挿入（Step 1）の出口になりうる

## References

- [`docs/design/roadmap-processing-unity.md`](../design/roadmap-processing-unity.md) — 決定 7（AI 制作能力を中心目標に置く / Unity 移行者獲得の市場仮説は降ろす）と非目標
- [`docs/design/shared-session.md`](../design/shared-session.md) — 「編集はファイル / 共有は `watch` / 観測は Probe のファイル IPC」というエディタ非依存の設計
- [`docs/design/live-viewer.md`](../design/live-viewer.md) — コンパニオンウィンドウ（③）の設計
- [`docs/design/ai-mcp-server.md`](../design/ai-mcp-server.md) — MCP 7 ツール
- [`docs/design/v1-release-plan.md`](../design/v1-release-plan.md) — v1.0 昇格条件（技術条件 + スター 100 超）
- [ADR-0009](0009-unfreeze-api-until-1-0.md) — 1.0 まで設計の質を優先する（本 ADR の「順番が逆になる」判断と同じ姿勢）
- Issue [#559](https://github.com/shinyaoguri/metaphor/issues/559) — 本 ADR のもとになった検討（論拠の順序は決定 7 を受けて入れ替えてある）
- Issue [#578](https://github.com/shinyaoguri/metaphor/issues/578) — sourcekit-lsp の背景インデックスで `import metaphor` が解決できず VSCode の補完・hover が全滅する
- [metaphor-cli#125](https://github.com/shinyaoguri/metaphor-cli/issues/125)（Step 0・完了）/ [metaphor-cli#126](https://github.com/shinyaoguri/metaphor-cli/issues/126)（Step 1・open）
