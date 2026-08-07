# 設計: ライブツーリング基盤（Parameter Store / 状態保持リロード / インスペクタ / 往復レイテンシ）

- **ステータス**: **A（Parameter Store）の D1 = ストアコア + `@Param` + `.metaphor/params/` は実装済み**（2026-08-07）。B / C / D と A の残り（D2 GUI 自動パネル / D3 `frame.json` の `params` 節 / D4 cli の MCP ツール）は設計叩き台のまま。実装 PR で確定した内容が正となり、契約変更は [CONTRACT.md](../../CONTRACT.md)（契約点 7）が正典
- **親**: [roadmap-processing-unity.md](roadmap-processing-unity.md) の Epic C / D / H
- **作成**: 2026-07-30

## 方式の要諦

**新しい RPC を作らず、Probe の request/response パターン（アトミック書込・mtime ポーリング・id エコー・JSON Schema 正典 = [ADR-0004](../adr/0004-wire-schema-canon-vs-shared-types.md)）を `.metaphor/` 配下の新ファセットとして拡張する。**

- **対称性がタダで手に入る**: AI のファイルツールがそのままトランスポートになる（Probe と同じ論法）。人間の GUI はプロセス内から同じストアを書く。二重システムを作らない
- **リロード耐性がタダで手に入る**: ファイルは子プロセスの kill/relaunch を生存する。まさに A/B が動くべき瞬間に強い。stdio RPC セッションは子と一緒に死ぬ
- **契約機構が既にある**: `contract/*.schema.json`・examples・`check-contract-schema.sh`・byte-identity CI にそのまま乗る
- **stdin は純粋 HID のまま**（契約点 3 不変）。プレーンモデルは「video = Syphon / observation = Probe ファイル / control = stdin HID + 制御ファイル」となり、[external-coupling-and-contract.md](external-coupling-and-contract.md) §6 が予期した「Probe 統合のパラメータ制御面」に一致する（第 4 プレーンの新設ではない）

## A. Parameter Store（基盤・最初に作る）

### 仕組み

`SketchContext` に `ParameterStore`（`gui` の兄弟）、加えて `ParameterPlugin`（MetaphorCore、`MetaphorProbePlugin` と同型）:

1. **登録**: `@Param` property wrapper で宣言。sketch `init()` 後・`setup()` 前に Mirror 反映で名前発見（`_radius` → `radius`）。挿入点は `SketchRunner` のプラグイン登録〜`setup()` の間
2. **永続値ロード**: `.metaphor/params/params.json` から読み、コード既定値の上に適用（name+type 一致で採用・不一致は破棄）。`setup()`/`draw()` は最初から復元値を見る
3. **外部書込の適用**: `pre()` で `.metaphor/params/set-request.json` を mtime ポーリング（Probe と同じ 1 frame 1 stat() のコストプロファイル）→ 適用 → `params.json` を `appliedRequestId` エコー付きでアトミック再書出
4. **永続化**: 変更時に書出（GUI ドラッグは ~200ms デバウンス・set-request 起因は即時）

有効化: `@Param` が 1 つでも宣言されていれば自動有効（素の `swift run` でも永続化が効く = cli 不要の単独価値）。オプトアウトは `METAPHOR_PARAMS=0`。

### スケッチ作者 API（案）

```swift
@main final class MySketch: Sketch {
    @Param(min: 10, max: 200) var radius: Float = 50   // 1 行 1 パラメータ
    @Param var showGrid: Bool = true
    @Param var tint: Color = .white

    func draw() {
        gui.params()        // 任意: 全 @Param の自動パネル描画
        circle(width/2, height/2, radius)
    }
}
```

- `gui.params()` は ParameterGUI の新メソッド。既存 slider/toggle/colorPicker ウィジェットを store-backed で再利用
- 既存の即時モード `gui.slider("x", &x, …)` は不変。名前だけの overload `gui.slider("radius")` で store に束縛
- v1 型セット: `float` / `int` / `bool` / `color` / `vec2` / `vec3` / `string`（`choices` 付き）— `ProbeValue` のタグ体系と整合

### ファイル形式（案）

```jsonc
// .metaphor/params/params.json — 子プロセスが唯一の書き手・アトミック書出
{
  "schemaVersion": 1,
  "revision": 42,
  "appliedRequestId": "01J…",   // 最後に適用した set-request の id（確認用）
  "params": [
    {"name": "radius", "type": "float", "value": 120.0, "min": 10, "max": 200},
    {"name": "tint",   "type": "color", "value": [1, 1, 1, 1]}
  ]
}

// .metaphor/params/set-request.json — 外部（AI/ツール）が .tmp→rename で書く・毎回新しい id
{ "id": "01J…", "values": { "radius": 120.0, "showGrid": false } }
```

