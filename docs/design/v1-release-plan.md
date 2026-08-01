# v1.0.0 リリース準備計画(readiness review)

- **ステータス**: 叩き台(レビュー所見は確定・準備トラックの優先順位と未決事項はユーザー判断待ち)
- **作成**: 2026-08-01(v0.8.0 リリース直後の 4 観点並列レビューに基づく)
- **正典**: 本ドキュメント + 起票される各 Issue。ロードマップ本体は [roadmap-processing-unity.md](roadmap-processing-unity.md)(機能面)、本ドキュメントは安定性・品質・体制面を扱う
- **レビュー方法**: ①公開 API 表面と安定性 ②テスト・CI・品質保証 ③ドキュメント・オンボーディング ④配布・依存・OSS 開発体制、の 4 観点を独立に調査し統合

## v1.0.0 が約束すること(前提の確認)

v1.0.0 は機能の節目ではなく **SemVer 上の契約宣言**である。タグを切った瞬間から:

1. **ソース互換の凍結** — public API の breaking change には major bump が必要になる(ABI 安定は宣言しない。SwiftPM ソース配布のため)
2. **過去タグの永続性** — `from: "1.0.0"` を書いた利用者のため、タグと Release asset(Syphon.xcframework.zip)は恒久的に resolve 可能であり続ける義務を負う
3. **変更の説明責任** — 何が変わり、何が壊れたかを利用者が追跡できる経路(CHANGELOG・リリースノート)が必要になる

したがって v1.0 の準備とは「機能を足すこと」ではなく、**(a) 凍結してよい API 面に整えること、(b) 凍結を守り続けられる品質ゲートと体制を作ること** である。

## 所見サマリ

### 強み(v1.0 に向けて既に高水準のもの)

- テスト 1,130 本・XCTest ゼロ(Swift Testing 統一)・`.disabled`/`withKnownIssue` ゼロ・warnings-as-errors
- 契約検証 4 層(トークン grep / JSON Schema / byte-identity / 自動 pin bump)と生成物鮮度検証(pre-push + CI 二重)
- リリース完全自動化(ラベル駆動・タグ前 example smoke ゲート・merge SHA 明示タグでレース回避)
- 外部 SwiftPM 依存ゼロ(利用者の resolve が速く供給網が小さい)
- ADR による設計判断の記録。deprecation ポリシーが ADR-0005 Amendment に成文化済み
- doc コメント密度(`///` 9,597 行 / public 宣言 2,288)、DocC サイトのビルド・デプロイ稼働済み
- `docs/README.md` の読者別導線設計、`docs/ai/` 一式は既に英語

### ギャップ一覧(優先度順)

