# 設計ドキュメント: AI協調ローカルMCPサーバ（`metaphor mcp`）

> ステータス: 提案（実装前）
> 対象: metaphor-cli（MCPサーバ本体）+ metaphor 本体（変更なし、契約の消費のみ）
> 関連: Probe プラグイン、`InputInjectionPlugin`、ライブビューア（[live-viewer.md](./live-viewer.md)）、CONTRACT.md
> トラッキング: Epic shinyaoguri/metaphor#75 / 設計 #66 / 実装 metaphor-cli#19(M1) #20(M2)

## 1. 背景と目的

metaphor の当面（〜1.0）の第一目的は **AI協調の研究・実証** — AI エージェントがビジュアルを
「観測（いま見えている画像と内部状態）」「操作（入力注入）」「高速反復（ライブリロード）」
できることの実証。差別化は Swift/Metal そのものではなく **Probe + ライブビューア + ローカルMCP**
の三点セットにある。

重要なのは、**観測・操作・反復の部品はすでに実装済み**だという点:

| ループ要素 | 実体 | 場所 |
|---|---|---|
| 観測（フレーム＋内部状態） | `MetaphorProbePlugin`（frame.png + frame.json + `probe()` 値 + blank警告） | metaphor 本体 |
| 操作・入力注入 | `InputInjectionPlugin`（stdin JSON Lines） | metaphor 本体 |
| 編集→反映の高速化 | `metaphor watch --viewer`（既定化済み） | metaphor-cli |

欠けているのは **(1) これらを束ねる単一インターフェイス（MCP）** と **(2) 状態の可視化**だけ。
本ドキュメントは (1) を `metaphor mcp <sketch>` として定義する。

## 2. なぜ MCP サーバは薄いアダプタで済むか

新機構はほぼ不要で、既存のファイル（Probe）と stdin（入力）を MCP プロトコルへ橋渡しするだけ。

- **観測**: Probe は `.metaphor/probe/request.json` を書くと次フレームで
  `current/frame.{png,json}` を atomic に書き出す。MCP サーバはこのファイル往復を自動化し、
  PNG を MCP の inline image として返すだけ。
- **操作**: 入力は既に stdin の JSON Lines（`{"t":"mouseDown","x":..,"y":..,"button":0}` 等）。
  MCP サーバは `WatchSession.forwardInput` 経由で子 stdin に流すだけ。
- **反復/監視**: `WatchSession`（build→spawn→supervise）をそのまま再利用。

## 3. アーキテクチャ

```
AIエージェント ──MCP(JSON-RPC 2.0 / stdio)──→ metaphor mcp <sketch-dir>
                                                ├─ WatchSession: build→spawn→supervise（既存）
                                                ├─ 子: ヘッドレス + Probe + timer（既存・無改造）
   observe  ←── .metaphor/probe/frame.{png,json} ←┘   (Probe 既存・無改造)
   operate  ──→ WatchSession.forwardInput → 子stdin     (既存・無改造)
```

- 子は `METAPHOR_PROBE=1` + `METAPHOR_VIEWER=1`（タイマー駆動・ウィンドウなし）で起動。
- スナップショットは Probe がファイルに直接書くため **Syphon もビューア窓も不要**。
  人間が横で見たい時だけ別途 `--viewer` で Syphon を覗ける（Probe と独立に両立）。

## 4. トランスポート

- **自前実装**。MCP stdio は実質「改行区切り JSON-RPC 2.0」。必要メソッドは
  `initialize` / `notifications/initialized` / `tools/list` / `tools/call` のみ。
- **外部依存（MCP SDK 等）は入れない**。metaphor-cli の「依存ゼロ・手書き switch dispatch・
  既に JSON Lines を喋る」哲学に完全に合致する。
- ツール結果は MCP content blocks（`text` / `image`(base64+mimeType)）で返す。

## 5. ツール（v1）

| ツール | 実体 | 返すもの |
|---|---|---|
| `snapshot` | Probe `request.json` を新 id で書く → `frame.json` mtime ポーリングで完了待ち | frame.png を **inline image** + frameCount / time / `probe()` 値 / blank警告 |
| `input` | 構造化イベント → `WatchSession.forwardInput` → 子stdin（既存 JSON Lines スキーマ） | ack |
| `build_status` | build runner の exit code + 捕捉した stderr | 成否 + ビルドエラーテキスト |

`snapshot` が MCP の image content で **フレームをそのままエージェントに見せる**のが肝。
これで「観測 → 編集 → 再観測 → 検証」が 1 インターフェイスで閉じる。

将来候補（v1 には入れない）: `reload`（強制再ビルド）、`get_state`（新snapshotなしで直近frame.json）。

## 6. 既知の実装上の注意

- 現在 launcher（`FoundationProcessLauncher`）は子の stdout/stderr を**親へ素通し**している。
  MCP モードでは親の stdout は JSON-RPC 専用なので、**子の出力を stdout に混ぜず stderr か
  ファイルへ**回すキャプチャモードを launcher に追加する。これが `build_status` の
  エラー取得にもそのまま使える（→ M2）。
- スナップショットのポーリングにはタイムアウトを設ける（子が描画していない/クラッシュ時）。

## 7. フェーズ分割

| Phase | 内容 | 場所 | 完了時の価値 |
|---|---|---|---|
| M1 | MCPサーバ骨格（initialize/tools/list/tools/call）+ `snapshot` のみ。ヘッドレス子をProbe付き起動 | cli #19 | AIがフレームを見る、が成立 |
| M2 | `input` + `build_status` + launcher キャプチャモード | cli #20 | 観測＋操作のループが閉じる |
| M3 | 「AIがmetaphorを駆動する」参照ループを README 最上位へ | metaphor #68 | 価値が表に出る |

## 8. 受け入れ基準

- M1: MCPクライアントから `tools/call snapshot` で実フレーム画像が返る（エンドツーエンド）。
  親 stdout に JSON-RPC 以外を混ぜない。
- M2: `input` で子スケッチがマウス/キーに反応（snapshot で確認可能）。ビルド失敗時
  `build_status` がエラーテキストを返し、動作中スケッチは維持される。

## 9. クロスリポジトリ契約（CONTRACT.md）

MCP サーバは契約トークンを **消費するだけで変更しない**:

- 環境変数 `METAPHOR_PROBE` / `METAPHOR_VIEWER` / `METAPHOR_SYPHON_NAME` / `METAPHOR_FPS`
- Probe のパス/スキーマ（`.metaphor/probe/...`、`ProbeRequest` / `ProbeFrameMetadata`）
- stdin 入力イベントの JSON Lines スキーマ

したがって契約破壊リスクはない。ただし「MCP サーバがこれらに依存する」ことを両リポジトリの
CONTRACT.md に明記し、暗黙依存を可視化する（消費側の追加であり、トークン自体は不変）。

## 10. スコープ外（v1）

- 状態保持を跨いだ再起動（ライブビューア Phase 2 の `saveState`/`restoreState` に依存）。
- 複数スケッチの同時管理。
- リモート（非ローカル）MCP トランスポート。