さらに `frame.json` に additive な `params: {revision, values{…}}` 節を追加（`performance` と同じ additive ルール。1 回の snapshot で「画像 + それを生んだパラメータ」が揃い、`sourceStamp` の来歴と合成できる）。

### 分担・契約・規模

- **metaphor**: wrapper + store + plugin + GUI 自動パネル + スキーマ + 適合テスト — **M**
- **metaphor-cli**: MCP ツール `params`（params.json 読み）/ `set_param`（set-request 書き→ `appliedRequestId`/`revision` エコー待ち。`ProbeSnapshotTool` と同型）— **S–M**
- **契約**: 契約点 7 新設（params ファイル + `params.schema.json` + `param-set-request.schema.json` + examples）、`frame.json.params` の additive 追記。**クロスリポ同時 PR 必須**

## B. 状態保持リロード

[live-viewer.md](live-viewer.md) Phase 2 の saveState/restoreState フックを維持しつつ、トランスポートを stdin 動詞/stdout base64 から**ファイルベースへ変更**して実装する（→ live-viewer.md §A-3 は本設計で改訂する）。

- リビルド前: cli が `.metaphor/state/save-request.json` `{id}` を書く → `StatePlugin`（`pre()` で mtime ポーリング）が `sketch.saveState()` を呼び `.metaphor/state/state.json` をアトミック書出 → cli が id 一致で ready 検知（Probe と同じ手順）→ 子を kill・`METAPHOR_RESTORE_STATE=<path>` 付きで再起動 → 新しい子が `setup()` 後に適用
- デコード失敗・タイムアウト（~250ms）は黙って新規起動（元設計のフォールバック）
- `state.json` は 2 節: `runtime`（frameCount/経過時間。`config.preserveClock` オプトインで metaphor 自身が復元 = スケッチコードゼロでもアニメが t=0 に戻らない）+ `user`（`saveState()` の opaque ペイロード）

```swift
struct SimState: Codable { var particles: [Particle] }

func saveState() -> Data? { encodeState(SimState(particles: particles)) }
func restoreState(_ data: Data) {
    guard let s: SimState = decodeState(data) else { return }
    particles = s.particles
}
```

両方とも `Sketch` にデフォルト実装（nil / no-op）で「draw() 以外は全部任意」を維持。

- **metaphor**: フック + ヘルパー + StatePlugin + env var — **M** / **metaphor-cli**: 監督シーケンス — **S**
- **契約**: env var `METAPHOR_RESTORE_STATE`（契約点 2）+ state ファイル群（`user` 節はエンベロープのみスキーマ管理・中身は意図的に opaque）。クロスリポ同時 PR
- **順序**: A の後（パラメータという「最も保持したい状態」は A だけでリロードを生存するため。B はシミュレーション状態と時計のため）

## C. インスペクタ / シーン観測

正直なスコープ設定: metaphor は基本 immediate-mode であり、retained なオブジェクトを持つのは `MetaphorSceneGraph` スケッチのみ。Unity 完全対等のインスペクタは一歩では届かないが、「ツリーを見る → 選ぶ → プロパティを編集 → 即反映」という Unity の**体感**は、A の機構 + 薄い 2 層に分解できる:

- **C1 シーンツリー観測**: `ProbeRequest` に optional `include: ["scene"]` → `frame.json` に additive `scene` 節（Node ツリー: name/transform/visible/bounds/color/children）。Tier 規則（Core は SceneGraph に依存できない）は probe plugin への汎用 provider hook で解決（`scene.probeAttach(sketch)` の 1 行で登録。physics や particles も同じ手口でツリーを公開できる）
- **C2 プロパティ編集 = A の名前空間利用**: 新機構ゼロ。`node.expose(params)` が `scene/cube1/position` 等を Parameter Store に公開。GUI 自動パネルは prefix でグルーピング、MCP は `set_param("scene/cube1/position", …)` で再ビルドなしにキューブが動く（~50ms）。人間パネルと AI が同一ストアを叩く = 対称性が構造的に満たされる
- **C3 クリック選択（設計予約のみ・今回スコープ外）**: `request.json` に additive `pick:{x,y}` → `frame.json` に `pick:{node}`（既存 `worldBounds` AABB のレイテスト）。ビューア側選択 UI は cli の将来マイルストーン
- インスペクタ**パネル**はまずスケッチ内 `gui.params()`（cli 作業ゼロ・どのウィンドウでも動く）。cli ネイティブのサイドパネル（params.json + scene 読み・set-request 書き = UI 付き MCP クライアント）は後日 **L**
- **metaphor**: provider hook + `Node.expose` + scene シリアライズ — A の上に **M** / **metaphor-cli**: C1/C2 は変更不要（`snapshot` は `frame.json` を素通しするため additive 節はそのまま流れる）

