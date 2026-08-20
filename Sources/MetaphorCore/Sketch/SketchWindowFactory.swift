import AppKit

/// スケッチが開くネイティブウィンドウ（プライマリ / セカンダリ）の唯一の生成口。
///
/// 生成を 1 箇所へ寄せているのは `NSWindow` の既定が
/// ``NSWindow/isReleasedWhenClosed`` = `true`（＝閉じたときに AppKit 自身が
/// `release` を送る MRR 時代の作法）で、metaphor 側の持ち方
/// （``SketchWindow`` / ``SketchRunner`` が Swift の強参照で保持する）と
/// 噛み合わないためです。既定のままだと閉じた時点で AppKit の release と ARC の
/// release が重なり、解放済みオブジェクトを触った瞬間に `SIGSEGV` になります
/// （セカンダリウィンドウを閉じて開き直すと落ちる #835）。ここを通す限り、
/// ウィンドウの寿命は常に ARC だけが決めます。
///
/// **画面に出すのは呼び出し側の責務です**（`makeKeyAndOrderFront(_:)` は呼びません）。
/// 生成と表示を分けておくと、テストから画面を汚さずに生成規約を検証できます。
@MainActor
enum SketchWindowFactory {

    /// スケッチ用の `NSWindow` を作ります（画面には出しません）。
    ///
    /// - Parameters:
    ///   - contentSize: コンテンツ領域のサイズ（ポイント）。
    ///   - title: タイトルバーに表示する文字列。
    ///   - aspectRatio: リサイズ時に保つ縦横比（通常はキャンバスのピクセル寸法）。
    /// - Returns: 画面に出していない `NSWindow`。寿命は呼び出し側の強参照が決めます。
    static func makeWindow(
        contentSize: NSSize,
        title: String,
        aspectRatio: NSSize
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 寿命は ARC 一本に統一する。既定（true）のままだと close() のたびに
        // AppKit が release を送り、呼び出し側の強参照が宙に浮く（#835）。
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentAspectRatio = aspectRatio
        window.center()
        return window
    }
}
