# 設計ノート: 外部結合アーキテクチャと契約ドリフト（Issue #119）

> ステータス: 設計判断ノート（実装は別スコープ）。本書は metaphor ⇄ metaphor-cli および
> AI エージェントとの**結合プリミティブ**を業界事例に照らして棚卸しし、Issue #119（契約型の
> 共有 SwiftPM パッケージ提案＝案D）への結論をまとめる。確定仕様は各実装・PR・ADR を正とする。
> 対象: metaphor 本体 + metaphor-cli（consumer）+ AI エージェント連携
> 関連: [live-viewer.md](live-viewer.md) / [ai-mcp-server.md](ai-mcp-server.md) /
> [shared-session.md](shared-session.md) / [../../CONTRACT.md](../../CONTRACT.md) / [../adr/](../adr/)

## 1. 背景

metaphor（producer）と metaphor-cli（consumer）は別リポ・別 SwiftPM パッケージで、cli は
metaphor を Swift ライブラリとして依存していない（子プロセス分離は Swift dylib のアンロード不能
問題に由来する本質的制約。[live-viewer.md](live-viewer.md) 参照）。両者は**ランタイム/バイナリ契約**
（[CONTRACT.md](../../CONTRACT.md)）だけで結合し、`scripts/check-contract.sh` の grep ベースの
トークン存在チェックで守られている。

Issue #119 は、この契約の守り方を「`metaphor-protocol` という描画スタックを含まない極小 SwiftPM
パッケージに契約型（`ProbeRequest` 等の Codable・環境変数名・入力イベント enum・`schemaVersion`）を
切り出し、両リポが url 依存してコンパイル時保証へ昇格する（案D）」と提案した。

本書は、この提案を評価するにあたり一段ゼロベースに引いて、**そもそも metaphor の外部結合は何で、
それぞれなぜその形なのか**を業界事例と突き合わせて棚卸しし、Issue #119 への結論を導く。

## 2. 外部結合は 1 つではなく 3 プレーン

metaphor を外部（cli のライブビューア、AI エージェント）と結ぶ経路は、性質の異なる 3 つに分かれる。
混同すると「JSON 結合が良いか」のような単一の問いに潰れてしまうため、まず分離する。

| プレーン | 役割 | 現状の transport | 実装 |
|---|---|---|---|
| **映像** | レンダリング結果の連続フレーム | **Syphon（IOSurface/GPU テクスチャ共有）** | `MetaphorSyphon` |
| **観測** | AI が「いま見えている画像」＋内部状態を取得 | **Probe ファイル**（`.metaphor/probe/request.json` → `current/frame.{png,json}` を mtime ポーリング） | `MetaphorProbePlugin` |
| **制御** | 外部からの入力注入 | **stdin JSON Lines**（HID イベント） | `InputInjectionPlugin` |

加えて環境変数（`METAPHOR_VIEWER` / `METAPHOR_PROBE` / `METAPHOR_SYPHON_NAME` 等）が起動時の
構成チャネルとして働く。以下、各プレーンの必然性と業界比較を述べる。

## 3. 各プレーンの必然性と業界比較

### 3.1 映像 = Syphon（GPU 共有）

同一マシンで producer の Metal テクスチャを cli のビューアへ **zero-copy** で渡す。

- **業界比較**: Syphon（macOS）/ Spout（Windows）/ NDI（ネットワーク）が定石。Chrome DevTools
  Protocol の `captureScreenshot` や Flutter VM Service の screenshot は **base64 を JSON に詰める**
  方式で ~33% 肥大＋全バッファリングという既知コストを負う。ゲームエンジンも「pixels は専用の
  binary/video パイプ、control は軽量 JSON」と二分する（Unreal Pixel Streaming=WebRTC、
  Unity=binary socket、同一プロセス時は共有 GPU メモリ）。
- **評価**: ✅ **最適。変更しない。** ただし Syphon はフレーム経路に構造データの side-channel を
  持たない（pixels-only）。NDI（per-frame XML metadata）や Spout（shared-memory buffer）と違い、
  **構造化状態は別チャネルが必須** ——これが観測プレーン（Probe）が独立して存在する理由でもある。

### 3.2 観測 = Probe ファイル（ポーリング往復）

AI が `request.json` を書き、producer が次フレームで `current/frame.{png,json}` を atomic に書く。

