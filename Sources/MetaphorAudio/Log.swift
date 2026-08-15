@usableFromInline
@inline(__always)
func debugWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[MetaphorAudio] Warning:", message())
    #endif
}

import Foundation

/// **Release ビルドでも必ず** stderr に出す警告。
///
/// 「ユーザーのコードは正しいのに、環境の都合で黙って動かない」条件だけに使います
/// （マイク権限が `.notDetermined` のままサンプルが 1 つも来ない等・Issue #685）。
/// `debugWarning` は DEBUG 限定なので、Release の `.app` では沈黙してしまいます。
/// stdout を汚さないよう必ず stderr に書きます。
func audioAlert(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write("[MetaphorAudio] Warning: \(message())\n".data(using: .utf8)!)
}
