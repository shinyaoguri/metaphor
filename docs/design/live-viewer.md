# 設計ドキュメント: ライブビューア（子プロセス + IOSurface）

> ステータス: 実装済み（方式C / Phase 1a–1c-β3 完了・実機確認済み）。`metaphor watch --viewer`
> が既定で、ライブビューア窓を維持したまま子スケッチのみ差し替え、マウス/キー入力にも反応する。
> 残りは Phase 2（`saveState`/`restoreState`、任意）のみ。本書は当初の設計提案であり、確定仕様は
> 実装と各 PR を正とする。
> 対象: metaphor 本体（ライブラリ側の小〜中規模変更）+ metaphor-cli（ビューア本体）
> 関連: Syphon 統合、Probe プラグイン、`RenderLoopMode`、`SketchRunner`

## 1. 背景と目的

metaphor は Processing ライクなクリエイティブコーディング環境だが、スケッチ本体（Swift コード）の
ホットリロードがなく、編集→反映に `swift build && swift run`（数秒）を要する。シェーダは
hot reload できるが、スケッチロジックの反復は Processing/p5.js の「保存→即実行」に劣る。

この問題に対する解として、3 つの方式を検討した。

| 方式 | 実行時性能 | クラッシュ隔離 | 状態保持 | 実装リスク |
|---|---|---|---|---|
| A: watch + プロセス再起動 | 影響なし | ◎ | ✗ | ほぼゼロ |
| B: dylib 差し替え (dlopen/dlclose) | 微小 | ✗（ホスト巻き込み） | ○ | 高 |
| C: 子プロセス + IOSurface ビューア | ほぼなし（+1 frame） | ◎ | △（シリアライズ経由） | 中 |

方式 B は Swift の制約で危険:
- Swift の dylib は実質アンロード不能（型メタデータ / protocol conformance がランタイムに登録され
  解除できず、リロードごとにリークする）
- 旧コードへの参照（クロージャキャプチャ）が 1 つでも残るとクラッシュ / 未定義動作。metaphor は
  `PluginFactory`、CustomMaterial/PostEffect、compute コールバック、OSC/MIDI/audio ハンドラ、
  GPU `addCompletedHandler` など捕捉箇所が多い
- 新旧の同名型は別物で、状態移行はシリアライズ必須
- in-process ゆえユーザースケッチのクラッシュがホストごと巻き込む（ライブコーディングで致命的）

したがって **方式 C を採用** する。ライブコーディングの本質的価値（ウィンドウが消えない・
クラッシュしても落ちない・絵が途切れない）を、プロセス分離で B より低リスクに実現する。

## 2. なぜ metaphor に C 案が適合するか（コードベース根拠）

精査の結果、C 案は新機構の追加ではなく既存部品の組み替えに近い。

1. **レンダリングは既にウィンドウから独立している。**
   タイマーモードでは `SketchRunner` が `renderer.useExternalRenderLoop = true` を立て、
   `DispatchSourceTimer` から `renderFrame()` を直接駆動する。MTKView は「プレビュー専用
   （スロットリング許容）」と明記されている（`Sources/MetaphorCore/Sketch/SketchRunner.swift`
   の timer ケース）。App Nap 無効化も既に入っている。

2. **フレーム転送は実装済み。**
   `SketchConfig(syphonName:)` を渡すと自動でタイマーモードに切り替わり（同 `SketchRunner` の
   loopMode 決定ロジック）、`renderFrame()` 内で Syphon サーバーへ publish される。Syphon は内部的
   に IOSurface のゼロコピー共有。したがって「子プロセス + IOSurface」のフレーム経路は新規 IPC
   コードゼロで v1 が作れる。

3. **画面ブリットは MTKView デリゲート（`draw(in:)`）にしかない。**
   `renderFrame()` はオフスクリーンテクスチャへの描画 + Syphon publish + エクスポート + Probe で
   完結する。ウィンドウを作らず timer で `renderFrame()` を回すだけで描画は動き、ブリットパスは
   自然に無効化される。つまりヘッドレス化は「ウィンドウ消費者を外し Syphon だけ残す」構成。

4. **2 パス設計の配当。**
   キャンバス解像度とウィンドウサイズが分離済みのため、ビューア側のウィンドウリサイズ /
   レターボックスは子プロセスに一切影響しない。

### 重要な設計原則

- **通常実行パス（`swift run` 直叩き・配布アプリ）は一切変更しない。** 追加機能はすべてオプトイン。
- ウィンドウ描画（ブリットパス）は削除しない。ビューアは開発ツールであり、完成作品は単体アプリと
  して自分のウィンドウに描画する。「ウィンドウは任意の消費者の 1 つ」という現設計を裏付ける形。

## 3. アーキテクチャ

```
metaphor-cli (親/常駐)              スケッチ (子/使い捨て)
 watch ──build──┐                   ┌─ ヘッドレス起動
 supervisor ───spawn──────────────→ │  timer→renderFrame()
 viewer window                      │  Syphon publish ──┐
   ↑ Syphon client ─────────────────────────────────────┘ (IOSurface zero-copy)
   └ input events ──stdin(JSON lines)──→ InputInjectionPlugin → InputManager
   overlay: build error / crash log / FPS・probe HUD
```

保存 → 増分ビルド → 子のみ再起動。ビューアは最終フレームを表示し続け、新しい子の最初のフレームで
切り替わる。クラッシュ時は stderr をオーバーレイ表示し、次の保存で復帰。

## 4. ワークストリーム A: ライブラリ側（本リポジトリ）

変更は 3 点に閉じ、すべてオプトイン。