- **業界比較**: 「外部ツール ⇄ 実行中ランタイム」の主流は **JSON-RPC over stdio/WebSocket**
  （LSP/DAP/MCP=stdio、CDP/Flutter VM Service/Unreal Remote Control=WebSocket、dev server HMR=WebSocket）。
  サーバ発の push・低レイテンシ・request/response 相関が理由。creative 系の AI 連携（Blender/TD/
  Houdini の MCP サーバ）も socket/HTTP が定石で、**file-polling を制御 transport にする例は稀**。
- **だが file-polling は誤りではない**:
  - **MCP 自身の大バイナリ戦略 = `resource_link`**（巨大/バイナリは base64 で詰めず `file://` URI を
    返しクライアントが帯域外フェッチ）。Probe の「PNG をファイルに書き consumer が読む」はまさにこれ。
  - **cli 非依存**: cli 無しでも `request.json` を書けば観測が成立。AI エージェントの**ファイルツールが
    そのまま transport** になり、ソケット/ハンドシェイク/フレーミング不要。
  - **再起動耐性**: ホットリロードで子プロセスが毎回 kill→再起動されても、ファイルは跨いで残り新プロセスが
    拾う。永続接続なら毎回ハンドシェイク再確立が要る。
- **評価**: ⭕ **スナップショット用途には妥当。** 決定論・replay・単純さ・cli 非依存の対価として
  file-polling を選んでいる。弱点はライブ制御（push 不可・ポーリングレイテンシ・相関の手組み）で、
  **対話的ライブ制御に広げるなら** §6 の JSON-RPC 化が王道。

### 3.3 制御 = HID 注入（stdin JSON Lines）

[InputInjectionPlugin.swift](../../Sources/MetaphorCore/Input/InputInjectionPlugin.swift) が stdin の
JSON Lines（`mouseDown`/`mouseUp`/`mouseMove`/`mouseDrag`/`scroll`/`keyDown`/`keyUp`）を `InputManager` に
注入する。

- **なぜ必須か（前提からの帰結）**: ①metaphor のスケッチは Processing 由来で**対話的になりうる**
  （`mouseX`/`mousePressed`/`key` が中核 API）。②無停止ホットリロードのため**ウィンドウ=親(cli)・
  レンダラ=子(headless)** にプロセス分割している（[live-viewer.md](live-viewer.md) 方式C）。
  ③ゆえに親ウィンドウの実マウス/キーイベントを子へ運ばなければ、ライブビューア上の対話スケッチが
  入力に一切反応しない。**HID 注入はこの橋渡しそのもの**で、「対話スケッチ × 無停止リロード」の交点で
  論理的に不可避。対話性かプロセス分割のどちらかを捨てれば不要になる、前提相対の必須性。
- **副次的意味**: 同じ stdin チャネルなので、AI/自動ハーネスが同形式の合成イベントを送れば対話スケッチを
  プログラム的に駆動できる（Probe=観測の対になる"操作"の半分）。
- **限界**: 運べるのは **HID イベントのみ**。スケッチのパラメータ値を set する制御面は**無い**。
- **業界比較**: creative 系の定石は OSCQuery/ossia 流の**型付きパラメータツリーを get/set**する制御面
  （Max/vvvv の native OSCQuery、Resolume の OpenAPI REST）。metaphor は HID 再生のみで、ここは未実装
  （§6 の defer 候補）。

## 4. Issue #119（案D）の評価

### 4.1 事実（コードを読んで確認）

- **consumer(cli) は契約型を struct で持たない**。`ProbeSnapshotTool.swift` / `ProbeSequenceTool.swift`
  は `JSONSerialization` + `[String: Any]` で `request.json` を手組みし、`frame.json` からは ready 判定の
  `id` / `frameCount` だけ抽出、残りは AI へ **verbatim 透過**（decode しない）。
- producer の Probe 型は `internal struct`。共有には可視性変更＋cli のライブラリ依存化（プロセス分離の
  前提を崩す）が必要。
- Issue の動機例（`stats.contentBounds` の原点左上・正規化、`customTypes` のタグ集合、`every` の既定値）は
  **意味論**で、Swift の型に表現できず grep でも守れない。

### 4.2 結論: 案D は不採用

1. **consumer に効かない**: cli は decode しないので、共有型を入れても consumer 側にコンパイル時保証が
   付かない（cli が辞書→型へ移行する別リファクタをしない限り）。verbatim 透過する `frame.json` 本体は
   恒久的に保証外。
