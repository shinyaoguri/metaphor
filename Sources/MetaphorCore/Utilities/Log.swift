/// Internal diagnostic logging for metaphor.
///
/// Prints warnings only in DEBUG builds. Use this function instead of
/// bare `print()` for consistent formatting and easy suppression.
@usableFromInline
@inline(__always)
func metaphorWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[metaphor] Warning:", message())
    #endif
}
