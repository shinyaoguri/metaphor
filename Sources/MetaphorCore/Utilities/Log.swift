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
