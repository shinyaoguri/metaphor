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
