@usableFromInline
@inline(__always)
func debugWarning(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[MetaphorVideo] Warning:", message())
    #endif
}
