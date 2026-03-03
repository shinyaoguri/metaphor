@usableFromInline
@inline(__always)
func debugWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[MetaphorNetwork] Warning:", message())
    #endif
}
