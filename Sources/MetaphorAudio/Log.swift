@usableFromInline
@inline(__always)
func debugWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
        print("[MetaphorAudio] Warning:", message())
    #endif
}

import Foundation

/// Writes a warning to stderr **in release builds as well**.
///
/// Use this only for conditions where the user's code is correct but the
/// environment silently prevents it from working — for example, microphone
/// access left at `.notDetermined` so not a single sample ever arrives
/// (Issue #685). `debugWarning` is DEBUG-only and stays silent in a release
/// `.app`. Always writes to stderr so that stdout stays clean.
func audioAlert(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write("[MetaphorAudio] Warning: \(message())\n".data(using: .utf8)!)
}