| # | 領域 | ギャップ | 深刻度 |
|---|---|---|---|
| G1 | API | ADR 自身が「1.0 前の破壊的変更ウィンドウ」に置いた作業が未着手(下記 A 節) | **高** |
| G2 | API | Swift 6 strict concurrency 完全未着手(`@preconcurrency import` 29 件、Package.swift/CI に設定ゼロ)。1.0 後にやると major 相当のソース互換リスク | **高** |
| G3 | API | 命名 3 系統混在(`no*` / `enable*`+`disable*` / `set*`+`clear*`)、記録 API のプレフィックス揺れ(`beginSVG` だけ `Record` なし)、二層で別名(`screenX` vs `screenPosition`) | **高** |
| G4 | 法務 | Syphon(Simplified BSD)のバイナリ再頒布に対するライセンス表記が皆無 | **高** |
| G5 | CI | GPU 不在時に 500+ テストがサイレント skip しても CI green(skip の可視化・アサートなし) | **高** |
| G6 | CI | ゴールデンイメージ回帰なし。#70 の決定論保証が中心 1 ピクセル比較にしか使われていない | **高** |
| G7 | テスト | 公開 API の中心 `Sources/MetaphorCore/Sketch/`(6,753 LOC)がテスト密度最薄(≈10 tests/kLOC、他の 1/5) | **高** |
| G8 | 配布 | タグ保護 ruleset なし・Release asset 保持ポリシー未文書・v0.2.2 は asset 欠損済み(v0.2.1 の asset に間借り) | **高** |
| G9 | i18n | 公開 API doc コメントの 75% が日本語(中核 API ほど日本語)。連動して `llms.txt` も 69% 日本語 | **高** |
| G10 | docs | DocC サイト(公開済み)への README リンクが 0 本 / `README.en.md` がリリース自動バンプ対象外で既に 1 版古い | **高** |
| G11 | docs | CHANGELOG.md 不在(リリースノートは PR タイトル自動羅列のみ)/ SemVer・API 安定性ポリシーの文書ゼロ | **高** |
| G12 | 体制 | CONTRIBUTING / SECURITY.md / Issue・PR テンプレート不在 | **高** |
| G13 | docs | TCC(マイク・カメラ)権限の説明が皆無(該当 example 3 本以上)/ Processing 移行ガイド未成果物化 | **高** |
| G14 | API | typed throws 0 件(ADR-0005 Decision 2「生成系 = typed throws」と実装が乖離)/ `GPUBuffer` subscript・`NoiseTexture` stops がユーザー入力でトラップ | 中 |
| G15 | API | deprecated 7 件が削除条件(deprecation を含む minor 公開済み)を満たしたまま残存。うち 2 件は protocol requirement | 中 |
| G16 | API | `@_exported import Metal/MetalKit/simd` が利用者名前空間に注入(凍結すると剥がせない)/ `_metaphorSyphonRegister()` が public 表面に露出 | 中 |
| G17 | CI | テスト実行が macOS 26 の 1 環境のみ(最小サポート macOS 14/Swift 5.10 はビルドのみ・非必須チェック) | 中 |
| G18 | CI | Examples 278 本中、定常検証は 19 本(6.8%)。全数スイープは手動のみ / カバレッジは印字のみでゲート・可視化なし / lint・format 未導入 | 中 |
| G19 | 契約 | stdin JSON Lines プロトコルにバージョン番号なし / `performance` 節を schemaVersion 据え置きで追加した先例(フリーズ点が曖昧) | 中 |
| G20 | 配布 | dependabot が github-actions のみ(website/ の npm、Syphon gitsubmodule が未監視)/ Syphon checksum が毎リリース変わる(非再現ビルド) | 中 |
| G21 | 体制 | bus factor = 1(コミッター1名・リリースが個人 PAT と admin bypass に依存)/ `release:*` ラベル説明が現行運用と不一致 | 中〜低 |

## A. 破壊的変更ウィンドウの完遂(v1.0 最大の論点)

ADR は既に「1.0 前にやる」と自ら宣言した項目を持つ。**v1.0 を切ることはこのウィンドウを自分で閉じることを意味する**ため、未着手項目の実施 or 明示的な見送り判断が v1.0 の前提条件になる:

| 項目 | 出典 | 状態 |
|---|---|---|
| 変換ファミリ(`translate`/`rotate`/`scale`)の P3D 意味論統一 | ADR-0005 | 未着手(2D/3D 非対称のまま) |
| `loadPixels()` のメインキャンバス Processing 互換 readback | ADR-0005 | follow-up のまま |
| コマンド記録の既定 ON 化(影オフ時の opt-in 撤廃) | ADR-0003 | 「安定後に判断」のまま |
| 生成系 API の typed throws 化 | ADR-0005 Decision 2 | 実装 0 件(untyped `throws` 52 件) |
| deprecated 7 件の削除 | ADR-0005 Amendment | 削除可能条件を満たして残存 |
| 命名統一(G3)・二層 API 名の整合 | (新規、本レビューで顕在化) | 未整理 |
| Swift 6 strict concurrency 対応(G2) | (新規) | 未着手 |
| `@_exported import Metal/MetalKit/simd` の扱い決定(G16) | (新規) | 未判断 |
| `GPUBuffer` subscript / `NoiseTexture` stops の failure mode 統一(G14) | (新規) | 不統一のまま |

**特に G2(Swift 6)は工数・波及とも最大**。strict concurrency 対応は `Sendable` 準拠追加・クロージャの `@Sendable` 化を伴い、公開 API のソース互換を壊しうる。0.x のうちに済ませるか、少なくとも「Swift 6 language mode で警告ゼロ」を v1.0 のゲートにすべきである。

