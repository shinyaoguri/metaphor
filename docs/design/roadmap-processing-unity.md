# ロードマップ: Processing 移行者獲得と AI 制作能力（v0.8〜v0.10 相当）

- **ステータス**: 運用中（living document）。各フェーズ完了時に見直し、Issue 番号・設計変更を本ドキュメントへ追記する。旧題「Processing / Unity ユーザー獲得」— Unity 移行者獲得の市場仮説は 2026-08-15 に降ろした（決定 7）。ファイル名は既存リンク保全のため維持
- **作成**: 2026-07-30（リポジトリ全体レビューに基づく）
- **正典**: 本ドキュメント + 各 Epic Issue。詳細設計は個別の design doc（例: [live-tooling-params.md](live-tooling-params.md)）へ委譲

## ポジショニング宣言（全優先判断のアンカー）

**metaphor は「人間と AI が同じ実行中スケッチを一緒に操作できる」クリエイティブコーディング環境である。**

- Processing ユーザーは「週末でスケッチが移植できる + キャンバスを見て操縦できる AI ペア」で乗り換える
- ~~Unity ユーザーは「エディタ税なしの Metal ネイティブなモダン 3D + 同じ AI ループ」で乗り換える~~ → **Unity 移行者獲得の市場仮説は降ろした**（2026-08-15・決定 7）。モダン 3D は「AI が到達できる絵の天井」のために作る
- API パリティは摩擦の除去、AI 協調ループが乗り換えのトリガー。パリティ単体では誰も乗り換えない
- パリティ軸に**作品軸**を併走させる（2026-08-07 追加）: 「metaphor で大規模インタラクティブ作品を一本作り切れるか」を検証指標に持ち、構造化支援・現場運用の設計は実作品の要求から逆算する（下記「作品トラック」）
- **AI 制作能力（AI authoring）を中心目標に置く**（2026-08-15 追加・決定 7）: 「一緒に操作できる」の先の「**AI が一人でも作り切れる**」— AI エージェントが metaphor でゲーム・3DCG アニメーション・シミュレーションをハイクオリティに作り切れることを技術目標とする。Three.js で AI がハイクオリティを出せる構造（学習分布 / 表現力の天井 / アセット経路 / 実行・観測ループ）のうち、metaphor に足りないのは**表現力の天井（PBR maps・IBL・glTF = Epic G）とアセット経路（G4）**で、**実行・観測ループ（Probe・決定論・MCP）は既に Three.js を上回る** — この優位を #563/#564/#567/#608 で伸ばす。競合調査（2026-08-15）で「決定論的観測 + AI 操作」を持つ環境は他に存在しないことを確認済み

## レビュー所見の要約（2026-07-30 時点）

全体レビュー（API 面・DX/ツールチェーン・アーキテクチャ拡張性の 3 観点）の結論:

### 強み

- 2D 描画・beginShape/contour・MShape（PShape 相当）・3 層バッチング/インスタンシングは完成度が高い
- 3D はプリミティブ + OBJ/USDZ/ABC・シャドウ・スカラー PBR・CustomMaterial・自動インスタンシングまで到達
- 差別化の核が既に存在する: Probe（決定論観測・performance 節）+ ライブビューア + MCP。warm snapshot p50 35.6ms
- 工学品質（テスト 1,041 本・ADR・契約管理・生成物の陳腐化検出）は機能面の見た目以上に高く、大きな機能成長を吸収できる

### 主要ギャップ

| 対象 | ギャップ |
|---|---|
| Processing 移行者 | データ IO（loadJSON/loadTable 等）・SVG 入出力・PDF・フォントファイル読込・textToPoints・PVector 風メソッド・2D カスタムシェーダ・OSC 送信・音声合成 |
| Unity 移行者 | コンポーネントモデル・ピッキング・PBR テクスチャマップ・キューブマップ/IBL・glTF・明示的インスタンシング API・3D 物理・インスペクタ |
| 両者共通 (DX) | 編集→反映 p50 約 2.8 秒（律速はビルド+子プロセス再起動）・リロード時の状態非保持・英語ドキュメント不足 |

### 拡張時のアーキテクチャ制約

