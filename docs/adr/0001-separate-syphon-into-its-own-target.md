# ADR-0001: Syphon を MetaphorCore から別ターゲットへ分離する

- **Status**: Accepted
- **Date**: 2026-06-29
- **Deciders**: shinyaoguri（PR レビュー）
- **PR / Commit**: refactor/syphon-target-separation

## Context

Issue #73「Syphon を MetaphorCore から分離（Core 純化）」。当初は「測って延期（icebox）」だったが、
動機（理論的関心 / 将来の platform 拡張 / 軽量ヘッドレス・AI Core）を踏まえ、**振る舞いを一切変えずに**
Syphon を別ターゲットへ切り出すことにした。

前提・制約:

- ランタイム描画経路は既に疎結合済み（`SyphonPlugin: MetaphorOutputPlugin` が `post()` フックで publish。
  `MetaphorRenderer.renderFrame()` は Syphon を名指ししない）。残る Core→Syphon 結合は
  **(a) `Package.swift` の `MetaphorCore → Syphon` 依存** **(b) `@_exported import Syphon`**
  **(c) 便利 facade（`startSyphonServer`/`syphonOutput`）と `SketchRunner` の自動配線** の3点のみ。
- **不変条件（最優先）**: ①性能を低下させない ②`config.syphon`/`syphonName`/env による手軽な Syphon 出力を維持
  ③metaphor-cli の擬似ホットリロード（ライブビューア）を維持。
- **クロスリポ契約**: CONTRACT 点5（`METAPHOR_VIEWER=1` ヘッドレスで `METAPHOR_SYPHON_NAME` のサーバーへ
  publish）を壊さないこと。
- **SwiftPM 制約**: 分離後 Core は Syphon を参照しないため、出力ファクトリを「いつ誰が登録するか」が核心。
  静的リンクで参照されないオブジェクトの `+load`/`__attribute__((constructor))` は dead-strip され得る。
  `-force_load`/`-ObjC` は `linkerSettings(.unsafeFlags(...))` 必須で、これは **metaphor を版指定の依存として
  使えなくする**副作用があり採用不可。

## Considered Options

### Option A: 出力プラグイン登録レジストリ + C コンストラクタによる自動登録（採用）
- Core に `MetaphorOutputRegistry`（Syphon 非参照）を置き、`MetaphorSyphon` が C の
  `__attribute__((constructor))` → `@_cdecl` Swift 関数でロード時にファクトリを登録。
- Pros: `import metaphor` 利用者・metaphor-cli は**無改修・体験不変**。`unsafeFlags` 不要。性能不変。
- Cons: C companion ターゲットが必要。自動登録は「該当オブジェクトがリンクされること」に依存（spike で検証）。

### Option B: アンブレラの保証実行点から明示 bootstrap
- `metaphor` アンブレラのどこかで `MetaphorSyphon.enable()` を呼ぶ。
- Pros: マジックが少ない。
- Cons: アンブレラはコードを持たず（`@_exported import` のみ）、エントリ `Sketch.main()` は Core 側にあるため、
  **保証された実行点が存在しない**。実質成立しない。

### Option C: 明示登録のみ（`import MetaphorSyphon` + `enable()` を利用者が呼ぶ）
- Pros: 最も単純・確実。
- Cons: 透明性が崩れ、examples/metaphor-cli/CONTRACT の同時改修が必要（クロスリポ破壊的変更）。不変条件②③に反する。

## Decision

**Option A** を採用。spike（最小 SwiftPM 再現: Core/CBootstrap/Plugin/Umbrella/executable）で
**debug・release × 同一パッケージ・クロスパッケージ依存の全4組合せ**で自動登録が走り、`unsafeFlags` 不要、
`MetaphorCore` 単体 import では登録されない（期待どおり）ことを確認した。Option C は明示 `enable()` として
フォールバック公開のみ残す。

## Consequences

### Positive
- `MetaphorCore` 単体は `Syphon` binaryTarget 非依存の純粋な描画コアになり、軽量ヘッドレス/AI Core や
  将来の platform 拡張の土台ができる。
- 出力バックエンド（NDI 等）を Core 非依存で追加できる拡張点（`MetaphorOutputRegistry`）が明確化。
- `import metaphor` 利用者・metaphor-cli は体験・性能・ホットリロードとも不変（透明分離）。

### Negative / Trade-offs
- 唯一の挙動差: `import MetaphorCore` を**直接**書く利用者は自動 Syphon が付かない（`import metaphor` か
  `import MetaphorSyphon`、または `MetaphorSyphon.enable()` で解決）。
- C companion ターゲット（`CMetaphorSyphonBootstrap`）という小さな構造的複雑さを導入。
- 自動登録は SwiftPM のリンク挙動に依存するため、将来 toolchain 変更時は spike の再確認が望ましい。

### Follow-ups / 残課題
- platform 拡張の本丸は Syphon ではなく **AppKit（特に `SketchRunner` の `NSApplication` ライフサイクル）**。
  本 ADR では扱わない（別途）。
- Syphon-free な真のヘッドレス（`CFRunLoop` + Probe 出力）は別施策。

## References
- `Sources/MetaphorCore/Core/MetaphorOutputRegistry.swift`（レジストリ）
- `Sources/MetaphorSyphon/`（`SyphonOutput` / `SyphonPlugin` / facade / `@_cdecl` 登録）
- `Sources/CMetaphorSyphonBootstrap/bootstrap.c`（C コンストラクタ）
- `Sources/MetaphorCore/Sketch/SketchRunner.swift`（`startOutput` 経由の自動配線）
- Issue #73、CONTRACT.md（点1・点5）
