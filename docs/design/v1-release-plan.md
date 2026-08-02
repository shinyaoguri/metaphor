# v1.0.0 リリース準備計画(readiness review)

- **ステータス**: 運用中(living document)。レビュー所見は確定、実装計画は 2026-08-01 にユーザーと戦略合意済み(v0.9.x 育成方式・既知課題は v0.8.x で完遂)
- **作成**: 2026-08-01(v0.8.0 リリース直後の 4 観点並列レビューに基づく)
- **正典**: 本ドキュメント + 起票される各 Issue。ロードマップ本体は [roadmap-processing-unity.md](roadmap-processing-unity.md)(機能面)、本ドキュメントは安定性・品質・体制面を扱う
- **レビュー方法**: ①公開 API 表面と安定性 ②テスト・CI・品質保証 ③ドキュメント・オンボーディング ④配布・依存・OSS 開発体制、の 4 観点を独立に調査し統合

## バージョンマイルストーン(決定事項)

**戦略: v1.0.0 を目指しつつ、リリース直前のものを v0.9.x で育てる。** prerelease タグ(`1.0.0-rc`)は使わず、通常のラベル駆動リリースのまま 0.9 系を実質 RC 系列として運用する。

| 期間 | 位置づけ | 内容 |
|---|---|---|
| **v0.8.x(現在)** | 壊してよい最後の期間 | 本ドキュメントの既知課題(G1〜G21・A 節)を**すべてここで片付ける**。breaking change はこの期間に完遂。Phase 2 機能開発(Parameter Store 等)と並行 |
| **v0.9.0** | API 凍結宣言 | 入口条件 = A 節全項目が「実施 or 見送り ADR 化」済み + Phase 2 完了。以降 v1.0 と同じ規律で運用開始 |
| **v0.9.x** | 育成・実証期間 | 原則 additive と fix のみ。英語化の継続、実運用(metaphor-sketches)フィードバック。breaking が必要になったら「凍結にまだ早かった」シグナルとして扱う。**コミュニティ条件(下記)を満たすまで期間の上限は設けず、改良を継続する** |
| **v1.0.0** | 昇格 | 昇格条件(後述)= 技術条件 + コミュニティ条件(**GitHub スター 100 超**)を満たした最後の 0.9.x を実質そのまま 1.0.0 に(2026-08-02 決定) |