2. **意味論は型外**: 動機例は座標原点・正規化・既定値という意味論で、型(案D)でも grep でも守れない
   （型が捕まえるのは構造的リネーム/型変更だけ）。
3. **コストが見合わない**: 契約面は小さく additive 安定（`ProbeRequest` 5 フィールド／環境変数 5 個／
   入力イベント 7 個）なのに、新パッケージ・リポ、3 者依存グラフ（metaphor→protocol→cli）、可視性変更、
   cli の辞書→型移行という恒久コストを負う。

## 5. 結論: 契約ドリフトは案C+（wire schema 正典）で解く

業界事例は **契約の正典化がトランスポート非依存で一点に収束**することを示す: LSP=`metaModel.json`、
CDP=PDL→JSON、DAP=JSON Schema、Flutter VM=versioned `service.md`、creative 系ネイティブの
**OSCQuery=型・値域・access つき JSON namespace**、Confluent/buf=単一スキーマ＋互換性自動検出。
いずれも「**単一の機械可読スキーマを正典にし、型共有ではなく検証/生成、capability/version で
additive 進化**」。Pact も「typed decode せず matcher で適合検証」で、consumer 非 decode の本ケースに合致。

→ metaphor は **wire format（JSON）レベルの単一スキーマを契約の正典にする（案C+）**。

- producer が `contract/*.schema.json` を所有し、実エンコーダ出力 ⊨ schema をテスト。
- consumer は `request.json` 出力 ⊨ schema をテスト（**decode 不要で効く**のが型共有との決定的差）。
- `schemaVersion` を `const` 化して bump を可視化。grep は非 JSON 契約点（Syphon pin・環境変数名・
  doc パス・headless 挙動）に縮小する二層構成。

### 5.1 正直な留保（過大評価を避ける）

- 価値は「**grep が見られなかった JSON の構造・値域・enum・バージョンを、consumer 出力も含め機械検証**」に
  限定される。深い意味論（contentBounds の「原点左上」、`every` の既定値）は依然 `description`／コード
  止まり（JSON Schema の `$comment` はツール非表示、`default` は非強制）。これは CONTRACT.md 散文と同等で、
  案C+ でも変わらない。動機 3 例のうち堅く強制できるのは `customTypes`（`enum`）と contentBounds の
  正規化範囲（`min`/`max`）で、座標原点と既定値は注釈止まり。
- JSON Schema の破壊的変更検出は未成熟（buf/oasdiff/Avro と違い WIP）。進化ガードは `const: schemaVersion` の
  可視化＋小さな自作チェック程度に留め過信しない。
- Swift ネイティブ validator は貧弱 → CI は `ajv-cli`(Node)/`check-jsonschema`(Python) に shell out
  （非 Swift の CI 依存が 1 つ増える）。

## 6. 将来オプション（今は不要・defer）

- **ライブ制御の JSON-RPC 化**: 低レイテンシ/イベント push/対話的 AI 制御が要件化したら、既存 stdin を
  **双方向 JSON-RPC over stdio（LSP/DAP/MCP 流）** へ昇格。frames は Syphon、大バイナリは file/URI
  （MCP resource_link）に残す。Issue #119 を解くのに**必須ではない**。
- **パラメータ制御面**: AI にパラメータ調整をさせる目標が立ったら、**OSCQuery 流の型付きパラメータツリー**
  （`type`/`value`/`range`/`access`/`description` ＋構造変化通知）を観測（Probe）と統合した形で追加。
  これは現状の HID 注入では届かない領域。

これらは正典スキーマ（案C+）の上に additive に載るため、file transport を続けても将来 JSON-RPC へ
移っても無駄にならない。

## 7. 影響範囲と次アクション

- **現アーキテクチャ（Syphon/Probe/HID）は健全。変更しない。**
- Issue #119 は **案D 不採用・案C+ 推奨**で着地。実装（`contract/*.schema.json` ＋ 両側検証テスト ＋
  CI validator step ＋ grep 縮小、cli 側は別リポ追従 PR）は本書とは別スコープ。着手時は最小有効量
  （`frame.schema.json` ＋ `request.schema.json` ＋ producer/consumer テスト各 1 本）から。
- 設計判断として ADR 化を検討（[../adr/](../adr/)、「wire schema 正典 vs 共有型」）。
