# 設計ドキュメント: 共有セッション（人間の `watch` ＋ AI の `mcp` 同居）

> ステータス: Phase 1（観測アタッチ）実装済み（metaphor-cli）。Phase 2（入力共有）は未着手。
> 対象: metaphor-cli（watch / mcp）。metaphor 本体は**改修なし**（Probe・入力注入は既存）。
> 関連: [ai-mcp-server.md](./ai-mcp-server.md)、[live-viewer.md](./live-viewer.md)、CONTRACT.md（契約点4 Probe）
> トラッキング: Epic shinyaoguri/metaphor#75

## 1. 目的

VSCode でプロジェクトを編集し、ターミナルから `metaphor watch` を起動して
差し替えながら開発しつつ、**同時に Claude Code(MCP) からも同じ実行中スケッチを
観測したい** —— 人間と AI が **1 つの実体を共有して協調**するワークフロー。

## 2. なぜ素朴には無理か（根本原因）

MCP は **stdio トランスポート**で、**クライアント（Claude Code）が自分でサーバ
プロセスを起動し、その stdin/stdout を占有**する。ゆえに VSCode のターミナルで
人間が起動した `metaphor watch`（別プロセス・別 stdio）に、Claude Code の
`metaphor mcp` が stdio で「あとから繋ぐ」ことは原理的にできない。従来の
`metaphor mcp` が自前の子を spawn していたのはこのため＝別インスタンスになる。

→ 1 つの実体を共有するには **supervisor の stdio とは別の IPC** が要る。metaphor は
既にそれを持っている: **Probe のファイル IPC（`.metaphor/probe/`）**。これを拡張する。

## 3. 鍵となる単純化: 編集はファイルで自動共有される

「編集の協調」に新しい機構は要らない。

- 人間 = VSCode でファイル編集・保存
- AI = Claude Code がファイルを直接編集（既存挙動）
- **`metaphor watch` が誰の変更かに関係なく再ビルド・差し替え**

つまり編集は「両者がディスクを書き、watch が 1 つだけ再ビルドする」で共有完了。
**MCP に残る役割は観測だけ**（snapshot / build_status）。入力注入（`input`）は対話
テスト用の別物で、この協調の必須要素ではない（Phase 2）。

## 4. 設計: 「所有者＝watch」「mcp＝アタッチする観測クライアント」

```
人間 ─┐
       ├─→ ディスク上のソース ──→ [ metaphor watch ]  ← 唯一の所有者
AI  ─┘                              build / spawn / swap / viewer
                                    子: METAPHOR_VIEWER=1 + METAPHOR_PROBE=1
                                       ├─ Syphon → 人間がビューア窓で見る
                                       └─ Probe  → .metaphor/probe/ に frame.{png,json}

Claude Code ──MCP(stdio)──→ [ metaphor mcp ]（ATTACH：spawnしない・buildしない）
                               snapshot     = .metaphor/probe/ 往復（既存）
                               build_status = .metaphor/build-status.json を読む
```

共有はすべて `.metaphor/` 配下のファイル（Probe と同じ哲学・新トランスポート不要）。

### 制御ファイル（`.metaphor/`）

| ファイル | 書き手 | 読み手 | 内容 |
|---|---|---|---|
| `probe/request.json` ↔ `probe/current/frame.{png,json}` | 子（Probe）/ mcp | mcp / 子 | 既存の観測往復（[ai-mcp-server.md](./ai-mcp-server.md)） |
| `session.json` | watch | mcp | `{schemaVersion, pid, sketchPath, syphonName, probeEnabled, startedAt}` |
| `build-status.json` | watch | mcp | `BuildOutcome {succeeded, exitCode, output, initial}` |

### 役割と挙動

- `metaphor watch`（既定で Probe ON、`--no-probe` で OFF）:
  - 起動時に `session.json` を書く（`pid`=supervisor）。
  - 毎ビルドで `build-status.json` を更新。
  - 子を `METAPHOR_PROBE=1` で起動（観測可能化）。
  - 停止時に `session.json` を削除。
- `metaphor mcp`:
  - 起動時に `session.json` を読み、**pid が生存していれば ATTACH**（spawn しない・
    build しない）。なければ従来どおり **自前で headless 子を spawn**（CI・単独利用を維持）。
  - ATTACH 中: `snapshot`=Probe 往復、`build_status`=`build-status.json`、`input`=未対応
    （明示メッセージ）。

## 5. 設計判断（確定）

- **トランスポート＝ファイル IPC（全フェーズ）**。supervisor は既に `PollingFileWatcher`
  を回しており追加コストが小さい。入力は AI 主導＝人間ペースなので poll 遅延を許容。
  低遅延が要れば将来ソケットへ（観測経路は不変）。
- **precedence**: 生存セッションがあれば mcp は必ず attach（build しない）→ 現状の
  「2 プロセスが同じ `.build` を奪い合う」競合が原理的に消滅。
- **セッション断**: ATTACH 中に所有者 pid が消えたら**黙って self-spawn せず**、以後の
  ツール呼びはタイムアウト/エラーで顕在化（驚き最小。watch 再起動を促す）。
- **snapshot の素性**: 共有編集中は撮ったフレームが旧ビルドのものでありうる。直近
  ビルドが失敗していれば snapshot 結果に注記を**cli 側で合成**する（`frame.json`＝
  ライブラリには触れない）。
- **Probe 常時 ON**: watch 起動だけで attach 可能に。コストは「毎フレーム request.json
  の mtime stat 1 回」で実質ゼロ。`--no-probe` を逃げ道に。

## 6. 影響範囲

- **metaphor 本体（ライブラリ）= 改修ゼロ**（Probe・InputInjectionPlugin 既存、
  `METAPHOR_PROBE=1` は cli が渡す env、buildId 注記は cli 側合成）。
- **metaphor-cli のみ**: `SharedSession`（manifest/build-status の read/write/生存判定）、
  `WatchSession`(`shareSession`)、`ViewerWatch`/`WatchCommand`(Probe ON＋共有)、`mcp`
  アタッチ判定、`SketchToolHandler`(`inputAvailable`＋snapshot 注記)。
- **契約（CONTRACT.md）**: `session.json`/`build-status.json` は **両端とも cli＝cli 内部
  プロトコル**につき cross-repo 契約の増分なし。Probe は既契約のまま。
- **ビルドロック競合**: 解消（ビルドは watch 1 つだけ）。

## 7. フェーズ

| Phase | 内容 | 状態 |
|---|---|---|
| 1 | 観測アタッチ（`snapshot` + `build_status`）。watch が Probe ON＋manifest＋build-status。mcp が attach。 | **実装済み** |
| 2 | `input.jsonl` 制御チャネルで AI 入力も共有（supervisor が tail→`forwardInput`）。 | 未着手 |

## 8. スコープ外（現時点）

- 同一インスタンスを人間と AI が**両方とも操作**するフル双方向（Phase 2 ＋ live-viewer
  Phase 2 の `saveState`/`restoreState` 領域）。
- 複数スケッチ／複数セッションの同時管理（セッションはスケッチディレクトリ単位）。
- リモート（非ローカル）トランスポート。