**凍結範囲(論点 2)の決着**: 0.9 系では全 13 モジュールを凍結扱いで運用してみて、0.9.x 中に「壊したくなった」モジュールが出た場合のみ v1.0 で preview 宣言(breaking は minor で可)に落とす。机上ではなく 0.9 の実績で線を引く。

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
| G14 | API | typed throws 0 件(ADR-0005 Decision 2「生成系 = typed throws」と実装が乖離。→ #323 でエラー型統一により代替、構文適用は 5.10 サポート終了まで延期)/ `GPUBuffer` subscript・`NoiseTexture` stops がユーザー入力でトラップ | 中 |
| G15 | API | deprecated 7 件が削除条件(deprecation を含む minor 公開済み)を満たしたまま残存。うち 2 件は protocol requirement | 中 |
| G16 | API | `@_exported import Metal/MetalKit/simd` が利用者名前空間に注入(凍結すると剥がせない)/ `_metaphorSyphonRegister()` が public 表面に露出 | 中 |
| G17 | CI | テスト実行が macOS 26 の 1 環境のみ(最小サポート macOS 14/Swift 5.10 はビルドのみ・非必須チェック) | 中 |
| G18 | CI | Examples 278 本中、定常検証は 19 本(6.8%)。全数スイープは手動のみ / カバレッジは印字のみでゲート・可視化なし / lint・format 未導入 | 中 |
| G19 | 契約 | stdin JSON Lines プロトコルにバージョン番号なし / `performance` 節を schemaVersion 据え置きで追加した先例(フリーズ点が曖昧) | 中 |
| G20 | 配布 | dependabot が github-actions のみ(website/ の npm、Syphon gitsubmodule が未監視)/ Syphon checksum が毎リリース変わる(非再現ビルド) | 中 |
| G21 | 体制 | bus factor = 1(コミッター1名)/ ~~リリースが個人 PAT と admin bypass に依存~~ **← 事実誤り**。`release.yml` / `release-on-merge.yml` は `GITHUB_TOKEN` のみで、ruleset も bypass しない(唯一の PAT `CLI_DISPATCH_TOKEN` は metaphor-cli への dispatch 専用・未設定なら skip)。個人アカウントに紐づくのは cli への dispatch と Homebrew tap への push 権限 / `release:*` ラベル説明が現行運用と不一致(W0-3 で解消済み) | 中〜低 |

## A. 破壊的変更ウィンドウの完遂(v1.0 最大の論点)

ADR は既に「1.0 前にやる」と自ら宣言した項目を持つ。**v1.0 を切ることはこのウィンドウを自分で閉じることを意味する**ため、未着手項目の実施 or 明示的な見送り判断が v1.0 の前提条件になる:

| 項目 | 出典 | 状態 |
|---|---|---|
| 変換ファミリ(`translate`/`rotate`/`scale`)の P3D 意味論統一 | ADR-0005 | **実施済み**(#325 / PR #384 / ADR-0005 Amendment 2026-08-02)。2D 変換 API が 3D にも効くようになった。逆方向は構造的に到達不能で残る(→ #387) |
| `loadPixels()` のメインキャンバス Processing 互換 readback | ADR-0005 | follow-up のまま |
| コマンド記録の既定 ON 化(影オフ時の opt-in 撤廃) | ADR-0003 | **見送り確定**(#327 / ADR-0003 Amendment 2026-08-02)。現行の「影オン=常時記録 / 影オフ=`METAPHOR_COMMAND_RECORD` opt-in」を 1.0 の確定仕様として凍結 |
| 生成系 API の typed throws 化 | ADR-0005 Decision 2 | **エラー型統一で代替済み**(#323)。typed throws 構文は Swift 5.10 サポート終了まで延期(見送り理由は ADR-0005 Amendment 2026-08-02) |
| deprecated 7 件の削除 | ADR-0005 Amendment | 削除可能条件を満たして残存 |
| 命名統一(G3)・二層 API 名の整合 | (新規、本レビューで顕在化) | 未整理 |
| Swift 6 strict concurrency 対応(G2) | (新規) | **実施済み**(#328 / PR #386・#394 / 2026-08-02)。全 Swift ターゲットに適用し新旧両ツールチェーンで警告ゼロ・CI ゲート化まで完了。公開 API のシグネチャ変更は発生せず |
| `@_exported import Metal/MetalKit/simd` の扱い決定(G16) | (新規) | 未判断 |
| `GPUBuffer` subscript / `NoiseTexture` stops の failure mode 統一(G14) | (新規) | 不統一のまま |

**G2(Swift 6)は当初の見立てどおり工数最大だったが、公開 API のソース互換は壊さずに完了した**(#328、2026-08-02)。`Sendable` 準拠追加や `@Sendable` 化を要する公開 API は結果として現れず、除去は内部構造の変更(弱参照を 1 段のクロージャに閉じ込める、通知トークン/セッションの保持者化、非 Sendable 値を隔離境界へ渡さない引数設計)で足りた。「両ツールチェーンで警告ゼロ」は CI ゲート化済み(`build-and-test` と `build-swift-5-10` の `-warnings-as-errors` + `scripts/check-strict-concurrency.py`)。**残る一歩は Swift 6 *language mode* への移行**で、これは swift-tools-version を 6.0 に上げる＝最小サポートを Swift 6 に引き上げることを意味するため、macos-14 / Xcode 15.4 ランナーを落とす判断とセットで別途扱う(現時点では診断はすべて警告扱いのまま、実質エラー相当にゲートされている状態)。

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

## v0.8.x 実装計画(既知課題の完遂)

既知課題は 4 つの Wave に分けて v0.8.x 期間中に片付ける。W0 は全並行可、W1 が背骨(順序依存あり)、W2/W3 は W1 と並行しつつ一部が W1 の順序に従属する。Issue の切り方はロードマップと同じ流儀(S は同一レイヤ束で 1 Issue + チェックリスト、M/L は各 1 Issue、設計判断を伴うものは ADR 先行)。

### 順序を決める 4 つの依存関係(計画の背骨)

1. **命名統一(W1-3)が英語化(W3-1 Core)より先** — rename で doc コメントごと動くため、先に英語化すると二度手間
2. **ゴールデンイメージ回帰(W2-2)が P3D 意味論統一(W1-6)より先** — 描画結果が変わる breaking の影響範囲を、ゴールデンの差分として可視化してから実施する
3. **swift-format 一括適用(W2-8)は W1 の rename 群の後** — 全ファイルを触る変更なので、進行中の breaking PR との conflict を避ける
4. **命名 deprecation → 削除に 0.8.x 内で最低 2 リリース必要** — ADR-0005 Amendment の「deprecation を含む minor を公開してから次で削除」を守るため、命名統一は 0.8.x の早い段階で着手する

### W0: クイックウィン(依存なし・全並行・即着手可)

| ID | 内容 | 対応ギャップ | 規模 |
|---|---|---|---|
| W0-1 | 法務・安全束: `THIRD_PARTY_LICENSES.md`(Syphon = Simplified BSD の著作権表示+全文)+ `SECURITY.md` + GitHub Private vulnerability reporting 有効化 | G4, G12 | S |
| W0-2 | 配布防御束: `refs/tags/v*` の deletion/update 禁止 ruleset + releasing.md に「Release asset は削除しない」明文化 + 全タグの binaryTarget URL 死活チェック(週次 CI) | G8 | S |
| W0-3 | リリース自動化修正束: `README.en.md` を release.yml の sed と validate-ai-docs.sh の**両方**に追加 / README 日英に DocC サイトリンク / `release:*` ラベル説明修正 / ci.yml に timeout-minutes | G10 | S |
| W0-4 | コミュニティ受け入れ束: `CONTRIBUTING.md`(DEVELOPMENT.md へ委譲する薄い入口)+ Issue テンプレート(バグ/機能/質問、cli との振り分け導線)+ PR テンプレート | G12 | S |
| W0-5 | dependabot 拡張(npm `/website` + gitsubmodule)+ 既存 alert 9 件の棚卸し(Windows 限定 dismiss 方針の適用) | G20 | S |

### W1: 破壊的変更ウィンドウの完遂(0.8.x の背骨・この順で)

| ID | 内容 | 対応 | 規模 | 依存 |
|---|---|---|---|---|
| W1-1 | **ADR: API 表面の最終整理**(命名 3 系統の統一方針 / `begin*Record` 揺れ / 二層 API 名 `screenX` vs `screenPosition` の寄せ先 / `@_exported import Metal・MetalKit・simd` の維持可否 / `_metaphorSyphonRegister` の隠蔽)。**設計判断のためユーザーレビュー必須** | G3, G16 | M | なし(最優先) |
| W1-2 | deprecated 7 件の削除(protocol requirement 2 件は準拠型への影響を確認) | G15 | S | なし |
| W1-3 | 命名統一の実装(W1-1 の ADR に従い、旧名は deprecated エイリアスで 1 リリース維持 → 次リリースで削除) | G3 | M | W1-1 |
| W1-4 | 生成系 API の**エラー型統一**(`throws` は各モジュールのエラー型だけを投げる・生 `NSError` の素通りを塞ぐ・全 public throwing API に `- Throws:` を明記)。**typed throws 構文の適用は Swift 5.10 サポート終了まで延期**(SE-0413 は Swift 6.0 の機能で、最小サポート 5.10 ではパース不可 — ADR-0005 Amendment 2026-08-02) | G14 | M | W1-1(エラー型設計を含むため) |
| W1-5 | failure mode 統一: `GPUBuffer` subscript(trap → 方針確定)/ `NoiseTexture` stops 空配列 / `SoundFile` doc の `try!` 例の是正 | G14 | S | W1-4 |
| W1-6 | 変換ファミリの P3D 意味論統一(ADR-0005 follow-up)。**実施済み**(#325 / PR #384 / ADR-0005 Amendment 2026-08-02)— Option A を採用し `translate(x,y)`/`rotate(a)`/`scale(sx,sy)` を 3D にも適用。実測で前提が覆り、3D の既定カメラは既に Processing P3D と同型のピクセル空間なので実装は 3 行・既存テストの赤 0・既存ゴールデン 6 枚とも差分 0。「統一しないと壊れたまま」だった Examples 4 本が直る(ToonShading を Probe で before/after 実測: 重心 (62,55) → (320,179))。検出用ゴールデン `transform-2d-on-3d` と `TransformSemanticsTests` を新設。逆方向(3D 変換 → 2D 描画)は 2D が `float3x3` アフィンのため構造的に到達不能で 9 例が残る(→ #387) | G1 | S | W2-2(ゴールデン回帰)導入後 — 充足 |
| W1-7 | `loadPixels()` メインキャンバス readback(ADR-0005 follow-up) | G1 | M | W2-2 導入後が望ましい |
| W1-8 | コマンド記録の既定 ON 化の判断(ADR-0003 follow-up)。**見送り確定**(#327 / ADR-0003 Amendment 2026-08-02)— 既定 ON は `loadPixels()` の Processing 互換(W1-7)を全スケッチで失わせるため、現行の「影オン=常時記録 / 影オフ=`METAPHOR_COMMAND_RECORD` opt-in」を 1.0 の確定仕様として凍結。定常フレームの描画結果が経路非依存であることを ADR の保証として宣言(常設テストは #375、環境変数の文書化は #376) | G1 | S〜M | なし |
| W1-9 | **Swift 6 strict concurrency**(最重量)。段階導入: (1) 有効化方法の検証 → (2) Tier 1 独立モジュール → (3) Core・Tier 2 → (4) CI ゲート化。**全段階完了**(#328 / PR #386・#394 / 2026-08-02)— 方式は `#if compiler(>=6.0)` で `.enableUpcomingFeature` / `.enableExperimentalFeature` を振り分け(5.10 では upcoming 名が黙って無視されるため。`unsafeFlags` は版指定の依存を壊すので不可)。**Swift ソースを持つ 25 ターゲット全部に適用し、Swift 6.3.3 / 5.10 の両ツールチェーンで警告ゼロ**(6.3.3: 21 → 0 / 5.10: 26 → 0)。ゲートは `build-and-test` の `-warnings-as-errors`(既存)に加え、`build-swift-5-10` にも同フラグを追加(5.10 でしか出ない警告が実在するため)、さらに新ターゲットの設定書き忘れを `scripts/check-strict-concurrency.py` が検出。`@preconcurrency import` は全数を一度剥がして再測定し **29 → 13**(両ツールチェーンの和集合で実際に必要な 13 箇所だけを根拠コメント付きで残した)、`@unchecked Sendable` は +3(通知トークン・キャプチャセッション保持者・非 Sendable 値の箱、いずれも根拠コメント付き)。実測記録は Issue #328 のコメントが正典 | G2 | **L** | 完了 |

### W2: 品質ゲート(W1 と並行、W2-2 は W1-6 より先)

| ID | 内容 | 対応 | 規模 |
|---|---|---|---|
| W2-1 | GPU skip 可視化: CI に `isGPUAvailable` 明示アサート or skip 件数レポート | G5 | S |
| W2-2 | **ゴールデンイメージ回帰基盤**: 決定論レンダリング(#70)+ `RenderTestHelper` 読み戻しを全フレームハッシュ比較へ拡張。代表シーン(2D 図形/ブレンド/3D ライティング/シャドウ/ポストFX)のゴールデン整備 | G6 | M |
| W2-3 | `Sources/MetaphorCore/Sketch/` テスト増強(公開 API 面のライフサイクル・SketchConfig・イベント系。breaking 前に書けば W1 の挙動変化検出網を兼ねる) | G7 | M |
| W2-4 | カバレッジのモジュール別可視化(レポートのアーティファクト保存 or PR コメント) | G18 | S |
| W2-5 | `build-swift-5-10` の必須チェック昇格 + macos-14 でのテスト実行の実現可否検証 | G17 | S〜M |
| W2-6 | `ObservabilityOverheadTests` の壁時計アサーションを #149 基準で env ゲートに隔離 | — | S |
| W2-7 | Examples 差分ビルド(PR が `Examples/` を触ったときのみ該当 example をビルド) | G18 | S |
| W2-8 | swift-format 導入と一括適用(**W1 の rename 完了後**) | G18 | M |

### W3: ドキュメント・英語化(並行トラック、W3-1 Core は W1-3 後)

| ID | 内容 | 対応 | 規模 |
|---|---|---|---|
| W3-1 | **API doc コメント英語化**(Epic #295 I2 として起票)。モジュール単位に分割し、周辺モジュール(Audio/Network/Physics 等)から先行、**Core は W1-3 命名統一の後**。`llms.txt` は生成物なので自動追随。機械的作業のためサブエージェント委譲向き | G9 | **L** |
| W3-2 | `CHANGELOG.md` 新設 + リリースノート様式(人間向けハイライト枠)。**早期に開始し、0.8.x の breaking をすべて記録していく**(v1.0 移行ガイドの原稿になる) | G11 | S |
| W3-3 | Processing 移行ガイド(API 対応表 + 落とし穴集。`.pde` 同梱資産の成果物化) | G13 | M |
| W3-4 | TCC 権限ドキュメント(マイク/カメラ、失敗時の復旧手順、該当 example への注記) | G13 | S |
| W3-5 | docs 整備束: `docs/README.md` 英語化 / 利用者向け Troubleshooting 拡充(Intel Mac・SwiftPM 解決失敗)/ Examples「順に学ぶ」推奨順路 1 ページ | G13 | S×3 束 |

### W4: ポリシー成文化(v0.9.0 の直前・入口条件の一部)

| ID | 内容 | 対応 | 規模 | 依存 |
|---|---|---|---|---|
| W4-1 | API 安定性ポリシー文書(何が public API か / deprecation 窓 / ABI 非保証(ソース互換のみ)/ 0.9 系の運用規律)。**実施済み**(#338 / 2026-08-02)— `docs/api-stability-policy.md`(英語)。4 層の線引き・`@_spi`/アンダースコア/`MetaphorTestSupport`/Examples の除外・ソース互換の落とし穴(enum case 追加・protocol requirement 追加)・deprecation 窓(公開リリース単位、1.0 後の削除は major)・変更種別 → bump の表・描画結果は「major を強制しないが `Breaking Changes` に載せる」(ADR-0003 Amendment の既定 ON 化余地と整合)・CONTRACT.md に載る契約と載らないもの(`METAPHOR_COMMAND_RECORD` を実例に)・`@_exported` 凍結宣言・最小サポート引き上げ = minor・preview 宣言の枠組み(現時点で preview モジュールはゼロ)。**残った未確定**: stdin プロトコルのバージョニング(→ #339)。doc で「内部」と明記された public 表面の退避先は **#388 で解消済み**(2026-08-02)— 5 シンボルを `internal` 化し、`@_spi` は不要と判定。ポリシー §1 は「アクセス修飾子が約束そのもの」に書き換え済み | G11 | S〜M | W1-1 |
| W4-2 | 契約フリーズ点の明記(`frame.json` の全キー凍結 / stdin プロトコルの互換規約とバージョニング)。**クロスリポ同時 PR**。Parameter Store の schema 変更(Epic D の D3/D4)が入った後に実施 | G19 | M | Phase 2 D3/D4 |
| W4-3 | bus factor 開示(README への単独メンテ・ベストエフォート明記)。**実施済み**(#338 と同 PR / 2026-08-02)— README 日英に「メンテナンス体制 / Maintenance」節。G21 の「リリースが個人 PAT と admin bypass に依存」は**事実誤り**で、`release.yml` は GITHUB_TOKEN のみ・ruleset を bypass しない(唯一の PAT `CLI_DISPATCH_TOKEN` は metaphor-cli への Syphon pin dispatch 専用で未設定なら skip)。開示はこの事実に基づき「応答時間は保証しないが、リリース経路とタグ/asset 保護は個人の手作業に依存しない」と書いた | G21 | S | なし |

### 実装の進め方

1. **Epic Issue「v1.0 readiness」を 1 本立て、W0〜W4 の各 Issue を子としてチェックリスト管理**(Epic #75 と同じパターン)。W0 の 5 束と W1-1 から着手
2. **W1-1(ADR)が全体のクリティカルパスの先頭。** 命名の寄せ先・`@_exported` の扱いはここで確定し、ユーザーレビューを経てから W1-3 以降を流す
3. サブエージェント委譲方針はロードマップと同一: 設計判断・契約・レンダリングに触れるもの = 高性能モデル、機械的作業(英語化・テスト雛形・ボイラープレート)= 安価なモデルへ委譲、独立 Issue は worktree 分離で並列
4. Phase 2(Parameter Store)はロードマップ側の管轄でそのまま並行。合流点は W4-2(契約フリーズ)のみ
5. 0.8.x のリリースは通常どおりラベル駆動で刻む(命名 deprecation → 削除の 2 リリース確保を意識)

## 残る設計判断(各 Issue/ADR の中で決める)

1. **命名 3 系統の寄せ先・二層 API 名・`@_exported import` の扱い** → W1-1 の ADR でユーザーレビューを経て確定
2. **英語化の 0.9.0 ブロッカー性**: W3-1 は additive なので 0.9.x に食い込んでも凍結は妨げない。ただし v1.0.0 昇格条件には含める(下記)
3. **preview 宣言の要否**: 0.9.x の実績で判断(マイルストーン節参照)

## 完了判定

### v0.9.0 の入口条件(API 凍結宣言)

- [x] W1 全項目が「実施済み」または「見送りの ADR 追記済み」(2026-08-02 完遂)— 実施 = W1-1(ADR-0007)/ W1-2(#321)/ W1-3 フェーズ 1(#322・#368)/ W1-4 はエラー型統一で代替 + 構文は延期を ADR 化(#323)/ W1-5(#324)/ W1-6 P3D 統一(#325)/ W1-7 loadPixels(#326)/ W1-9 Swift 6 は**両ツールチェーン警告ゼロ + CI ゲート化**(#328)。見送り = W1-8 記録既定 ON(ADR-0003 Amendment)
- [x] W2-1〜W2-3(GPU skip 可視化・ゴールデン回帰・Sketch/ テスト)が CI で稼働(#329 / #330 / #331、2026-08-01〜02)
- [x] W4-1(API 安定性ポリシー)公開済み — `docs/api-stability-policy.md`(#338 / 2026-08-02)。あわせて W4-3(bus factor 開示)も完了
- [ ] Phase 2(Parameter Store)完了・実運用 1〜2 サイクル経過
- [ ] W4-2(契約フリーズ点)が両リポで合意済み
- [ ] CHANGELOG に 0.8.x の全 breaking が記録済み(運用中。0.8.x の各 breaking はマージ時に `## [Unreleased]` へ記録している。**最後の 0.8.x リリース公開時点で確定**)

**残る入口条件は Phase 2 とその後続(W4-2)のみ。** ほかに v0.9.0 前に片付ける必要があるものとして、#322 フェーズ 2(命名の旧名削除。**deprecation を含む minor の公開が前提** — ADR-0005 Amendment)と #388(doc で内部と明記された public 表面の退避。凍結後は `public` を剥がすこと自体が major になる)がある。

### v1.0.0 への昇格条件

技術条件とコミュニティ条件の**両方**を満たした時点で昇格する(2026-08-02 決定)。片方だけでは昇格しない。

**技術条件**(readiness — すべて必須):

- [ ] 0.9 系で breaking なしの実績(全モジュール。壊したくなったものは preview 宣言で決着済み)
- [ ] Examples 278 本の全数スイープ green(`examples-sweep.yml` full=true)
- [ ] API doc コメント英語化(W3-1)完了
- [ ] metaphor-sketches での実運用検証を通過
- [ ] リリースノートに 0.x → 1.0 の人間向けハイライトと移行ガイド(CHANGELOG から生成)

**コミュニティ条件**(採用の実績):

- [ ] GitHub スター数が 100 を超える(2026-08-02 時点: 1)

v1.0.0 は SemVer 契約の凍結宣言であり、利用者がいて初めて意味を持つ。コミュニティ条件を満たすまでは 0.9.x のまま改良(additive / fix・品質向上・ドキュメント・実運用フィードバックの反映)を継続する。スター数は外部要因のため期限は設けない。技術条件が先に揃った場合も 0.9.x を延長する — 凍結規律の運用実績が長くなること自体が昇格時の信頼材料になる。
