# ADR-0014: ビューアのフレーム転送を専用 IPC にし、Syphon を独立 Package の plugin へ分離する

- **Status**: Accepted
- **Date**: 2026-08-22
- **Deciders**: @shinyaoguri
- **PR / Commit**: (この ADR を含む PR = [#792](https://github.com/shinyaoguri/metaphor/issues/792) M0。実装は §Follow-ups の子 Issue が担う)

## Context

[ADR-0001](0001-separate-syphon-into-its-own-target.md)（2026-06-29）で Syphon の**ランタイム**は
`MetaphorCore` から分離済みである — `SyphonPlugin: MetaphorOutputPlugin` が `post()` で publish し、
renderer は Syphon を名指しせず、`MetaphorSyphon` が C constructor 経由で `MetaphorOutputRegistry` に
factory を自動登録する。しかし **packaging** は分離されておらず、次の 4 点が残っていた
（[#792 本文](https://github.com/shinyaoguri/metaphor/issues/792)）。

1. **配布境界**: root `Package.swift` が `Syphon.xcframework` の remote binaryTarget を宣言している。
   umbrella から `MetaphorSyphon` を外しても、**使わない product 経由の binaryTarget まで SwiftPM は download する**
   （[所見 1-a](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)）。
   代償は resolve 失敗（asset 欠落・ネットワーク）、sourcekit-lsp の背景インデックス破綻
   （[#578](https://github.com/shinyaoguri/metaphor/issues/578)）、毎リリースの xcframework 再ビルド →
   checksum → pin bump の連鎖（cli 側の pin bump PR は 2 か月で 11 本）、非 macOS への将来の足かせ
2. **明示 API の不在**: `SketchConfig.syphon` / `syphonName` / `SketchWindowConfig.syphonName` /
   `METAPHOR_SYPHON_NAME` と Core の公開 API が Syphon 固有で、`MetaphorOutputRegistry.factory` は単一
   （NDI 等が増えると後勝ち）。render loop の要件（`.displayLink` → `.timer`）も Syphon 固有の config を見て決めている
3. **viewer transport**: `metaphor watch --viewer` は子（ヘッドレスのスケッチ）が Syphon サーバーへ publish し、
   親（cli）が Syphon client で受ける。親子専用の転送に外部アプリ向けの名前 discovery・zombie server 対策
   （[#715](https://github.com/shinyaoguri/metaphor/issues/715)・cli の `SyphonRecoveryPolicy` とテストで 384 行）を抱えている
4. **Core の Syphon 固有の起動制御**: `resolveSyphonName(requiresOutput: true)` がヘッドレス = 出力名必須 =
   Syphon 起動を強制し、Probe しか使わない `make *-shots` でも毎回 Syphon server が立つ

### なぜ 1 つの ADR か

「Syphon を独立 Package へ出す」と「ビューアの転送路を Syphon 以外にする」は**片方だけでは成立しない**。
umbrella から `MetaphorSyphon` を外した瞬間に `watch --viewer` は絵を失い、逆に transport だけ替えても
binaryTarget の代償は消えない。2 つの軸を持つが結合した 1 判断なので 1 ADR にまとめる
（README の「1 ADR = 1 判断」に対する例外として明記）。

### 制約

- **Swift 5.10 互換**（CI `build-swift-5-10`）と **`-warnings-as-errors`**: deprecated API の参照は警告ではなく
  ビルド失敗になる（[追記](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379812561)）
- **cli は `Foundation.Process` で任意の sketch 実行体を起動する**（`brew install` + `swift build` した素の実行体）。
  LaunchAgent / app bundle / XPC Service のような **install footprint を持てない**。`Process` は stdin/stdout/stderr
  以外の fd を子へ継承しない（[所見 1-d](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)）ので、
  制御チャネルにはパスを環境変数で渡せる Unix domain socket が要る
- **オーナー判断**（[決定 1〜3](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379915189)）:
  (1) deprecated API は採用しない — 将来も推奨される技術で組む / Syphon は公式プラグインとして必ず使える状態を保ち、
  **使い方を今より複雑にしない** (2) 既定 template は Syphon-free (3) `__capture` / `__view` は廃止
- **現在の開発スタイルを保つ**: 消えない窓・ビルドエラー overlay・クラッシュ後も最後の絵を保持・入力転送
  （[`docs/design/live-viewer.md`](../design/live-viewer.md) の価値そのもの）
- **クロスリポ契約**: [CONTRACT.md](../../CONTRACT.md) 契約点 1（Syphon pin）・2（環境変数）・5（Syphon フレーム）に
  触れるので metaphor-cli と同名ブランチで同時に変える
- **利用者がまだいない**（0.x・[ADR-0009](0009-unfreeze-api-until-1-0.md)）: 互換窓は軽視してよい

## Considered Options

### 軸 A: Syphon（binaryTarget）の置き場

| 案 | 内容 | 却下理由（実測） |
|---|---|---|
| A-1 現状維持 | root Package に binaryTarget、umbrella が `MetaphorSyphon` を含む | 上記 4 点がそのまま残る。#578 は回避策（cli template の `.sourcekit-lsp/config.json`）を恒久化することになる |
| A-2 umbrella から外すが同じ Package に残す | compile / link は分離される | **resolve は分離されない**。消費側が使わない product の binaryTarget でも SwiftPM は download する（[所見 1-a](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)、tools 5.10 で再現）。breaking のコストに対し便益が無い |
| A-3 `metaphor-plugins` に product として集約 | 公式 plugin 置き場に同居 | 同リポ [ADR 0001](https://github.com/shinyaoguri/metaphor-plugins/blob/main/docs/decisions/0001-monorepo-multi-product.md) の根拠「使わない product はビルドもリンクもされない」は binary artifact には当てはまらない（A-2 と同じ実測）。NDI 等が増えるたびに Syphon しか使わない消費者が他の artifact まで取得する |
| A-4 tools 6.1 に上げて package traits で gate | `.target(name:condition: .when(traits:))` で binaryTarget を条件付きに | **traits は compile / link の条件であって resolve の条件ではない**。`traits: []` の消費者でも download が走る（[所見 1-a](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)）。tools-version を上げる是非と無関係に成立しない |
| **A-5 独立リポジトリ `metaphor-syphon`（採用）** | `MetaphorSyphon` + C bootstrap + xcframework（自リポの Release asset を self-pin）+ submodule + build script + Examples 3 本を移す | metaphor-plugins ADR 0001 が自ら挙げる分離の正当理由「依存が重い / 別のリリースペース」の**初適用**（[所見 3-3](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)） |

### 軸 B: ビューアの転送路

評価軸は制約から導いた 4 つ — 非推奨 API なし / install footprint なし / 開発スタイルを保つ / CPU コピーなし
（全候補の棚卸しは [効率・単純さ・最適性の評価](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380287593)）。

| 案 | 非推奨 | footprint | スタイル | コピー | 却下理由（実測） |
|---|---|---|---|---|---|
| B-1 Syphon 継続 | あり（下記 B-2 と同じ機構） | binary artifact | 保つ | 0 | 軸 A の代償が残る。discovery・zombie・rebind 対策が親子専用には過剰 |
| B-2 global IOSurface（`kIOSurfaceIsGlobal` + ID 渡し） | **あり**（macOS 10.11 で deprecated「Global surfaces are insecure」） | なし | 保つ | 0 | 親子間 lookup・子の終了後の保持まで動くことは実測した（[所見 1-b](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)）が、**オーナー判断 (1) で不採用**。Syphon 自身がこの機構（[所見 1-c](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)）で、同一マシンの任意プロセスが ID を当てれば読める |
| B-3 IOSurface + Mach port（`IOSurfaceCreateMachPort`） | port を渡す経路の `bootstrap_register` が deprecated | なし | 保つ | 0 | **親子が Mach で出会う公開経路が無い**。cli は `Process` で素の実行体を起動するので、bootstrap 登録（deprecated）か XPC（B-4）か exception port のハックしか残らない（[所見 1-c](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)） |
| B-4 XPC（`IOSurfaceCreateXPCObject` / `MTLSharedTextureHandle`） | なし | **LaunchAgent か app bundle** | 保つ | 0 | 素のプロセスの `xpc_connection_create_mach_service(…, LISTENER)` は launchd 未登録で **両側 `Connection invalid`**、`NSXPCListener.anonymous().endpoint` は `NSKeyedArchiver` で Data 化できない（NSXPCCoder 限定）。**install footprint が必須**になり「使い方を複雑にしない」に反する（[決定](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379915189)） |
| B-5 子が自分の窓を持つ（reload 時は新旧を重ねる） | なし | なし | **変わる** | 0 | IPC ゼロで最も単純だが、overlay・クラッシュ後の保持・入力注入を失う。スタイルを捨てる案 |
| B-6 ScreenCaptureKit で子の窓を撮る | なし | なし | 保つ | 0 | 画面収録の TCC・WindowServer 経由の遅延・隠れ窓は撮れない |
| B-7 VideoToolbox + localhost | なし | なし | 保つ | encode / decode | リモート表示向け（本件の非目標） |
| B-8 raw BGRA を socket で送る | なし | なし | 保つ | **CPU 500 MB/s（1080p60）** | 動くが無駄。最終フォールバック候補に留める |
| B-9 通常ファイルの `mmap` | なし | なし | 保つ | 0 | dirty page のディスク書き戻しが起きる（`.metaphor/` が同期フォルダ配下なら最悪） |
| B-10 名前付き POSIX shm | なし | なし | 保つ | 0 | 名前 31 文字（`PSHMNAMLEN`）・leak した名前の掃除・列挙 API なし・`O_EXCL` と stale の扱い（[制約の実測](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380027348)） |
| **B-11 匿名 POSIX shm（fd を `SCM_RIGHTS` で渡す）+ Unix socket + `MTLBuffer(bytesNoCopy:)` + linear texture view（採用）** | **なし** | **なし** | **保つ** | **0** | 残る制約は `ftruncate` が 1 回しか効かないことだけ（resize = 新しい shm + `hello` 再送） |

B-11 の実測（Swift 6.3.3 / macOS 26 / Apple Silicon）:

- 子が 1080p の render target を shm buffer へ GPU blit し、親が**別プロセスの read-only mapping** から texture view を
  作って GPU で読むと**ピクセル一致**。子の終了後も親の mapping は読める（= reload 中の旧フレーム保持は追加実装なし）
  （[shm 実測](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379915189)）
- `shm_open` → 即 `shm_unlink` で名前を捨て、fd を `sendmsg(SCM_RIGHTS)` で渡す → 親は `recvmsg` → `fstat` でサイズ検証
  （3 slot 分 24,920,064 byte が一致）→ `mmap` → `makeTexture(offset: 2 × slotBytes)` で GPU 読み一致
  （[fd 渡し](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380143746)）。名前が無いので
  **fd を持つ 2 プロセス以外から到達できず、leak もしない**
- 定常コスト（120 フレーム p50 の GPU 時間）: 1080p **shm 0.049 ms** vs IOSurface 0.050 ms / 4K **shm 0.093 ms** vs
  IOSurface 0.061 ms。commit → complete はどちらも ≈ 0.3 ms。**IOSurface と同等**で、理論下限
  （CPU コピー 0・子の GPU 1・親の GPU 1・子の完了 → 親の次の vsync）との差は無い
  （[評価](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380287593)）
- 再現コードは [spike コード](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380480130)

### 付随する選択肢

| 論点 | 候補 | 採用と理由 |
|---|---|---|
| producer の置き場 | (a) `MetaphorCore` 内の `ViewerOutputPlugin` / (b) 別ターゲット `MetaphorFrameIPC` | **(a)**。source-only・Apple 専用・CONTRACT 対象という性質が Probe / `InputInjectionPlugin` / `StatePlugin` と同じで、Core の外に出す理由が無い（[所見 3-1](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)） |
| slot の同期 | (a) socket の `release` メッセージ / (b) `IOSurfaceIsInUse` / `IncrementUseCount` / (c) 共有メモリ上の C11 atomics | **(a)**。(b) は IOSurface を捨てた時点で消える（採用前の実測では commit 直後の数 ms が false になる隙間もあった — [追記](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379812561)）。(c) は in-process の fake で再現できずテストしにくく、Core の C 依存を増やすだけ。socket 越しのプロトコルは両リポとも in-process の fake producer / consumer で検証できる（[決定](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379915189)） |
| slot 数と `release` | 1 slot / 2 slot（`release` 無し）/ **3 slot + `release`** | 1 slot は Syphon 同様 tearing、2 slot で `release` 無しは親の GPU 読みが 1 frame 以上遅れると競合。`release` は 10 行で、protocol を fake で証明可能にする |
| 互換窓 | (a) cli が IPC と Syphon の dual transport を持つ / (b) **cli は IPC のみ** | **(b)**。利用者がまだいないので互換窓を作らない。`hello` が来ない子には「metaphor ≥ N が必要」を overlay で案内し、Syphon.framework の同梱・pin 契約（契約点 1）は IPC 化と同じ cli リリースで落とす（[A-2](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380027348)） |
| 既定 template | (a) metaphor-syphon を既定で依存に入れる / (b) **Syphon-free、`--template syphon` が足す** | **(b)**。`mcp` 単独の暗黙 publish は「リンクされていれば publish、無ければ 1 行の注記」 |
| umbrella からの `MetaphorSyphon` 削除 | (a) deprecation 窓を通す / (b) **直接削除（breaking minor）** | **(b)**。in-tree と metaphor-syphon が同じモジュール名 `MetaphorSyphon` を持ち、両方を同時にリンクできない。[ADR-0009](0009-unfreeze-api-until-1-0.md) の「窓を通すこと自体が設計をゆがめる場合」に該当。`SketchConfig.syphon*` 等の**フィールド**は通常どおり deprecate → 次 minor で削除（[ADR-0005](0005-sketch-api-consistency.md) Amendment） |
| AI 向けドキュメント | (a) 本体の `llms.txt` にプラグイン分も載せる / (b) **プラグインが自前の `llms.txt` を持ち、cli の `api_reference` が両方を引く** | **(b)**。プラグインが増えても同じ型（metaphor-plugins 全体の方針にする） |

## Decision

**軸 A は A-5、軸 B は B-11 を採用する。** 到達形は次のとおり（[実装計画 §1](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380480298)）。

```text
metaphor（本体・binaryTarget なし）
├── MetaphorCore
│   ├── MetaphorOutputProviders   ← 旧 MetaphorOutputRegistry の一般化（複数 provider + render loop 要件）
│   ├── ViewerOutputPlugin        ← viewer 用 frame IPC の producer（METAPHOR_VIEWER_SOCKET で自動登録）
│   └── CMetaphorIPC (C target)   ← shm_open / sendmsg(SCM_RIGHTS) の薄いラッパ（CMetaphorSyphonBootstrap と入れ替わり）
└── metaphor (umbrella)           ← MetaphorSyphon を含まない

metaphor-syphon（独立リポジトリ・公式プラグイン）
└── MetaphorSyphon + CMetaphorSyphonBootstrap + Syphon.xcframework（自リポの Release asset を self-pin）
    使い方: Package.swift に 1 行 + import MetaphorSyphon + SketchConfig(plugins: [.syphon()])

metaphor-cli
└── MetaphorViewer/FrameIPCSource ← socket を listen してから子を起動、METAPHOR_VIEWER_SOCKET を注入
```

責務: 通常の描画と CLI live viewer = 本体 + 内部 IPC / MadMapper 等への外部出力 = metaphor-syphon /
AI 向け観測 = Probe（不変）。

決め手は 3 つ。(1) **binaryTarget を root manifest から出す手段は別 Package しかない**ことが traits まで含めて
実測で確定した（A-2〜A-4 の却下）。(2) 転送路の候補を「非推奨 API なし・footprint なし・開発スタイルを保つ・
CPU コピーなし」で篩うと、**匿名 POSIX shm + fd 渡しだけが 4 軸を同時に満たし**、性能は IOSurface と同等だった。
(3) 親子専用の経路にすれば、外部アプリ向けの discovery・zombie 対策・名前衝突がまるごと不要になり、
cli から Syphon.framework の同梱と pin 自動化（契約点 1）を落とせる。

### プロトコルの骨子（確定仕様は M2 = [#1037](https://github.com/shinyaoguri/metaphor/issues/1037) で書き換える CONTRACT.md 契約点 5 が正）

- **socket**: `AF_UNIX` / `SOCK_STREAM`。親が `bind` + `listen` してから子を起動し、パスを `METAPHOR_VIEWER_SOCKET`
  （`sun_path` の上限 = 103 byte 以下、cli は短い一時ディレクトリに置く）で渡す。メッセージは JSON Lines、
  未知の `t` / フィールドは無視（契約点 3 と同じ規約）。接続できなければ診断 1 行を出して plugin 無しで続行（Probe は動く）
- **メッセージ**: 子 → 親 `hello`（`protocolVersion: 1`・幅高・`pixelFormat: bgra8Unorm`・`alpha: premultiplied`
  （[ADR-0012](0012-alpha-semantics.md)）・`colorSpace`・`orientation: topLeft`・`bytesPerRow`・`slotBytes`・`slots: 3`・
  `backing: posix-shm`。**この行の `sendmsg` に shm の fd を添える**。resize は新しい fd つきで再送）/
  子 → 親 `frame {slot, seq}`（command buffer の完了ハンドラから送る。親は最新だけ表示 = latest-wins）/
  親 → 子 `release {slot}`（親の draw の完了ハンドラから。子は未 release の slot へ書かず、3 枚とも塞がっていれば drop）
- **shm レイアウト**: `bytesPerRow = alignUp(width × 4, minimumLinearTextureAlignment)`、`slotBytes = alignUp(bytesPerRow × height, pageSize)`、
  slot i は offset `i × slotBytes`。`ftruncate` は作成時 1 回
- **世代 / reload / クラッシュ**: 子 1 プロセス = socket 接続 1 本。親は接続ごとに世代を採番し、新世代の最初の `frame` が
  来るまで旧世代の texture を表示し続ける（mapping は子の死後も有効）。子が生きているのに `hello` が来なければ
  「metaphor ≥ N が必要」overlay
- **orientation**: row 0 = top の正立で規約化（現行の `flipped: true` + viewer 側シェーダの相殺をやめる）
- **`protocolVersion` の bump 規則**: `schemaVersion` と同じ（キー追加は据え置き、リネーム / 削除 / 意味変更は bump）

## Consequences

### Positive

- **root `Package.swift` から binaryTarget が消える**。通常の消費者は Syphon artifact を resolve も download もしない。
  [#578](https://github.com/shinyaoguri/metaphor/issues/578)（sourcekit-lsp の背景インデックス）は結果として解消し、
  cli template の `.sourcekit-lsp/config.json` 回避策を外せる
- CI 全 workflow の Syphon submodule → cache → `build-syphon.sh` の節（cache miss で +10 分）と、`release.yml` の
  xcframework ビルド → checksum → pin → cli への dispatch の連鎖が本体から消え、週次トレインが軽くなる
- viewer の転送路から **discovery・zombie server・UUID rebind・名前衝突**が消え、cli の `SyphonRecoveryPolicy`
  (+tests 384 行)・Syphon.framework の同梱・`doctor` の framework 検査・`syphon-bump.yml` が不要になる
- 露出が減る: global IOSurface は任意プロセスが ID で読めたが、匿名 shm は fd を持つ 2 プロセスしか到達できない
- 「ヘッドレス + Probe のみ」「ヘッドレス + IPC のみ」が正規の状態になり、`make *-shots` は Syphon server を立てなくなる
- 出力は `MetaphorOutputPlugin` + provider 登録の裏に置かれ、`hello` が `backing` / `pixelFormat` / `colorSpace` を
  持つので、Syphon が将来 XPC 化しても metaphor-syphon の更新だけで済み、HDR（`rgba16Float`）は additive に足せる
  （[先読み](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380334024)）

### Negative / Trade-offs

- **breaking**: `import metaphor` だけで `config.syphon` / `syphonName` / `METAPHOR_SYPHON_NAME` が効かなくなる。
  移行は `Package.swift` に metaphor-syphon を 1 行 + `import MetaphorSyphon` + `.syphon(name:)`
  （`changelog.d/*.breaking.md` に移行表）。`watch --no-viewer` / `mcp` 単独の暗黙 publish は
  「プラグインがリンクされているときだけ」になり、MadMapper 併用の利用者には見える変化
- ADR-0001 の不変条件②③（`config.syphon` による手軽な出力・umbrella 経由の透明な自動登録）を**意図的に捨てる**。
  ランタイム分離（Option A の機構）はそのまま metaphor-syphon で使う
- cli は IPC のみなので、**古い本体（N 未満）と新しい cli の組合せで `watch --viewer` は使えない**（overlay で案内）
- `MTLDevice.makeBuffer(bytesNoCopy:)` が shm の mapping を受け付ける挙動は文書化された API だが、OS / toolchain 更新で
  変わり得る。Core のテストに「shm → buffer → texture view → GPU 読み」を 1 本置き、CI の GPU ガード付きで常時検証する
- buffer-backed texture は linear 2D のみ（mipmap / MSAA 不可）。4K → 小窓の縮小でシマーが出るのは現行の IOSurface 経路と同じ。
  viewer 側で private texture へ blit + mip 生成すれば解消できる独立改善（cli に任意の Issue）
- `examples-sweep` / `tutorial-shots` が metaphor-syphon を GitHub から取得するようになる（offline 不可）。
  手元で offline のときは `swift package edit` でローカル checkout を当てる手順を DEVELOPMENT に書く
- Core の plugin / provider API サブセット（`MetaphorPlugin` / `MetaphorOutputPlugin` / `MetaphorOutputProviders` /
  `PluginFactory(requirements:)` / `MetaphorRenderer.device`・`addPlugin`・`removePlugin`・`plugin(id:)`）は
  metaphor-syphon が依存するので **1.0 扱いで凍結**し、変更は deprecate → 次 minor で削除とする
  （0.x の minor breaking が plugin のリリースを毎回強制しないため）。nightly の本体 `main` 互換ビルドで破れを検出する

### Follow-ups / 残課題

実装は [#792 の計画コメント §4 / §7](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380480298) の子 Issue が担う（M = metaphor / S = metaphor-syphon / C = metaphor-cli / P = metaphor-plugins）:

| ID | Issue | 内容 |
|---|---|---|
| M0 | [#1035](https://github.com/shinyaoguri/metaphor/issues/1035) | 本 ADR + ADR-0001 の Status 更新 + `live-viewer.md` の改訂 |
| M1 | [#1036](https://github.com/shinyaoguri/metaphor/issues/1036) | Core: provider 登録 / `PluginFactory(requirements:)` / `SketchWindowConfig.plugins`（additive） |
| M2 | [#1037](https://github.com/shinyaoguri/metaphor/issues/1037) | Core: `ViewerOutputPlugin` + `CMetaphorIPC` + 契約点 1 / 2 / 5 の書き換え（C1 と同名ブランチ） |
| M3 | [#1038](https://github.com/shinyaoguri/metaphor/issues/1038) | 契約点 6: プラグインの `llms.txt` の所在規約（C6 と同名ブランチ） |
| S0 | [#1039](https://github.com/shinyaoguri/metaphor/issues/1039) | `metaphor-syphon` 開設・移植・v0.1.0 |
| M4 | [#1040](https://github.com/shinyaoguri/metaphor/issues/1040) | **breaking**: umbrella / root / CI / Examples / tutorial から Syphon を外す |
| M5 | [#1041](https://github.com/shinyaoguri/metaphor/issues/1041) | 残りのドキュメント（README・DEVELOPMENT・releasing・DocC・THIRD_PARTY_LICENSES） |
| M6 | [#1042](https://github.com/shinyaoguri/metaphor/issues/1042) | **breaking**: deprecated フィールドの削除（N+2） |
| M7 | [#578](https://github.com/shinyaoguri/metaphor/issues/578) | 背景インデックスの回帰確認 → クローズ |
| C0〜C6 | [cli#162](https://github.com/shinyaoguri/metaphor-cli/issues/162) 〜 [cli#168](https://github.com/shinyaoguri/metaphor-cli/issues/168) | `FrameSource` 切り出し / IPC consumer / Syphon 同梱の撤去 / doctor / template / `api_reference` |
| P1 | [metaphor-plugins#7](https://github.com/shinyaoguri/metaphor-plugins/issues/7) | ADR 0001 への追記・roadmap |

順序: M1 → M2 ⇄ C1（同名ブランチ）→ 本体 release N → cli（C1 `release:skip` + C2 `release:minor` = 1 リリース）→ S0 → M4（N+1）→ M6（N+2）。
cli を先に出すと `hello` が来ず viewer が使えないので、**本体 → cli の順**で出す。

未決の細部（実装 PR で決めてよい）: `hello` の `colorSpace` の語彙、`frame` に `frameCount` / `time` を載せるか、
`bye` の要否、`ViewerOutputPlugin` の public 可否、C シムの関数名。

## References

- Issue [#792](https://github.com/shinyaoguri/metaphor/issues/792) — 設計 Issue。本文は当初案（IOSurface + Mach IPC）で、以下のコメント群が上書きする
  - [調査所見](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705) — spike 3 本（1-a traits でも binaryTarget は download される / 1-b global IOSurface の親子 lookup / 1-c Syphon の転送機構と Mach port の経路 / 1-d `Process` は fd を継承しない）と 3-1〜3-3 の推奨
  - [追記](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379812561) — `IOSurfaceIsInUse` の実測・`-warnings-as-errors` と deprecated 定数・`__capture` / `__view` の利用実態
  - [決定と transport の差し替え](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379915189) — オーナー判断 1〜3・XPC の実測・POSIX shm + `bytesNoCopy` の実測と性能表
  - [決定の追記と POSIX shm の制約](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380027348) — A-1〜A-4（使い方の到達形 / 互換窓 / AI docs / Examples）・`PSHMNAMLEN`・`ftruncate` 1 回
  - [改良: fd を `SCM_RIGHTS` で渡す](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380143746)
  - [効率・単純さ・最適性の評価](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380287593) — 全候補の棚卸し表と理論下限との比較
  - [先読み](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380334024) — Apple の方向性（XPC + システム仲介）と Syphon 本家の見込み、`backing` を `hello` に持たせる根拠
  - [spike コード](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380480130) / [実装計画](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5380480298)（決定事項 D1〜D14・仕様 §3・PR 分割 §4）
- [ADR-0001](0001-separate-syphon-into-its-own-target.md) — ランタイム分離（生きている）と packaging（本 ADR が置換）
- [ADR-0005](0005-sketch-api-consistency.md) Amendment / [ADR-0009](0009-unfreeze-api-until-1-0.md) — deprecation 窓と、窓を通さない例外条項
- [ADR-0012](0012-alpha-semantics.md) — viewer へ渡すフレームは premultiplied
- [CONTRACT.md](../../CONTRACT.md) — 契約点 1（廃止）・2（`METAPHOR_VIEWER_SOCKET` 追加）・5（viewer frame IPC へ書き換え）・6（プラグインの `llms.txt`）
- [`docs/design/live-viewer.md`](../design/live-viewer.md) — 方式 C（子プロセス + 共有 GPU メモリ）の設計。§2-2 / §3 / §7-4 を本 ADR で改訂
- [metaphor-plugins ADR 0001](https://github.com/shinyaoguri/metaphor-plugins/blob/main/docs/decisions/0001-monorepo-multi-product.md) — 「1 リポ 1 Package・product 分割」とその例外条項
- Syphon-Framework [#47](https://github.com/Syphon/Syphon-Framework/issues/47)（global IOSurface 削除への備え）/ [#10](https://github.com/Syphon/Syphon-Framework/issues/10)（XPC 仲介案）
- Apple: [`IOSurfaceCreateMachPort`](https://developer.apple.com/documentation/iosurface/iosurfacecreatemachport%28_%3A%29) / [`MTLSharedTextureHandle`](https://developer.apple.com/documentation/metal/mtlsharedtexturehandle) / [`makeBuffer(bytesNoCopy:length:options:deallocator:)`](https://developer.apple.com/documentation/metal/mtldevice/makebuffer%28bytesnocopy%3Alength%3Aoptions%3Adeallocator%3A%29) / [SwiftPM package traits](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packagetraits/)
