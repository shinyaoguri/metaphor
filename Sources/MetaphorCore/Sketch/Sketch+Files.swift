import AppKit

// MARK: - File Dialogs (selectInput / selectOutput)

/// ライブビューア用の headless 実行（`METAPHOR_VIEWER=1`）かどうか。
/// headless ではダイアログを表示できないため no-op + warning にする。
private var isViewerHeadless: Bool {
    ProcessInfo.processInfo.environment["METAPHOR_VIEWER"] == "1"
}

extension Sketch {

    /// ファイルを開くダイアログを表示します（Processing の `selectInput()` 互換）。
    ///
    /// 非ブロッキングで、ユーザーの選択後にコールバックが呼ばれます。
    /// headless モード（`METAPHOR_VIEWER=1`）ではダイアログを出さず、
    /// 警告を出力して `nil` で即コールバックします。
    ///
    /// ```swift
    /// selectInput("画像を選択") { path in
    ///     guard let path else { return }  // キャンセル時は nil
    ///     self.img = try? self.loadImage(path)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: ダイアログに表示するメッセージ。
    ///   - callback: 選択されたファイルの絶対パス（キャンセル時は `nil`）を受け取るクロージャ。
    public func selectInput(
        _ prompt: String = "Select a file",
        _ callback: @escaping @MainActor (String?) -> Void
    ) {
        guard !isViewerHeadless else {
            metaphorWarning("selectInput: headless mode (METAPHOR_VIEWER=1) cannot show dialogs")
            callback(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            let path = response == .OK ? panel.url?.path : nil
            Task { @MainActor in callback(path) }
        }
    }

    /// ファイルを保存するダイアログを表示します（Processing の `selectOutput()` 互換）。
    ///
    /// 非ブロッキングで、ユーザーの決定後にコールバックが呼ばれます。
    /// headless モード（`METAPHOR_VIEWER=1`）ではダイアログを出さず、
    /// 警告を出力して `nil` で即コールバックします。
    ///
    /// - Parameters:
    ///   - prompt: ダイアログに表示するメッセージ。
    ///   - callback: 保存先の絶対パス（キャンセル時は `nil`）を受け取るクロージャ。
    public func selectOutput(
        _ prompt: String = "Save as",
        _ callback: @escaping @MainActor (String?) -> Void
    ) {
        guard !isViewerHeadless else {
            metaphorWarning("selectOutput: headless mode (METAPHOR_VIEWER=1) cannot show dialogs")
            callback(nil)
            return
        }
        let panel = NSSavePanel()
        panel.message = prompt
        panel.begin { response in
            let path = response == .OK ? panel.url?.path : nil
            Task { @MainActor in callback(path) }
        }
    }
}
