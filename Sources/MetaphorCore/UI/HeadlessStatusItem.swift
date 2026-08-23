import AppKit

/// ヘッドレス実行中のプロセスの「いまの状態」（メニュー表示用のスナップショット）。
///
/// メニューを開いた瞬間に組み立て、そのまま文字列へ落とします。値の取得元は
/// 画面表示・Probe・``Sketch/performance`` と同じ（``FrameRateTracker``）なので、
/// メニューに出る実測 fps は他の観測手段と一致します。
struct HeadlessStatusSnapshot {
    /// スケッチ名（``SketchConfig/title``）。
    var title: String
    /// 実行中の metaphor のバージョン。
    var version: String
    /// プロセス ID。
    var pid: Int32
    /// オフスクリーンテクスチャの幅。
    var width: Int
    /// オフスクリーンテクスチャの高さ。
    var height: Int
    /// 目標フレームレート。
    var targetFPS: Int
    /// 直近ウィンドウの実測フレームレート。算出に足るフレームが無ければ `nil`。
    var measuredFPS: Double?
    /// 描画したフレーム数。
    var frameCount: Int
    /// 指標を出してからの経過秒数。
    var elapsed: TimeInterval
    /// 表示用に整形済みの出力先（``outputLabel(pluginID:viewerConnected:)`` の結果）。
    var outputs: [String]
}

extension HeadlessStatusSnapshot {
    /// メニューに並べる情報行を組み立てます（純関数・テスト対象）。
    ///
    /// - Returns: 1 行 1 項目の文字列。スケッチ名は含みません（呼び出し側が見出しに使う）。
    static func menuLines(_ s: HeadlessStatusSnapshot) -> [String] {
        [
            "metaphor \(s.version) · headless · PID \(s.pid)",
            "\(s.width)×\(s.height) @ \(s.targetFPS) fps (measured \(measuredText(s.measuredFPS)))",
            "frame \(s.frameCount) · \(elapsedText(s.elapsed)) elapsed",
            outputsText(s.outputs),
        ]
    }

    /// 実測 fps の表示。算出不能なときは `0` ではなく `--`
    /// （``PerformanceHUD`` と同じ理由 — `noLoop()` の作品で `0` と出すと誤情報になる）。
    static func measuredText(_ fps: Double?) -> String {
        guard let fps else { return "--" }
        return String(format: "%.1f", fps)
    }

    /// 経過時間の表示（`MM:SS`、1 時間を超えたら `H:MM:SS`）。
    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = Int(max(elapsed, 0))
        let (h, m, sec) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    /// 出力先の行。1 つも無い状態＝誰もフレームを見ていない状態なので、そう明示します
    /// （孤児になったヘッドレスプロセスを、メニューを開くだけで見分けられるようにする）。
    static func outputsText(_ outputs: [String]) -> String {
        guard !outputs.isEmpty else { return "Output: none — nobody is watching these frames" }
        return "Output: " + outputs.joined(separator: ", ")
    }

    /// 出力プラグインの識別子を人が読める名前へ変換します（純関数・テスト対象）。
    ///
    /// ライブビューアだけは接続状態まで出します（親が落ちても子は回り続けるため、
    /// 「繋がっていたが切れた」を区別できることに意味があります）。外部モジュールの
    /// 出力（metaphor-syphon 等）は識別子から慣習的な接頭辞・接尾辞を落として出します。
    ///
    /// - Parameters:
    ///   - pluginID: 出力プラグインの識別子。
    ///   - viewerConnected: ライブビューアの接続状態（ビューア以外では無視）。
    static func outputLabel(pluginID: String, viewerConnected: Bool?) -> String {
        if pluginID == ViewerOutputPlugin.id {
            let state = (viewerConnected ?? false) ? "connected" : "disconnected"
            return "live viewer (\(state))"
        }
        var name = pluginID
        if let dot = name.range(of: "org.metaphor.") {
            name = String(name[dot.upperBound...])
        }
        if name.hasSuffix("-output") {
            name = String(name.dropLast("-output".count))
        }
        return name.isEmpty ? pluginID : name
    }
}

/// ヘッドレス実行中であることをメニューバーに出す状態項目。
///
/// ``HeadlessIndicator/menuBar`` / ``HeadlessIndicator/both`` のときだけ
/// ``SketchRunner`` が生成し、終了時に取り外します。中身はメニューを開いた瞬間に
/// 組み立てるので、開いていない間のコストはゼロです。
@MainActor
final class HeadlessStatusItem: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let snapshotProvider: () -> HeadlessStatusSnapshot
    private let onQuit: () -> Void

    /// 状態項目をメニューバーへ出します。
    ///
    /// ウィンドウサーバのセッションを持たない環境（CI 等）では項目のボタンが得られない
    /// ことがあります。その場合は生成に失敗して `nil` を返し、スケッチの実行は続けます
    /// （表示のために描画を止めない）。
    ///
    /// - Parameters:
    ///   - snapshotProvider: メニューを開いたときに現在値を返すクロージャ。
    ///   - onQuit: 「Quit」が選ばれたときの処理。
    init?(
        snapshotProvider: @escaping () -> HeadlessStatusSnapshot,
        onQuit: @escaping () -> Void
    ) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            metaphorDiagnostic("headless indicator: no status bar button available; skipping")
            return nil
        }
        self.statusItem = item
        self.snapshotProvider = snapshotProvider
        self.onQuit = onQuit
        super.init()

        if let image = NSImage(
            systemSymbolName: "rectangle.dashed", accessibilityDescription: "metaphor (headless)"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            // SF Symbol が引けない環境でも「何かある」ことは分かるようにする。
            button.title = "◌"
        }
        let snapshot = snapshotProvider()
        button.toolTip = "\(snapshot.title) — metaphor (headless, PID \(snapshot.pid))"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// 状態項目をメニューバーから取り外します（終了時の後始末）。
    func remove() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - NSMenuDelegate

    /// メニューが開かれる直前に中身を作り直します（常時ポーリングしない）。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let snapshot = snapshotProvider()
        menu.removeAllItems()

        let header = NSMenuItem(title: snapshot.title, action: nil, keyEquivalent: "")
        menu.addItem(header)

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        for line in HeadlessStatusSnapshot.menuLines(snapshot) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: line, attributes: [.font: font])
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit \(snapshot.title)", action: #selector(quitSelected), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func quitSelected() {
        onQuit()
    }
}
