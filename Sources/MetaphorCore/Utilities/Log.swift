import Foundation

/// metaphor の内部診断ログ。
///
/// DEBUG ビルドでのみ警告を出力します。一貫したフォーマットと
/// 容易な抑制のため、素の `print()` の代わりにこの関数を使用してください。
@usableFromInline
@inline(__always)
func metaphorWarning(_ message: @autoclosure () -> String) {
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
/// ``metaphorWarning`` は DEBUG 限定、``metaphorDiagnostic`` は `METAPHOR_DEBUG=1`
/// 限定なので、**Release の `.app`** という「まさにその症状が出る形態」では
/// どちらも沈黙してしまいます。stdout を汚さないよう必ず stderr に書きます。
func metaphorAlert(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write("[metaphor] Warning: \(message())\n".data(using: .utf8)!)
}

/// `METAPHOR_DEBUG=1` が設定されているか（プロセス起動時に 1 度だけ評価）。
private let metaphorDebugEnabled: Bool =
    ProcessInfo.processInfo.environment["METAPHOR_DEBUG"] == "1"

/// ランタイムゲート付きの診断ログ（stderr）。
///
/// `metaphorWarning` と異なり **Release ビルドでも** 出力できます。ただし既定では
/// 沈黙し、`METAPHOR_DEBUG=1` のときだけ stderr に出します。クロスリポ契約
/// （stdin 入力イベント / Probe の `request.json`）のデコード失敗など、本来は無視で
/// 良いが「なぜ反映されないのか」を切り分けたいときの観測性のために使います。
/// stdout を汚さないため必ず stderr に書きます（MCP の JSON-RPC や Syphon 出力に
/// 干渉しない）。
func metaphorDiagnostic(_ message: @autoclosure () -> String) {
    guard metaphorDebugEnabled else { return }
    FileHandle.standardError.write("[metaphor] \(message())\n".data(using: .utf8)!)
}
