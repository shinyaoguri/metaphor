# Architecture Decision Records (ADR)

このディレクトリは、本プロジェクトで下された設計判断とその根拠を **append-only** で蓄積する場所です。コードは「どうなっているか」を語りますが、ADR は「**なぜそうなっているか**」を語ります。

## なぜ ADR を書くか

- AI エージェントが過去の議論をやり直さなくて済む (settled な判断を context として与えられる)
- 半年後の自分 / 新しい貢献者が経緯を辿れる
- 「コードを読めば分かる "What"」ではなく「コードを読んでも分からない "Why"」を記録する

## 何を書くべきか

- **新規追加で書く**: 複数の選択肢があり、片方を選んだ重要な判断 (アーキテクチャ選択、API 互換性方針、レンダリングパイプライン設計、クロスリポ契約[metaphor ⇄ metaphor-cli] の変更、フォーマット決定、責務分担)
- **書かなくてよい**: 自明なリファクタ、命名変更、軽微なバグ修正、新規 example の追加
- **判断基準**: 「6 ヶ月後にこの判断を覆そうとした人が、当時の議論を見ずに同じ結論に達するか?」が NO なら ADR にする

## 設計ドキュメントとの違い

- [`docs/design/`](../design/) — **当初の設計提案**。実装前後の経緯・全体像・ロードマップを散文で書く (例: ライブビューア, MCP サーバ)。確定仕様はコード/CONTRACT.md を正とする
- `docs/adr/` (ここ) — **確定した個別判断**。1 ファイル 1 判断、却下案も含めて append-only で残す

両者は補完的。大きな設計提案の中で下した個々の確定判断を ADR として切り出す、という関係になる。

## 書き方

1. [`template.md`](template.md) をコピーして `NNNN-kebab-case-title.md` で保存
2. NNNN は連番 (4 桁 zero-padded)。既存最大 + 1
3. 1 ADR = 1 判断。複数の判断を 1 ファイルにまとめない
4. **コードと同じ PR で commit**。ADR と実装がアトミックに進む
5. 下の「既存 ADR」テーブルに 1 行追記する

## 改廃

- ADR は **append-only**。既存 ADR を編集しない (誤字脱字を除く)
- 判断を覆すときは **新しい ADR を追加し、旧 ADR の Status を `Superseded by ADR-NNNN` にする**
- 「やめた」場合は `Status: Deprecated` で残す

## 既存 ADR

| # | Status | Title |
|---|---|---|
| _まだありません_ | | |

## 参考

- [ADR の元になった Michael Nygard の記事](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [CLAUDE.md](../../CLAUDE.md) — アーキテクチャ概要とコード挙動 (What)
- [CONTRACT.md](../../CONTRACT.md) — metaphor ⇄ metaphor-cli のクロスリポ契約
- [docs/design/](../design/) — 設計提案ドキュメント
