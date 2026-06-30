# AIループ往復時間の測定（Epic #75 実測フェーズ）

- **ステータス**: 初回測定（2026-06-30）
- **対象**: Epic #75 の成功基準のうち未達だった2つ — **A: 往復時間**（観測→編集→再観測）、**B: 保存→反映時間**
- **関連**: #115（frame.json `sourceStamp`）、#116（ベンチスケッチ）、metaphor-cli#44（測定ハーネス）

## なぜ測るか

Epic #75 は成功を **「機能数でなく」** 往復時間・観測の決定論性で定義する。観測の決定論性は #70/#71 で達成済み。本ドキュメントは残る2基準（A/B）を**再現可能な数値**にし、後続候補（scope(b) 完全決定論パイプライン / データI/O / #87）のどれが往復時間に効くかを**実測で判断する**ためのもの。機能追加が目的ではない。

## 方法

実際の AI ループ経路（`metaphor mcp` の stdio JSON-RPC）を外部から駆動する測定ハーネス [`scripts/measure-roundtrip.py`（metaphor-cli）](https://github.com/shinyaoguri/metaphor-cli) を用いる。`mcp` は内部で `WatchSession`（ファイル監視＋`swift build`＋子プロセス再起動）を回しつつ `METAPHOR_VIEWER=1` でヘッドレス描画するため、**観測（snapshot）と編集→反映を同一経路で**測れる。

- **反映の機械判定**: 編集が新フレームに反映されたかは `frame.json` の **`sourceStamp`（#115）の変化**で判定する。cli が監視 `.swift` の (パス:mtime:サイズ) を集約した決定論的スタンプを子 env `METAPHOR_SOURCE_STAMP` に注入し、producer が `frame.json` に echo する。これにより「古いフレーム（編集前）」と「リビルド後の新フレーム」を確実に区別できる。
- **編集**: ベンチスケッチ末尾にビルド安全な sentinel 行を append/更新（測定後に原状復帰）。
- **指標**: cold-start snapshot / warm snapshot 往復 / roundtrip（編集→反映）の p50・p95。
- **ground truth**: 画面キャプチャ権限は不要。`frame.png`/`frame.json` の読み戻し。

## 結果（初回）

- 機種/ビルド: Apple Silicon / **debug ビルド**（増分）
- スケッチ: `Examples/Samples/ProbeSnapshot`（2D の小規模スケッチ）
- サンプル: warm n=12 / roundtrip n=6

| 指標 | p50 | p95 | 内訳 |
|---|---|---|---|
| cold-start snapshot | 1328 ms | — | 子の Metal 初期化＋初回ビルド＋初フレーム |
| **warm snapshot（観測）** | **35.6 ms** | 65.5 ms | request→frame ready（IPC＋1フレーム） |
| **roundtrip（編集→反映＝基準A/B）** | **2811 ms** | 2854 ms | 監視検知＋増分 `swift build`＋再起動＋初フレーム |

## 分析（実測フェーズの結論）

- **観測は安いが往復は遅い**: warm snapshot **35ms** に対し roundtrip **2811ms** ≈ **約80倍**。差分のほぼ全ては **増分 `swift build`＋子プロセス再起動**。
- **律速は観測でも決定論パイプラインでもなく「ビルド＋再起動」**。したがって AI 反復速度に次に効くのは scope(b) 完全決定論パイプラインではなく、**ビルド/再起動の短縮**（増分ビルドの最適化・コンパイル済みプロセスのウォーム維持・状態保持リロード等）。
- 決定論観測(#70/#71)＋provenance(#115) の投資により warm snapshot が **35ms と安定**し、roundtrip も p50↔p95 の幅が小さい（測定ノイズが小さい）。この安定性自体が「信頼できる観測」基準の達成を裏づける。

## 既知の制限 / 今後

- **debug ビルド・単一機種・小規模スケッチ（ProbeSnapshot）**の初回値。release ビルドや重いスケッチ（#116 `ProbeBenchmark`：影オン3D）での再測定で傾向の頑健性を確認する。
- roundtrip を `T_detect / T_build / T_relaunch` に**分解する細粒度計測**は未実装（現状は合算）。律速がビルドであることは明白だが、再起動コストの切り分けには `build-status.json` のタイムスタンプ等を使う追補が要る。
- 上記の律速（ビルド支配）は Epic #75 のバックログとして子 Issue 化する。

## 参考

- ハーネス: `metaphor-cli/scripts/measure-roundtrip.py`（#44）
- provenance: [CONTRACT.md](../../CONTRACT.md) frame.json スキーマ v4（`sourceStamp`）、#115
- 決定論レンダリング: [docs/design/deterministic-rendering.md](deterministic-rendering.md)、#70/#71
- Epic #75