### A-1. ヘッドレス起動モード
- 対象: `Sources/MetaphorCore/Sketch/SketchRunner.swift` の `setupWindow`
- 内容:
  - `NSWindow` / `MetaphorMTKView` を生成しない
  - `renderer.configure(view:)` を呼ばない（→ ブリットが消える）
  - 強制的にタイマーモード + Syphon サーバー起動（既存経路を再利用）
  - `app.setActivationPolicy(.regular)` → `.accessory`（Dock 非表示）
  - `applicationShouldTerminateAfterLastWindowClosed` はヘッドレス時 `false`
- トリガ: 環境変数 `METAPHOR_VIEWER=1`（CLI が子に注入）。Syphon 名・FPS も環境変数で受領。
  **`SketchConfig` には触らない**（ユーザー API を汚さない）。
- リファクタ方針: `setupWindow` を `setupRenderer()`（共通）+ `attachWindow()` / `attachHeadless()`
  に分割。
- **最大の技術リスク / 最初に検証する項目**: `renderer.renderFrame()` が view 無しで完全に動くこと。
  特に `renderer.input` 等の初期化が `configure(view:)` に依存していないか。

### A-2. 入力注入プラグイン
- 新規: `Sources/MetaphorCore/Input/InputInjectionPlugin.swift`（`MetaphorPlugin` 準拠）
- 内容:
  - `pre()` で stdin の JSON lines を非ブロッキング読み取り（専用スレッド + ロック付きキュー、
    Probe のポーリングと同じ発想）
  - デキューしたイベントを `InputManager` の `handleMouseDown` 等
    （`Sources/MetaphorCore/Input/InputManager.swift` の Event Handlers）へ流す
- イベント JSON 例:
  - `{"t":"mouseDown","x":120.0,"y":80.0,"button":0}`
  - `{"t":"keyDown","code":53,"chars":"a","repeat":false}`
- 座標: 子はキャンバス座標で受け取る。ビューア→キャンバスの逆変換（レターボックス考慮）は親の責務。

### A-3. （Phase 2 / 任意）状態保持フック
- 対象: `Sketch` プロトコル
- 追加:
  ```swift
  func saveState() -> Data?       // default: nil
  func restoreState(_ data: Data) // default: no-op
  ```
- 流れ: 再起動直前に親が `{"t":"saveState"}` を送信 → 子が stdout に Data(base64) 出力 → 親が保持
  → 新しい子の起動時に渡す。Probe の atomic write 基盤を流用。decode 失敗時は黙って初期状態へ
  フォールバック。

## 5. ワークストリーム B: CLI ビューア（metaphor-cli リポジトリ）

工数の約 8 割。本リポジトリ外なので概要のみ。

1. **watcher**: スケッチディレクトリ監視 → `swift build`（metaphor 本体はビルド済み前提で増分のみ）
   → 成功で supervisor に再起動指示、失敗で stderr をビューアにオーバーレイ
2. **supervisor**: 子を `Process` で spawn（環境変数で `METAPHOR_VIEWER=1` + Syphon 名 + FPS 注入）、
   stdin/stdout/stderr をパイプ、終了コード監視 → クラッシュ検知でオーバーレイ。再起動時は
   新→旧の順で起動オーバーラップさせ「絵が途切れない」を実現
3. **viewer window**: Syphon client で子テクスチャを受信 → 常設ウィンドウに表示（レターボックス）。
   マウス/キーをキャプチャ → キャンバス座標へ逆変換 → JSON lines で子の stdin へ
4. **overlay/HUD**: ビルドエラー・クラッシュログ・FPS・probe 値（renderer は GPU タイムスタンプを
   既に記録）を半透明表示

## 6. フェーズ分割

| Phase | 内容 | 場所 | 規模 | 完了時の価値 |
|---|---|---|---|---|
| 0  | `metaphor watch`（監視→rebuild→再起動、ウィンドウは一瞬消える） | CLI | 数日 | 手動 re-run が消える |
| 1a | ヘッドレスモード (A-1) + `renderFrame()` view 非依存検証 | lib | 小 | Syphon 常用者に単体で有用 |
| 1b | 入力注入プラグイン (A-2) | lib | 中 | — |
| 1c | Syphon ビューア + supervisor + overlay | CLI | 大 | 本命: 消えない・落ちない |
| 2  | 状態保持フック (A-3) | lib+CLI | 中 | 再起動跨ぎの状態維持 |

Phase 0 → 1 の順なら途中で止めても損が出ない。

## 7. 着手前に確定すべき技術的論点

1. **`renderFrame()` の view 非依存性**（最重要・1a 冒頭で検証）。ダメなら renderer を
   ヘッドレス対応に小改修。
2. **入力転送経路**: stdin パイプを推奨（spawn 時に無料。Tier 規則で MetaphorCore は
   MetaphorNetwork に依存不可なので OSC は使わない）。
3. **座標逆変換ロジック**: MetaphorMTKView の既存変換と同式を CLI 側にも持つ（唯一の二重実装。
   仕様として明記）。
4. **再起動時の Syphon 名衝突**: 新旧オーバーラップ中は別名 / 世代サフィックス。

## 8. 制約（計画に織り込み済み）

- ビルド時間は短縮されない（C 案が直すのは消失/喪失/クラッシュ体験のみ）
- `createWindow`（セカンダリウィンドウ）はヘッドレス非対応 → ドキュメント明記
- lldb デバッグ用に `metaphor run --no-viewer`（従来インプロセス）を残す
- IME / 修飾キーの完全転送は edge case 残（開発ツールとして許容）

## 9. テスト戦略

- lib: ヘッドレス起動でフレームが Syphon に出ることのヘッドレステスト（CI は GPU 制約あり、
  `MetalTestHelper` のガード流用）。入力注入は JSON→InputManager 状態変化のユニットテスト。
- CLI: supervisor のプロセス再起動・クラッシュ検知の統合テスト。
