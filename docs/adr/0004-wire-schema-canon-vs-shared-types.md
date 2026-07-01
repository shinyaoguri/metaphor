# ADR-0004: 契約ドリフトを共有型ではなく wire スキーマ正典で防ぐ（Issue #119 案C+）

- **Status**: Accepted
- **Date**: 2026-07-01
- **Deciders**: PR で確定（設計ノート [docs/design/external-coupling-and-contract.md](../design/external-coupling-and-contract.md)、Issue #119）
- **PR / Commit**: 本 PR（`contract/*.schema.json` + 両側検証）

## Context

metaphor（producer）と metaphor-cli（consumer）は別リポ・別 SwiftPM パッケージで、cli は metaphor を Swift ライブラリとして依存していない（子プロセス分離は Swift dylib のアンロード不能問題に由来する本質的制約）。両者は **ランタイム/バイナリ契約**（[CONTRACT.md](../../CONTRACT.md)）だけで結合し、`scripts/check-contract.sh` の grep ベースのトークン存在チェックで守られてきた。

grep は「合意済みトークンのリネーム/削除」は捕まえるが、**JSON の構造・値域・enum・バージョン**を検証できない。とりわけ Probe 契約点（`request.json` / `frame.json` / `sequence.json`）は、consumer(cli) が契約型を **decode せず** `JSONSerialization` + `[String: Any]` で `request.json` を手組みするため、grep も型共有も consumer 出力には効きにくい。

Issue #119 は「契約型を極小 SwiftPM パッケージ `metaphor-protocol` に切り出し、両リポが url 依存してコンパイル時保証へ昇格する（案D）」を提案した。本 ADR はこの提案を評価し、代替の決定を確定する。設計ノート（[external-coupling-and-contract.md](../design/external-coupling-and-contract.md)）が判断過程、本 ADR がその確定記録。

## Considered Options

### Option A（案D）: 契約型を共有 SwiftPM パッケージに切り出す
- Pros: producer/consumer が同じ Swift 型を import すれば、構造的リネーム/型変更はコンパイルエラーで即検出。
- Cons: **consumer に効かない**——cli は `request.json` を decode せず辞書で手組みし、`frame.json` は verbatim 透過するため、共有型を入れても consumer 側にコンパイル時保証が付かない（cli が辞書→型へ移行する別リファクタをしない限り）。**意味論は型外**——動機例（`contentBounds` の原点左上・正規化、`customTypes` のタグ集合、`every` の既定値）は型に表現できない。**コスト過大**——契約面は小さく additive 安定（`ProbeRequest` 5 フィールド／環境変数 5 個／入力イベント 7 個）なのに、新パッケージ・リポ、3 者依存グラフ（metaphor→protocol→cli）、可視性変更、cli の辞書→型移行という恒久コストを負う。

### Option B: 現状維持（grep のみ）
- Pros: 追加コストゼロ。
- Cons: JSON の構造・値域・enum・バージョンを検証できず、consumer 出力（`request.json`）も守れない。契約ドリフトの主要な失敗モード（キー追加/型変更/値域逸脱）を素通りさせる。

### Option C+（採用）: wire format（JSON）レベルの単一スキーマを契約の正典にする
- `contract/*.schema.json`（JSON Schema draft 2020-12、両リポに同一内容）を producer が所有し、実装（`Sources/MetaphorCore/Probe/`）を意味の正典として機械可読に写す。
- producer が実エンコーダ出力 ⊨ schema、consumer が `request.json` 出力 ⊨ schema をテスト（**decode 不要で効く**のが型共有との決定的差）。
- `schemaVersion` を `const` 化して bump を可視化。grep は非 JSON 契約点（Syphon pin・環境変数名・doc パス・headless 挙動・原子書き込みトークン）に縮小する二層構成。
- Pros: consumer 出力にも効く。業界事例（LSP=`metaModel.json`、CDP=PDL→JSON、DAP=JSON Schema、OSCQuery、Pact の matcher 適合検証）が「単一の機械可読スキーマを正典にし、型共有ではなく検証/生成、capability/version で additive 進化」に収束するのと一致。transport 非依存（file-polling を続けても将来 JSON-RPC へ移っても無駄にならない）。契約面が小さいので実装も小さい。
- Cons: 深い意味論（原点左上・既定値）は依然 `description`／コード止まり（`$comment` はツール非表示、`default` は非強制）。JSON Schema の破壊的変更検出は未成熟。Swift ネイティブ validator が貧弱なため CI は `check-jsonschema`（Python）へ shell out（非 Swift の CI 依存が 1 つ増える）。

