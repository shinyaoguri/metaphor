import Foundation

// metaphor の診断ログ。依存ゼロの最小ターゲットに置いてあります。
//
// `MetaphorCore` の中に置いていた頃は internal だったため、アンブレラ
// （`Sources/metaphor/`）や Core 非依存の Tier 1 モジュールからは物理的に呼べず、
// 同種の入口ガードでも `print("[metaphor] Warning: …")` の直書きに割れていました
// （Issue #805）。Tier 1 からも使えるようにするには「Core より下」に置くしかないため、
// 依存を一切持たない `MetaphorLog` ターゲットへ切り出しています。
// `MetaphorCore` が `@_exported import` で再輸出するので、
// `import metaphor` / `import MetaphorCore` の利用者から見える名前は従来どおりです。
//
// ## どれを使うか
//
// | 関数 | 出力先 | 出るビルド | 使いどころ |
// |---|---|---|---|
// | ``metaphorWarning(_:)`` | stdout | DEBUG のみ | **ユーザーのコードが誤っている**。入口ガードで値を弾いた・丸めた |
// | ``metaphorAlert(_:)`` | stderr | 常に | **ユーザーのコードは正しいのに環境の都合で黙って動かない** |
// | ``metaphorDiagnostic(_:)`` | stderr | `METAPHOR_DEBUG=1` のときだけ | 無視してよいが**切り分けたい**内部イベント |
//
// 迷ったら ``metaphorWarning(_:)``。ライブラリの入口で不正な引数を弾いたときの警告は
// ほぼ全てこれに当たります（開発中に気付けばよく、Release の stdout を汚さない）。
//
// ``metaphorAlert(_:)`` は「Release の `.app` でしか出ない症状」専用の逃げ道です
// （例: カメラ / マイクの権限が `.notDetermined` のまま入力が 1 つも来ない。素の実行
// ファイルには TCC ダイアログが出ないため原因が観測できない・Issue #685）。
// DEBUG 限定の ``metaphorWarning(_:)`` も `METAPHOR_DEBUG=1` 限定の
// ``metaphorDiagnostic(_:)`` も、まさにその形態では沈黙してしまうため。
//
// ``metaphorDiagnostic(_:)`` はクロスリポ契約（stdin 入力イベント / Probe の
// `request.json`）のデコード失敗のように、**本来は黙って捨ててよいが**「なぜ反映され
// ないのか」を切り分けたいときに使います。
//
// stdout はライブラリの出力チャネル（metaphor-cli との JSON Lines）と共有しているので、
// **Release でも出るものは必ず stderr へ書きます**。素の `print()` は使わないでください。
//
// この規約は文章だけでは守られませんでした（#805 で明文化したあとも `Sources/` には
// 生の `print()` が 19 箇所残っていた・Issue #896）。いまは
// `scripts/check-no-raw-print.py` が CI で `Sources/` の生 `print(` を落とします。
// 正当な例外はそのスクリプトの `ALLOWLIST` に理由つきで載せてください。

/// 開発者向けの警告（stdout、**DEBUG ビルドのみ**）。
///
/// ユーザーのコードが誤っている（不正な引数を入口ガードで弾いた・丸めた）ときに使います。
/// Release ビルドでは本体ごと消えるため、`metaphor` の出力チャネルを汚しません。
///
/// 一貫したフォーマットと容易な抑制のため、素の `print()` の代わりにこの関数を使用してください。
///
/// - Parameter message: 警告本文（`[metaphor] Warning: ` が前置されます）。
@inlinable
@inline(__always)
public func metaphorWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[metaphor] Warning:", message())
    #endif
}

/// **Release ビルドでも必ず** stderr に出す警告。
///
/// 「ユーザーのコードは正しいのに、環境の都合で黙って動かない」条件だけに使います
/// （例: カメラ / マイクの権限が `.notDetermined` のまま入力が 1 つも来ない。
/// 素の実行ファイルには TCC ダイアログが出ないため、原因が観測できない・Issue #685）。
///
/// ``metaphorWarning(_:)`` は DEBUG 限定、``metaphorDiagnostic(_:)`` は `METAPHOR_DEBUG=1`
/// 限定なので、**Release の `.app`** という「まさにその症状が出る形態」では
/// どちらも沈黙してしまいます。stdout を汚さないよう必ず stderr に書きます。
///
/// - Parameter message: 警告本文（`[metaphor] Warning: ` が前置されます）。
public func metaphorAlert(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write("[metaphor] Warning: \(message())\n".data(using: .utf8)!)
}

/// `METAPHOR_DEBUG=1` が設定されているか（プロセス起動時に 1 度だけ評価）。
private let metaphorDebugEnabled: Bool =
    ProcessInfo.processInfo.environment["METAPHOR_DEBUG"] == "1"

/// ランタイムゲート付きの診断ログ（stderr）。
///
/// ``metaphorWarning(_:)`` と異なり **Release ビルドでも** 出力できます。ただし既定では
/// 沈黙し、`METAPHOR_DEBUG=1` のときだけ stderr に出します。クロスリポ契約
/// （stdin 入力イベント / Probe の `request.json`）のデコード失敗など、本来は無視で
/// 良いが「なぜ反映されないのか」を切り分けたいときの観測性のために使います。
/// stdout を汚さないため必ず stderr に書きます（MCP の JSON-RPC や Syphon 出力に
/// 干渉しない）。
///
/// - Parameter message: 診断本文（`[metaphor] ` が前置されます）。
public func metaphorDiagnostic(_ message: @autoclosure () -> String) {
    guard metaphorDebugEnabled else { return }
    FileHandle.standardError.write("[metaphor] \(message())\n".data(using: .utf8)!)
}