## D. 往復レイテンシ

現状 p50 2,811ms（[roundtrip-measurement.md](roundtrip-measurement.md)。律速 = incremental swift build + 子再起動。観測は 35.6ms）。

1. **最大の勝ち筋は「再分類」**: A により、値の変更は再ビルド不要の ~50–100ms ファイル往復になる（set-request → 次フレーム適用 → params.json エコー、必要なら + 35ms の snapshot）。シェーダは既にホットリロード可。**2.8 秒はコード構造変更のときだけ**に限定される。新指標: param-roundtrip p50 < 100ms（cli の `measure-roundtrip.py` にモード追加）
2. **ビルド経路は控えめな改善に留まる**: SwiftPM にデーモンはなく、Swift コードの sub-second 編集→反映は本アーキテクチャでは非現実的。見込み: FSEvents 検知・ビルドコマンド調整・spawn 重畳で 2,811 → ~1,800–2,200ms（cli 側 **M**）
3. **計測が先**: `T_detect / T_build / T_relaunch` の分解計測（cli **S**。roundtrip-measurement.md が既にバックログ指摘）を最適化より先に行う
4. **B は体感の再起動コストを削る**（状態が飛ばない・時計が戻らない）
5. **エージェント指導も D の一部**: `llms-sketch.txt` / `docs/ai/` に「チューニング値は `@Param` で宣言し、`set_param` + `snapshot` で回す。コード編集は構造変更のときだけ」を追記（AI が実際に回すループそのものを変える）

## 順序と初回マイルストーン

```
A (store+wrapper+files+GUI → cli MCP ツール)      ← 基盤
├─→ frame.json params エコー（A と同時）
├─→ C1 scene 節 + C2 node.expose                  ← A の上の薄い層
├─→ B 状態フック（A のファイル/ready 規約を流用）
└─→ D: 計測分解 + param-roundtrip 指標（cli・いつでも並行可）
後日: cli インスペクタサイドパネル・C3 ピッキング・ビルド経路チューニング
```

**最強の初回マイルストーン = A 一式 + D 計測**。他のすべてが A に依存し、素の `swift run` / watch / MCP のどのモードでも単独価値があり、製品の看板数値を「2,811ms」から「最頻イテレーションは <100ms」に変える。

## 未決事項（2026-08-07 に 1 / 2 / 4 / 5 / 7 を確定、3 / 6 は B 着手時）

1. **確定: Mirror によるラベル発見 + 明示名 override**（`@Param("myName")`）。将来 Swift macro で置換可。トップレベルのプロパティのみ発見対象（ネストした型の中は対象外）
2. **確定: last-writer-wins + `revision` エコー**。`ifRevision` 楽観ロックは入れない（拒否時のリトライ規約とエラー面を契約に増やす割に、人間がツマみながら AI が書く実際の使い方で得が薄い）。反映確認は `appliedRequestId` + `revision`、拒否理由は `params.json` の `warnings[]`
3. 未決（B のスコープ）: `preserveClock` の既定は オプトイン（推奨・t 駆動スケッチの驚き最小）か、watch 時デフォルト ON か
4. **確定: スケッチディレクトリ単位で固定・v1 はプリセットなし**。名前付きプリセットは実作品（Epic J [#414](https://github.com/shinyaoguri/metaphor/issues/414)）で必要になったら additive に足す
5. **確定: スケッチ内 `gui.params()` 先行 → cli サイドパネルは後日**
6. 未決（B のスコープ）: live-viewer.md §A-3（stdin saveState 動詞 + stdout base64）の正式な改訂タイミング（B の実装 PR で同時改訂を想定）
7. **確定: `string` の `choices` は v1 から入れる**。`params.json` に `choices` が出るので AI に合法値がそのまま伝わり、範囲外は拒否されて `warnings[]` に載る

### D1 の実装で決めた細部（設計叩き台からの差分）

- **`warnings[]` を `params.json` に追加**（叩き台の形式には無かった）。拒否理由（未知の名前・型不一致・`choices` 外）を返す面が無いと、AI は「書いたのに変わらない」を無言で踏む。`frame.json` の `warnings[]` と同じ流儀
- **`min` / `max` は外部書き込みのみクランプ**し、コードからの代入は素通し（スケッチ作者のコードを驚かせない）
- **`revision` はプロセス起動時にも 1 つ進む**。宣言そのもの（新しい `@Param`・レンジ変更）が変わり得るため、「内容が変われば revision も変わる」を保つ
- **`Float` と `Double` はどちらも型タグ `float`**（wire は JSON number のため）