## B. 品質ゲートの補強(凍結を守り続ける仕組み)

1. **GPU skip の可視化(G5)** — CI に `isGPUAvailable` の明示アサート、または skip 件数レポートを追加。ランナー変更で Metal が消えても現状は誰も気付かない
2. **ゴールデンイメージ回帰(G6)** — 決定論レンダリング(#70)+ 既存の `RenderTestHelper` 読み戻しを全フレームハッシュ比較に拡張するだけで基盤が成立する。レンダリングライブラリの 1.0 として、シェーダ/パイプライン変更の見た目退行を検出する最重要ゲート
3. **`Sketch/` のテスト増強(G7)** — 凍結対象の中心が最薄という逆転の解消
4. **v1.0 タグ前の Examples 全数スイープ(G18)** — `examples-sweep.yml` の `full=true` を一度 green にすることを 1.0 のリリース条件に含める
5. **最小サポート環境でのテスト実行(G17)** — macos-14 ジョブをビルドのみ→テストありへ(Swift Testing が 5.10 に無い制約があるため、実現方法は要検討。少なくとも `build-swift-5-10` の必須チェック昇格)
6. カバレッジのモジュール別可視化、`ci.yml` への `timeout-minutes`、壁時計アサーション(`ObservabilityOverheadTests`)の #149 基準での隔離

## C. 「他の人が使える」ためのドキュメント・国際化

1. **クイックウィン(即日)**: README(日英)に DocC サイトへのリンク追加 / `README.en.md` を `release.yml` の sed と `validate-ai-docs.sh` の**両方**に追加(片方だけだと相互デッドロック)
2. **API doc コメント英語化(G9)** — Epic #295 第 2 弾。最大工数だが `llms.txt` は生成物なので自動追随する(= AI 向け正典も同時に英語化される)。中核 API(`circle`/`rect`/`fill`)ほど日本語という現状の逆転を優先的に解消
3. **Processing 移行ガイド** — `.pde` 同梱・同名階層という他にない資産を「Processing の X は metaphor では Y」の対応表 + 落とし穴集として成果物化
4. **TCC 権限ドキュメント(G13)** — マイク・カメラ利用時の権限、失敗時の復旧手順。該当 example を動かした初見者が黙って詰む現状の解消
5. **CHANGELOG.md の新設(G11)** — v1.0 以降の破壊的変更追跡の枠組みを 0.x のうちに開始。リリースノートに人間向けハイライト枠を追加
6. `docs/README.md`(読者別導線の入口)の英語化、利用者向け Troubleshooting 拡充(Intel Mac/Metal・SwiftPM 解決失敗)、Examples の「順に学ぶ」推奨順路ページ

## D. 配布・法務・OSS 体制

1. **Syphon ライセンス表記(G4・即日)** — `THIRD_PARTY_LICENSES.md`(または NOTICE)に Simplified BSD の著作権表示とライセンス全文を同梱。バイナリ再頒布中の現状はリポジトリ内で最も明確な法務ギャップ
2. **SECURITY.md(即日)** — 脆弱性の非公開報告経路(GitHub Private vulnerability reporting の有効化含む)
3. **タグ保護 + asset 保持ポリシー(G8)** — `refs/tags/v*` への deletion/update 禁止 ruleset。releasing.md に「Release asset は削除しない」を明文化。全タグの binaryTarget URL が 200 を返す定期チェック(v0.2.2 型の事故の検知)
4. **CONTRIBUTING.md / Issue・PR テンプレート(G12)** — 内容の 8 割は DEVELOPMENT.md と README「フィードバック / Issue 報告」節に既存。外部向け入口として成形するだけ
5. **API 安定性ポリシーの成文化(G11)** — 「何が public API か(4 層のうちどこまで約束するか)」「deprecation は何 minor 保持するか」「Probe wire schema・stdin プロトコル・環境変数は SemVer のどこに載るか」「ABI 非保証(ソース互換のみ)」を 1 ページに
6. **契約のフリーズ点明記(G19)** — v1.0 時点の `frame.json` v4 全キーをフリーズ点として CONTRACT.md に明記。stdin プロトコルに互換規約(未知の `t` の扱い)を定義
7. dependabot に npm(`/website`)と gitsubmodule を追加 / `release:*` ラベル説明の修正 / Syphon zip の再利用(submodule pin 不変なら checksum 固定)検討
8. **bus factor = 1 のリスク開示** — 技術では解けない。README への現状明記(単独メンテ・ベストエフォート)か、バックアップメンテナ確保かの判断

## 準備トラック計画(案)

機能ロードマップ(Phase 2〜)と**直交する readiness トラック**として進める。R0〜R2 は Phase 2 と並行可能。

| トラック | 内容 | 規模感 |
|---|---|---|
| **R0: クイックウィン** | G4 ライセンス表記 / SECURITY.md / タグ保護 / README.en 自動バンプ修正 / DocC リンク / dependabot 追加 / timeout-minutes / ラベル説明修正 / CONTRIBUTING + テンプレート | 各 S、合計数日 |
| **R1: 破壊的変更ウィンドウ完遂** | A 節の全項目。命名統一 → deprecated 削除 → typed throws → P3D 意味論 → Swift 6 strict concurrency の順(依存が薄い順) | L(Swift 6 が支配的) |
| **R2: 品質ゲート** | GPU skip 可視化 → ゴールデンイメージ回帰 → Sketch/ テスト増強 → カバレッジ可視化 → 最小環境テスト | M〜L |
| **R3: ドキュメント・英語化** | API doc コメント英語化(Epic #295 I2)→ 移行ガイド → TCC → CHANGELOG 開始 → Troubleshooting | L(英語化が支配的) |
| **R4: ポリシー成文化** | API 安定性ポリシー / 契約フリーズ点 / asset 保持ポリシー / リリースノート様式 | S〜M |
| **RC: リリース候補** | Examples 全数スイープ green → `1.0.0-rc.1`(prerelease dispatch は実装済み)→ 実運用検証(metaphor-sketches)→ v1.0.0 | M |

## 未決事項(ユーザー判断)

1. **v1.0 のタイミング**: Phase 2(Parameter Store)完了後を推奨。Parameter Store は公開 API と wire 契約(schemaVersion)の両方に大きく触れる予定であり、その前に凍結すると直後に major 相当の圧力がかかる。ただし「Phase 3(glTF/PBR)まで待つ」は additive なので不要
2. **凍結範囲**: 13 プロダクト全部を一括で 1.0 と宣言するか、モジュール別の成熟度(例: Core/umbrella = stable、MPS/RenderGraph = 成熟度表示つき)を README に明示するか。public 宣言 2,288・4 層重複面の一括凍結は面が広い
3. **Swift 6 対応の位置づけ**: v1.0 ブロッカーとするか(推奨: strict concurrency 警告ゼロを最低ライン)
4. **英語化の水準**: API doc コメント英語化(最大工数)を v1.0 ブロッカーにするか、v1.x で継続するか
5. **`@_exported import Metal/MetalKit/simd` の扱い**: 維持(公開シグネチャに MTLTexture/SIMD3 が頻出するため実質不可避)か、v1.0 前に剥がすか
6. **二層 API(Sketch グローバル / SketchContext)の名前不一致**(`screenX` vs `screenPosition` 等): どちらに寄せるか
7. **bus factor 開示の方法**: README への明記か、他の手段か

## 完了判定(v1.0 リリース条件のチェックリスト案)

- [ ] A 節の全項目が「実施済み」または「明示的に見送り判断済み(ADR 追記)」
- [ ] Swift 6 strict concurrency 警告ゼロ(または見送りの ADR)
- [ ] GPU skip 可視化 + ゴールデンイメージ回帰が CI で稼働
- [ ] Examples 278 本の全数スイープ green
- [ ] THIRD_PARTY_LICENSES / SECURITY / CONTRIBUTING / テンプレート / タグ保護が整備済み
- [ ] API 安定性ポリシー・契約フリーズ点・CHANGELOG が公開済み
- [ ] `1.0.0-rc.1` で metaphor-sketches の実運用検証を通過
- [ ] リリースノートに 0.x → 1.0 の人間向けハイライトと移行ガイド