## Decision

Option C+ を採用する。決め手は「**consumer が decode しない**本ケースでは、型共有（案D）は consumer にコンパイル時保証を与えられず、wire schema だけが consumer 出力（`request.json`）まで機械検証できる」こと。契約面は小さく additive 安定なので、新パッケージ・3 者依存グラフ・可視性変更という案D の恒久コストは見合わない。

具体（最小有効量から着手）:

1. `contract/frame.schema.json` / `request.schema.json` / `sequence.schema.json` と `contract/examples/*.json` を producer が所有。
2. 検証は二段。**Swift テスト**（`ProbeSchemaConformanceTests`）が実型のエンコード結果と `examples/` の構造一致を守り（examples が実型からドリフトしない番人、GPU 不要）、**shell**（`scripts/check-contract-schema.sh` = `check-jsonschema`）が `examples/` を各スキーマで検証する。推移的に実エンコーダ出力 ⊨ schema。Swift ネイティブ validator は使わない（§5.1）。
3. consumer(cli) 側も同じ `contract/` を同期し、`request.json` 生成経路のテストで出力 ⊨ `request.schema.json` を検証。
4. `scripts/check-contract.sh` の grep は JSON 構造検査から降り、非 JSON 契約点＋`schemaVersion` の値に縮小。

## Consequences

### Positive
- consumer が書く `request.json` を含め、JSON の構造・キー・値域・enum・`schemaVersion` を両リポ CI で機械検証できる。
- grep（構造）と schema（値域・enum・version）の役割が分離し、契約の正典が一点（`contract/`）に収束。
- transport 非依存で additive 進化に前方互換（将来 JSON-RPC 化や OSCQuery 流パラメータ制御面を載せても無駄にならない）。
- 現アーキテクチャ（Syphon/Probe/HID）は健全なまま。変更しない。

### Negative / Trade-offs
- 深い意味論（`contentBounds` の原点左上、`every` の既定値）は強制されず `description`／コード止まり。過大評価しない。
- JSON Schema の破壊的変更自動検出は未成熟。進化ガードは `const: schemaVersion` の可視化＋小さな自作チェックに留める。
- CI に非 Swift 依存（`check-jsonschema`、Python）が 1 つ増える。
- `contract/` と `CONTRACT.md` を両リポで同一に保つ運用コスト（`check-contract-identity.sh` は現状 CONTRACT.md のみ対象。schema/README は README 規約＋手動同期）。

### Follow-ups / 残課題
- 案D は不採用として Issue #119 をクローズ。
- ライブ制御の JSON-RPC 化・OSCQuery 流パラメータ制御面は defer（要件化したら別 ADR）。正典スキーマの上に additive に載る。
- `check-contract-identity.sh` の対象を schema/README へ広げるかは将来判断。

## References
- 設計ノート: [docs/design/external-coupling-and-contract.md](../design/external-coupling-and-contract.md)（案D 評価・案C+ 導出、§5.1 の留保）
- 契約: [CONTRACT.md](../../CONTRACT.md)（契約点 4「wire スキーマの正典」）
- 正典スキーマ: `contract/*.schema.json` / `contract/README.md`
- 検証: `scripts/check-contract-schema.sh`、`Tests/metaphorTests/ProbeSchemaConformanceTests.swift`
- Swift 型: `Sources/MetaphorCore/Probe/ProbeFrameMetadata.swift` / `ProbeRequest.swift` / `ProbeSequenceManifest.swift`
- Issue #119、Epic #75