- 全面 `@MainActor`（ジョブシステム化は隔離モデルの再設計が必要 → 非目標）
- `TextureManager` は `colorAttachments[0]` 固定（MRT 不可 → deferred rendering は非目標）
- ~~`Canvas3D.swift`（約 1,700 行）はパイプライン系機能を足す前に分割が必要（Epic G の門番タスク）~~ → [#439](https://github.com/shinyaoguri/metaphor/issues/439) で関心事ごとの `Canvas3D+*.swift` へ分割済み（本体 1,985 → 435 行）
- 3 層 API 転送（Sketch → SketchContext → Canvas）のため、新プリミティブ 1 つに 3 箇所編集。小粒 API は束ねて実装する

## レビュー所見の追補（2026-08-07 機能インベントリ）

「ある程度大規模なインタラクティブコンテンツの制作基盤として現状で十分か」の観点で全モジュール・全 Examples を棚卸しした。結論: **絵を出す力は既に中規模以上、足りないのは作品を組み立てて現場に置く力**。移行者獲得のパリティ軸だけでは拾えないギャップが 3 層に分かれて存在する:

| 層 | 内容 | 受け皿 |
|---|---|---|
| A. 構造 | シーン管理（切替・遷移）・状態機械・タイムライン/キュー・スケジューラが皆無。tween/easing（30 種）はあるが演目として並べる層がない。Examples 278 本の最大は 303 行で、複数シーン + 複数入力 + 長時間運用の統合リファレンス不在 | Epic K [#415](https://github.com/shinyaoguri/metaphor/issues/415)（J の所見待ち） |
| B. 現場運用 | `NSScreen` 参照ゼロ（マルチディスプレイ配置不可）・キオスク運用なし（常時最前面/スリープ抑止/自動復帰）・自己監視の公開 API なし（#273）・本番経路の GPU エラー検知なし・パラメータ永続化なし | 永続化は Epic D #290、他は Epic L [#416](https://github.com/shinyaoguri/metaphor/issues/416) |
| C. 接続 | DMX/Art-Net・NDI・シリアル（Arduino）・深度センサ・マルチタッチ・音声入出力デバイス選択が参照ゼロ | Phase 4（需要ゲート）へ追記 |

強みの確認（再投資不要）: GPU 系（パーティクル・compute・postFX = 自前 7 + MPS 4 + CIFilter 82）・OSC/MIDI 送受・マルチウィンドウ = マルチ Syphon サーバ・決定論レンダリングと書き出し・エラー設計・Probe/MCP。**Syphon で VJ ソフトへ送るライブビジュアル用途は現状で実用域**（現場層を外部ツールが肩代わりするため）。ギャップが効いてくるのは単体アプリとしての展示・常設。

この所見から作品軸と「作品トラック」（Epic J/K/L）を追加した。

## 戦略的判断（決定事項）

1. **各フェーズ = フラッグシップ 1 つ + S/M パリティ束**。比率は Phase 1 ≈ 80% Processing / Phase 2 ≈ 50:50 / Phase 3 ≈ 80% Unity。S 項目は 3 層転送コストの償却のため同一 PR トレインに束ねる
2. **AI 協調を統一柱にする**。Parameter Store（Epic D）が要石: ParameterGUI の土台・リロード生存・Probe/MCP からの読み書き・将来のインスペクタのデータモデルを 1 機能で兼ねる
3. **往復レイテンシはクロスリポ Epic として本ロードマップが持つ**（metaphor 側 = 状態保持、cli 側 = ビルド高速化。2 リポの間に落とさない）
4. **英語ドキュメントは並行トラックで in scope**（README/Getting Started → 公開 API doc コメント → website #74）。ADR 全訳は非目標
5. **glTF は採用（Phase 3・import のみ・skins/animations なし）。3D 物理は Jolt 等のラップを Phase 4 需要ゲートに置く**。2D Verlet ソルバの剛体拡張はしない（角度状態を持たない土台のため不適）
6. **作品駆動（2026-08-07 追加）**: 構造化支援（Epic K）・現場運用（Epic L）の子 Issue は、リファレンス作品（Epic J）の実需から逆算して起票する。抽象論で SceneManager を先に設計しない — ライブラリを Unity の劣化コピーへ向かわせないための規律。作品の完走は v1.0 昇格条件「metaphor-sketches での実運用検証」の具体化を兼ねる
7. **AI 制作能力を中心目標に置く（2026-08-15 追加・オーナー合意）**: 「AI が metaphor でゲーム・3DCG アニメーション・シミュレーションを作り切れる」を技術目標とする。付随する判断:
   - **Unity 移行者獲得の市場仮説は降ろす**。Phase 3 の実装項目（PBR maps / IBL / glTF）は 1 つも捨てず、目的を「AI が到達できる絵の天井を Three.js 相当へ引き上げる」に差し替える（glTF は「AI がアセットを調達する経路」として必然）。Unity 概念の移植（#294 H1 の GameObject/Component 等）は AI 制作実験の実需が出るまで起票しない
   - **スケルタルアニメーション・3D 物理の非目標/ 需要ゲートは維持**し、ゲートの「需要」に「**AI 制作実験で実際に詰まった**」を含める（下記 Phase 4）
   - **コミュニティ向け活動・情報発信より技術解決を先行する**。v1.0 昇格（スター 100）は急がない — [v1-release-plan.md](v1-release-plan.md) の「期限を設けない」方針と整合し、同文書の変更は不要
   - AI は metaphor を事前学習で知らないため、「調べずに書いても概ね当たる」を設計観点に加える: 新 API は Processing / p5 / Three.js の既知イディオムからの距離を基準に含め（ADR-0007 の延長）、examples-index を AI が模倣する型紙として扱う
   - 3D バックエンド戦略は #689 で決着（2026-08-15）: **自作 Metal 基盤 + 自前 glTF loader + Model I/O は `.obj`/`.usdz`/`.abc` の入口として維持**。SceneKit は deprecated（26.0）のため依存を作らず、RealityKit を visionOS/AR への出力面とする案は**再評価トリガー付きで保留**（トリガーは #689 のクローズコメント参照）

## フェーズ計画

リリースは週次トレインの自動版数のため、フェーズと版数は厳密には対応しない（v0.8 等は目安）。フェーズ管理はマイルストーンではなく Epic チェックリストで行う（Epic #75 と同じパターン）。

### Phase 1「週末でスケッチ移植」— 完了（2026-08-01）

目標: p5.js 上位例 50 本が diff 10 行未満で移植できる。スタブ example 3 本（LoadSaveJSON / LoadSaveTable / LoadDisplaySVG）が動く。

**完了記録**: metaphor 側の全 Issue（#278〜#286）を PR #297〜#306 の 10 本で実装・マージ（2026-07-30〜31）。テスト 1,041 → 1,128 本。スタブ example 3 本解消 + 新規 example 3 本（DropImage / OSCLoopback / SVGExport）。残タスクと引き継ぎ:

- **リリース済み（2026-08-07 追記）**: Phase 1 の全変更は **v0.8.0（2026-08-01）** としてリリース完了。以降の 0.8.x は破壊的変更ウィンドウとして [v1-release-plan.md](v1-release-plan.md) が管轄
- **cli#88（ビルド高速化 pass 1）完了（2026-08-01・cli PR #89/#90/#91）**: 分解計測で真の律速が「バイナリ解決のサイレント失敗 → 毎リロード ~490ms 浪費 + `swift run --skip-build` 経由の子起動 ~1.4s」と判明（当初想定の increment build ではなかった）。resolver の executable target フォールバック + FSEvents 検知で **roundtrip p50 2,768→986ms（-64%）・cold start 2,134→170ms**。目標 ≤1.5s を超過達成し Processing の起動体感（~1s）に到達。経緯・実測の正典は [cli#88](https://github.com/shinyaoguri/metaphor-cli/issues/88) のコメント。残る主要区間は build ~730ms（SwiftPM 増分の下限近く・追加短縮は将来の別 Issue）
- **設計変更（重要）**: #285 SVG 書き出しは Issue 当初案の「`Deferred2DCommand` replay」が**頂点バッチレベルで不成立**と判明し、図形 API フック方式（PGraphicsSVG 型）へ変更（ユーザー確認済み・Issue 本文改訂済み）。**#71（コマンド記録の一般化）を意味レベルで設計する際は、SVGRecorder のフック点（`Canvas2D` 図形メソッド入口）との統合を検討すること**
- **アーキテクチャ上の判断**: #284 アセットキャッシュは同一インスタンス返し（Unity の `Resources.Load` 意味論）。テクスチャ共有は `ImageFilterGPU` のプール回収と衝突するため不採用
- 副産物 Issue: [#298](https://github.com/shinyaoguri/metaphor/issues/298)（llms.txt が SIMD extension を拾わない — Vec2/Vec3 の PVector メソッド群が AI から見えない。Phase 1 の移植支援に効くため優先度high寄り）
- 目標指標（p5 上位例 50 本の移植性）の実測はまだ。実運用（metaphor-sketches での作品制作）で検証し、穴を Issue 化する方針

| 機能 | 対象 | 規模 | 備考 |
|---|---|---|---|
| データ IO（loadJSON/saveJSON/loadTable/saveTable/loadStrings/saveStrings、URL 対応） | Processing | S | Foundation のみ・レンダラ非接触 |
| Vec2/Vec3 の PVector 風拡張（normalize/limit/heading/rotate/lerp/setMag/dist） | Processing | S | SIMD typealias への extension |
| パスキーのアセットキャッシュ（loadImage/loadModel） | 両方 | S | 「draw() 内 loadImage」footgun の解消 |
| キャンバス操作束（applyMatrix/resetMatrix/shearX/Y/screenX/Y/Z/keyTyped/copy/mask/MImage.resize） | Processing | S×7 | 1 Issue・1 PR トレインに束ねる |
| selectInput/selectOutput + 既存 file-drop の公開 | Processing | S | NSOpenPanel/NSSavePanel |
| SketchConfig に MSAA 設定 | 両方 | S | 内部は 4x 実装済み |
| OSC 送信 | 両方 | S | 受信は実装済み。TouchOSC/VJ ループが完成 |
| **SVG 書き出し（フラッグシップ）** | Processing | M | 決定論コマンドストリーム（`Canvas2DCommand`）の replay で実装。プロッタ/印刷層への真のトリガー |
| 英語 docs 第 1 弾（README/Getting Started/主要 example 10 本） | 両方 | M | 並行トラック |
| ビルド高速化 pass 1（cli 側・目標 p50 ≤1.5s） | 両方 | M | metaphor-cli 側 Issue |

### Phase 2「生きているスケッチ」

目標: 体感の編集→反映 ≈ 0（状態がリロードを生存する）。人間のスライダーと AI の MCP が同一パラメータを共同操作するデモが撮れる。

| 機能 | 対象 | 規模 | 備考 |
|---|---|---|---|
| **Parameter Store（フラッグシップ）** | 両方 | L | 詳細は [live-tooling-params.md](live-tooling-params.md)。#87 を吸収、#273/#275 は同じ schema 変更に同乗 |
| 状態保持リロード（saveState/restoreState） | 両方 | M | [#451](https://github.com/shinyaoguri/metaphor/issues/451) + [cli#105](https://github.com/shinyaoguri/metaphor-cli/issues/105)（**完了**・契約点 8 新設。[live-viewer.md](live-viewer.md) §A-3 をファイルベースへ改訂） |
| loadShader()/shader() の 2D 対応 + シェーダファイル監視ホットリロード | Processing | L | Canvas2D パイプライン状態リファクタ [#646](https://github.com/shinyaoguri/metaphor/issues/646)・loadShader/shader/resetShader [#647](https://github.com/shinyaoguri/metaphor/issues/647)・ファイル監視リロード [#648](https://github.com/shinyaoguri/metaphor/issues/648) とも**完了**（Epic クローズ済み） |
| フォントファイル読込（CTFontManager）+ textToPoints | Processing | M | 生成タイポグラフィの解放 |
| SVG 読み込み（loadShape → MShape） | Processing | M | Phase 1 の SVG 書き出しと対になる |
| canvas 全体 filter()/blend() | Processing | S–M | 既存 postFX の配線替えが主 |
| drawInstanced(mesh, transforms) 公開 API | Unity | M | InstanceData3D は内部実装済み |
| ゲームパッド（GCController） | 両方 | S | |
| Canvas3D.swift 分割（リファクタ） | — | M | Phase 3 の門番。[#439](https://github.com/shinyaoguri/metaphor/issues/439)（**完了**） |
| 英語 docs 第 2 弾（公開 API doc コメント） | 両方 | M | cli #86（api_reference 強化）と相乗 |

### Phase 3「AI が届く絵の天井」（旧称「エディタ税なしのモダン 3D」・2026-08-15 に目的を再定義）

目標: **AI エージェントが Three.js で作る事例と同等の「ハイクオリティな絵」に、metaphor 上の AI が到達できる**。具体判定は従来どおり — glTF サンプル（DamagedHelmet 等）が参照ビューア相当で描画される。実装項目は再定義の前後で不変（決定 7）。「対象: Unity」の表記は移行者ペルソナの名残として残すが、取捨の基準は「Unity にあるか」ではなく「AI のハイクオリティ制作に要るか」。

| 機能 | 対象 | 規模 | 備考 |
|---|---|---|---|
| UV 全域対応（beginShape3D 頂点 UV + DynamicMesh UV） | 両方 | M | テクスチャ系すべての前提 |
| PBR テクスチャマップ（normal/roughness/metallic/AO） | Unity | L | 信頼性の分水嶺。UV + Canvas3D 分割に依存 |
| キューブマップ/スカイボックス + IBL + HDR/トーンマッピング | Unity | L | 単一レンダーターゲットで実現可（MRT 不要） |
| **glTF/GLB import（フラッグシップ）** | Unity | M–L | ジオメトリ + PBR マテリアル + ノード階層 → SceneGraph。skins/animations は対象外 |
| SceneGraph 軽量コンポーネント + GetComponent 風 lookup | Unity | M | Node に加算的 |
| ピッキング/レイキャスト（マウス → Node） | Unity+AI | M | AI も Probe 経由で「(x,y) に何があるか」を特定可能に |
| ライブビューアのノードインスペクタ（Parameter Store × ピッキング） | Unity | M | 編集機構は Parameter Store をそのまま使う |
| website（#74）英語ファースト | 両方 | — | 既存 Issue |

### Phase 4（需要ゲート — コミットしない）

需要シグナル（ユーザー要望・作品制作での具体的必要・**AI 制作実験で実際に詰まったこと** — 2026-08-15 追加）が出たときのみ着手する。スケルタルアニメーション・3D 物理はこのゲートの典型対象: 「AI にゲームを作らせたら物理が無くて詰んだ」が出た時点で Jolt 等のラップを起票する（先回りで自作しない — 決定 6 と同じ規律）。

- 3D 物理: Jolt 等のラップによる optional モジュール（**自作はしない**）
- 音声合成 minimal（AVAudioSourceNode ベースの p5.sound-lite）
- PDF 書き出し（SVG バックエンドの再利用）
- WebSocket/HTTP モジュール
- 接続層（2026-08-07 追記）: DMX/Art-Net・NDI 出力・シリアル（Arduino）・深度センサ/マルチタッチ入力・音声入出力デバイス選択と多チャンネル出力。出力系は `MetaphorOutputRegistry`、入力系は Tier 1 モジュール構造が受け皿で、コアに手を入れず optional モジュールで追加できる

### 作品トラック（フェーズ横断・2026-08-07 追加）

パリティのフェーズと並行して走る検証トラック（英語 docs トラックと同格）。目標: **「複数シーン + 複数入力 + 30 分無人稼働」を満たすリファレンス作品を metaphor-sketches で 1 本作り切り、その実需で構造層・現場層の設計を確定する**。背景は「レビュー所見の追補（2026-08-07）」を参照。

| Epic | 内容 | ゲート |
|---|---|---|
| [#414](https://github.com/shinyaoguri/metaphor/issues/414) J: 作品駆動検証（リファレンス作品） | 作品を 1 本作り切り、踏んだ穴を都度 Issue 化。v1.0 昇格条件「実運用検証を通過」の具体化を兼ねる | **1 本目 `0815-strata` / 2 本目 `0815-salvage` 完走（2026-08-15）**。下記「J の所見」 |
| [#415](https://github.com/shinyaoguri/metaphor/issues/415) K: 構造化支援の最小セット | Scene プロトコル + 遷移 / cue リスト / `after()`/`every()`。既存 tween/easing の上に薄く載せる | 子 Issue は J の所見後に起票（Phase 2.5 相当）。1 本目の所見は出た |
| [#416](https://github.com/shinyaoguri/metaphor/issues/416) L: 現場運用束 | マルチディスプレイ配置（NSScreen 指定）・キオスク（常時最前面/スリープ抑止/自動復帰）・自己監視の公開 API（#273 吸収）・GPU エラー検知 | 優先度は J の運用要件で確定。単体アプリ常設をやると決めるまで着手しない |

#### J の所見: 1 本目 `0815-strata`（2026-08-15）

metaphor-sketches の [`2026/0815-strata`](https://github.com/shinyaoguri/metaphor-sketches/tree/main/2026/0815-strata) を作り切った。
生成的地形（3D PBR × 時間変容）を 4 シーン（`formation` / `erosion` / `strata` / `dormant`）で巡回させ、
入力はカメラ（動き量・輝度）と OSC（シーン指定・パラメータ書き込み）の 2 系統、
出力は単体アプリ常設と Syphon 送出の両対応。要件（複数シーン + 複数入力 + 30 分無人稼働）は全て満たした。

**踏んだ穴と起票**（作品側で握り潰さず、回避策にコメントを残したうえで Issue 化した）:

| 層 | 事象 | Issue |
|---|---|---|
| ポスト | `VignetteEffect` の `intensity` が「強度」ではなく「黒に落ちきる半径」で意味が逆。既定値のままで画面の大半が黒くなる | [#684](https://github.com/shinyaoguri/metaphor/issues/684) |
| 入力 | `CaptureDevice` が権限 `notDetermined` でも `isAvailable=true` を返し、フレーム 0 のまま無言で失敗する | [#685](https://github.com/shinyaoguri/metaphor/issues/685) |
| 3D | `DynamicMesh` に in-place 更新が無く、毎フレーム頂点・インデックス両方のバッファを確保し直す | [#686](https://github.com/shinyaoguri/metaphor/issues/686) |
| 3D | `directionalLight` / `pointLight` に intensity が無く、PBR 単灯だと `albedo/π` で沈む | [#687](https://github.com/shinyaoguri/metaphor/issues/687) |
| 契約 | `.app` 起動では cwd が `/` になり `.metaphor/`（Probe / Parameter Store）が壊れる | [#688](https://github.com/shinyaoguri/metaphor/issues/688) / [cli#133](https://github.com/shinyaoguri/metaphor-cli/issues/133) |

既存の検討 Issue には実測を書き戻した: [#573](https://github.com/shinyaoguri/metaphor/issues/573)（App bundle）へは
「**配布以前に、カメラ・マイクを使う作品は `swift run` では完成させられない**」（TCC ダイアログは
`Info.plist` を持つバンドルにしか出ない）と、手で `.app` を組むのに必要だった 6 工程。
[#571](https://github.com/shinyaoguri/metaphor/issues/571)（Scene の寿命境界）へは
「この作品ではリソースも購読も全シーン共有で、**寿命境界は要らず、欲しかったのは
値の束の補間と保持時間つき巡回**だった」という反証寄りの所見。

**K（#415）への含意**: 手書きしたのは `SceneProfile`（25 フィールド）+ 手動の線形補間 30 行 +
`SceneDirector` 70 行。**一番効くのは補間の自動化**で、寿命管理ではない。
外部指定（OSC）と自律タイマーの共存規約も自前で決める必要があった。

**L（#416）への含意**: 単体アプリ常設を選ぶと `.app` 化が必須になり、そこは #573 とほぼ同じ問題に着地する。
自己監視 API の不在は実際に効いた — 30 分の劣化計測は **Probe を外から叩いて** 行うしかなく、
作品自身が fps / メモリを読んで degrade することはできない。一方でマルチディスプレイ・
キオスク（最前面・スリープ抑止）は今回の 1 本では実需として出ていない（常設の現場に置いていないため）。

**2 本目の切り口**: 今回は「1 つの絵をパラメータで変容させ続ける」型だったため、シーンが
リソースを持たなかった。シーンごとにアセット（動画・音・モデル）が入れ替わる型を試すと
#571 の寿命境界の要否が判定できる。

**2 本目は「AI 単独制作実験」を兼ねる**（2026-08-15 追加・決定 7）: AI エージェントに
（人間の介入を最小にして）ゲームまたは 3DCG シミュレーションを 1 本作らせ、詰まった箇所 —
書けなかったイディオム・表現力の欠落（PBR maps / IBL / glTF の不在がどこで効くか）・
観測ループの穴（#563 入力リプレイ / #564 視覚検証の要否）・スケルタルアニメと 3D 物理の実需 —
をすべて Issue 化する。1 本目 `0815-strata` の方法論（作品側で握り潰さず起票する）の再利用。
これにより G2/G3/G4・#563/#564・物理/アニメの優先順位が抽象論でなく実測で決まる。
「シーンがリソースを持つ型」（#571 判定）と兼ねられるかは実験設計時に判断する。

#### J の所見: 2 本目 `0815-salvage`（2026-08-15・AI 単独制作実験）

metaphor-sketches の [`2026/0815-salvage`](https://github.com/shinyaoguri/metaphor-sketches/tree/main/2026/0815-salvage) を作り切った。
**3 ステージの 3D ゲーム**（`title` → `hull` → `reactor` → `vent` → `result`）で、
ステージごとに**モデル・床テクスチャ・環境音・背景動画が丸ごと入れ替わる**。
2 本目の 2 つの目的（#571 の寿命境界判定 / AI 単独制作実験）を 1 本で兼ねた。

制作は企画から検証・記録まで AI（Claude Code）が行い、**題材も実装方針も人間に確認していない**。
絵の確認も人間の目視ではなく、AI が Probe のスナップショットを読んで判断した。
アセット（`.obj` / `.png` / `.wav` / `.mp4`）は依存を足さずに `scripts/gen-assets.py` で決定論的に生成している。

**踏んだ穴と起票**:

| 層 | 事象 | Issue |
|---|---|---|
| 3D | IBL が無いため `metallic` を上げると拡散が消え、埋める環境光が無く灰色に潰れる。**スカラーの metallic が 0.2 超で死に機能** | [#293](https://github.com/shinyaoguri/metaphor/issues/293) へ実需（G3 > G2 の一票）→ G3a [#706](https://github.com/shinyaoguri/metaphor/issues/706) / G3b [#710](https://github.com/shinyaoguri/metaphor/issues/710) で解消 |
| 3D | `emissive` / `specular` に 0..255 の 3 引数版が無く `fill` と書き味が揃わない | [#700](https://github.com/shinyaoguri/metaphor/issues/700) |
| 映像 | `VideoPlayer` / `CaptureDevice` を 3D のテクスチャとして貼れない（`texture()` が `MImage` 限定）。2D の書き割りで回避 | [#701](https://github.com/shinyaoguri/metaphor/issues/701) |
| 並行性 | `Sketch` の外にアセットを持つ型は `@MainActor` が要る（最初のビルドのエラーが全部これ）。文書に無い | [#702](https://github.com/shinyaoguri/metaphor/issues/702) |

既存の検討 Issue への書き戻し: [#563](https://github.com/shinyaoguri/metaphor/issues/563) へは
「**ゲームでは状態への到達手段が無いのが一番効く**」（作品側に `SALVAGE_START` と自動操縦を自作した）、
[#564](https://github.com/shinyaoguri/metaphor/issues/564) へは
「`contentFraction` / `meanLuminance` で**壊れている**は弾けるが、**作品として成立していない**は画像を読むまで分からない」。

**30 分無人稼働（`cache: false`・自動操縦）**: 178 サンプル・Probe timeout 0 件で
fps 59.8 維持（前半 → 後半で ±0.0）、**47 周・238 シーン遷移・485 ロード / 477 解放**、
`assetsLive` は 5〜9 の間で振動し周回とともに増えない（解放は効いている）。
メモリは 30 分で +15.6MB（mean 464.8MB）。ただし **4〜5 分おきに +160MB のスパイク**が
10〜20 秒出て戻る挙動があり（`frameTimeMs.max` も 40〜67ms へ伸びる）、1 本目では出ていない。原因は未特定。
対照として `cache: true`（ライブラリのキャッシュ）で 7 分回すと mean 432.1MB・スパイクなし・
ロード 9.5ms（`cache: false` は 15.7ms）で、**キャッシュを使うほうが安定する**。
つまり現状は「キャッシュか寿命境界か」の二択で、**シーンのスコープでキャッシュする中間が無い**。

**#571（Scene = 寿命境界）の判定**: 1 本目の反証寄りの所見に対し、2 本目は**要る側**の材料が出た。
ただし欲しいのは Scene プロトコルではなく、その下の 3 つ（詳細は #571 のコメント）:
(1) `SoundFile` / `VideoPlayer` は参照を捨てても止まらず明示的な `stop()` が要る、
(2) `loadModel` / `loadImage` の `cache: true` 既定が寿命境界と衝突する（この作品は `cache: false` を
選べたから成立した）、(3)「いま何が生きているか」を答える経路が無い（作品側で台帳を書いて Probe に出した）。
Scene プロトコル自体は作品側で 130 行、しかも描画 API が `Sketch` 拡張である以上
ライブラリ版は `func draw(_ s: any Sketch)` を強いて書き味を損なうため、ライブラリには要らないと判断した。

**AI 制作能力（決定 7）への含意**: 詰まりの内訳は
**表現力の天井（G3 IBL）が 1 件・アセット経路が 1 件・API の書き味が 1 件・文書が 1 件**で、
実行・観測ループ（Probe / 決定論 / MCP）は 2 本目でも破綻しなかった。決定 7 のギャップ分解と整合する。
スケルタルアニメと 3D 物理は**実需が出ていない**（当たり判定は球の距離だけで足りた）ため、
Phase 4 の需要ゲートは開かない。

## 非目標

- クロスプラットフォーム（Windows/Linux/iOS/web）— macOS 14+/Apple Silicon の契約は維持
- スケルタルアニメーション/スキニング（glTF import も skins を読まない。AI 制作実験で実需が出たときのみ再評価 — 決定 7）
- フルゲームエンジン・エディタアプリ化（シーンシリアライズ形式・prefab・Play/Edit 分離は作らない。インスペクタはビューアの付帯機能）
- 物理エンジンの自作
- MRT / deferred rendering（forward 維持）
- ジョブシステム / マルチスレッド化（`@MainActor` 隔離は維持）
- シェーダグラフ / ビジュアルノードエディタ
- ショーコントロール GUI / タイムラインエディタ（構造化支援は Epic K のコード API 最小セットまで）
- ADR の全訳・アセットストア的 GUI

## Epic 構成

Epic はテーマ別（フェーズ跨ぎ可）。子 Issue は「S は同一レイヤ束で 1 Issue + チェックリスト、M/L は各 1 Issue、リファクタ前提は blocking リンク付き独立 Issue」。**起票は着手フェーズ分のみ**（現時点: Epic 全 9 本 + Phase 1 の子のみ。後続フェーズの子は着手時に起票して本表へ追記する）。

| Epic | 内容 | 子（Phase 1 起票分は Issue 番号を記載） |
|---|---|---|
| [#287](https://github.com/shinyaoguri/metaphor/issues/287) A: Processing API パリティ第 1 弾 | Phase 1 の S 束 | **全完了・クローズ済み**: A1 データ IO #278 / A2 Vec 拡張 #279 / A3 キャンバス操作束 #280 / A4 ダイアログ+drop #281 / A5 MSAA #282 / A6 OSC 送信 #283 / A7 アセットキャッシュ #284 |
| [#288](https://github.com/shinyaoguri/metaphor/issues/288) B: ベクタ往復 | SVG/PDF | B1 SVG 書き出し #285（**完了**・方式は API フックに改訂）/ B2 loadShape（Phase 2）/ B3 PDF（Phase 4） |
| [#289](https://github.com/shinyaoguri/metaphor/issues/289) C: 往復レイテンシ（クロスリポ） | ビルド高速化 + 状態運搬 | C1 ビルド高速化 pass 1（[cli#88](https://github.com/shinyaoguri/metaphor-cli/issues/88)・**完了**）/ C2 saveState/restoreState [#451](https://github.com/shinyaoguri/metaphor/issues/451)（**完了**）/ C3 watch 側状態運搬（[cli#105](https://github.com/shinyaoguri/metaphor-cli/issues/105)・**完了**）/ C4 計測分解（**完了**） |
| [#290](https://github.com/shinyaoguri/metaphor/issues/290) D: Parameter Store & AI 共同操作 | Phase 2 フラッグシップ | D1 store コア / D2 ParameterGUI 再基盤 / D3 probe schema 拡張 / D4 MCP 書込チャネル（cli）/ D5 リロード永続 [#451](https://github.com/shinyaoguri/metaphor/issues/451)（**完了**）/ D6 ノードインスペクタ（Phase 3） |
| [#291](https://github.com/shinyaoguri/metaphor/issues/291) E: 2D シェーダ | loadShader/shader | E1 Canvas2D パイプラインリファクタ [#646](https://github.com/shinyaoguri/metaphor/issues/646)（**完了**）/ E2 loadShader API [#647](https://github.com/shinyaoguri/metaphor/issues/647)（**完了**）/ E3 ファイル監視リロード [#648](https://github.com/shinyaoguri/metaphor/issues/648)（**完了**） |
| [#292](https://github.com/shinyaoguri/metaphor/issues/292) F: タイポグラフィ | フォント/アウトライン | F1 フォントファイル読込 [#649](https://github.com/shinyaoguri/metaphor/issues/649) / F2 textToPoints [#650](https://github.com/shinyaoguri/metaphor/issues/650) / F3 text-on-path（stretch）[#651](https://github.com/shinyaoguri/metaphor/issues/651) |
| [#293](https://github.com/shinyaoguri/metaphor/issues/293) G: モダン 3D | PBR/glTF/IBL | G0 Canvas3D 分割 #439（**完了**）/ G1 UV #433・#435（**完了**）/ G2 PBR maps / G3a トーンマッピング [#706](https://github.com/shinyaoguri/metaphor/issues/706)（**完了**）/ G3b skybox・IBL [#710](https://github.com/shinyaoguri/metaphor/issues/710)（**完了**）/ G4 glTF / G5 drawInstanced |
| [#294](https://github.com/shinyaoguri/metaphor/issues/294) H: SceneGraph インタラクティビティ | コンポーネント/ピッキング | H1 コンポーネント / H2 ピッキング / H3 インスペクタ（= D6） |
| [#295](https://github.com/shinyaoguri/metaphor/issues/295) I: 英語 & website | 国際化 | **クローズ済み**（2026-08-16・I2 / I3 を移管して役目を終えた）: I1 README/GS 英語化 #286（**完了**・境界は [docs/README.md](../README.md) に明記）/ I2 API doc コメント [#334](https://github.com/shinyaoguri/metaphor/issues/334)（**Epic #314 の W3-1 が管轄**）/ I3 website（i18n 構成は #487・#491 で導入済み。残る LP 英語文言の見直しは [#740](https://github.com/shinyaoguri/metaphor/issues/740)） |
| [#414](https://github.com/shinyaoguri/metaphor/issues/414) J: 作品駆動検証 | 作品トラックのリファレンス作品 | 作品本体は metaphor-sketches 側。**1 本目 `0815-strata` / 2 本目 `0815-salvage`（AI 単独制作実験）完走**（所見は「J の所見」節、起票は #684〜#688 / cli#133 / #700〜#702） |
| [#415](https://github.com/shinyaoguri/metaphor/issues/415) K: 構造化支援 | Scene 遷移 / cue / スケジューラ | 子 Issue は J の所見後に起票。1 本目の所見では**補間の自動化**が最優先 |
| [#416](https://github.com/shinyaoguri/metaphor/issues/416) L: 現場運用束 | マルチディスプレイ / キオスク / 自己監視 | #273 を吸収。着手は常設判断とセット。1 本目では**自己監視の不在**のみ実需として確認 |

既存 Issue との関係: #268（バルク頂点 API）は Epic A/G から参照（重複起票しない）。#87 は Epic D が吸収。#275 は Epic D の schema 変更に同乗。#273 は Epic L が吸収（2026-08-07 変更。Probe schema に触れる部分のみ Epic D の schema 変更に同乗）。cli #86 は API doc コメント英語化 #334（Epic #314 の W3-1）と相乗。

## 実装の進め方（将来セッションへの指示）

1. **一気に実装しない。** 実装は起票された Issue を単位に、小さく作って早めに PR（1 PR = 1 関心事）。使いながら直す前提で、フェーズ完了ごとに本ドキュメントを見直して更新する（優先度変更・追加ギャップ・Issue 番号の追記）
2. **サブエージェント委譲方針**（パフォーマンス最大化 × トークンコスト最適化）:
   - 設計判断・API 設計・レンダリング/契約（CONTRACT.md）に触れる実装・レビュー = 最高性能モデル（本体または高性能サブエージェント）
   - 定型・機械的作業（3 層転送のボイラープレート展開・example 移植・docs 翻訳・テスト雛形・生成物再生成）= 安価なモデルのサブエージェントへ委譲
   - 独立した子 Issue は worktree 分離の並列サブエージェントで同時進行してよい。迷ったら高性能側に倒す
3. **契約に触れる項目**（Epic C/D の一部）は metaphor-cli と同時更新・両リポ `CONTRACT.md` 整合・`./scripts/check-contract.sh` green が必須（[CONTRACT.md](../../CONTRACT.md) 参照）
4. 各フェーズの目標指標（Phase 1: p5 例 50 本移植性 / Phase 2: 状態生存 + 共同操作デモ / Phase 3: glTF 描画品質）を完了判定に使う
