import AppKit

/// The current state of a headless process — a snapshot for display in the menu.
///
/// Built the moment the menu opens and turned straight into strings. The values
/// come from the same source as the on-screen display, Probe and
/// ``Sketch/performance`` (``FrameRateTracker``), so the measured fps shown in
/// the menu agrees with every other way of observing it.
struct HeadlessStatusSnapshot {
    /// The sketch name (``SketchConfig/title``).
    var title: String
    /// The version of metaphor that is running.
    var version: String
    /// The process ID.
    var pid: Int32
    /// The width of the offscreen texture.
    var width: Int
    /// The height of the offscreen texture.
    var height: Int
    /// The target frame rate.
    var targetFPS: Int
    /// The measured frame rate over the recent window, or `nil` without enough frames to compute it.
    var measuredFPS: Double?
    /// The number of frames drawn.
    var frameCount: Int
    /// Seconds elapsed since the metrics started.
    var elapsed: TimeInterval
    /// The outputs, already formatted for display (the result of ``outputLabel(pluginID:viewerConnected:)``).
    var outputs: [String]
}

extension HeadlessStatusSnapshot {
    /// Builds the information rows shown in the menu (a pure function, covered by tests).
    ///
    /// - Returns: One string per item. The sketch name is not included — the caller uses it as the heading.
    static func menuLines(_ s: HeadlessStatusSnapshot) -> [String] {
        [
            "metaphor \(s.version) · headless · PID \(s.pid)",
            "\(s.width)×\(s.height) @ \(s.targetFPS) fps (measured \(measuredText(s.measuredFPS)))",
            "frame \(s.frameCount) · \(elapsedText(s.elapsed)) elapsed",
            outputsText(s.outputs),
        ]
    }

    /// The measured fps, shown as `--` rather than `0` when it cannot be computed
    /// (the same reason as ``PerformanceHUD`` — printing `0` for a `noLoop()` piece would be misinformation).
    static func measuredText(_ fps: Double?) -> String {
        guard let fps else { return "--" }
        return String(format: "%.1f", fps)
    }

    /// The elapsed time, as `MM:SS` (or `H:MM:SS` past an hour).
    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = Int(max(elapsed, 0))
        let (h, m, sec) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    /// The output rows. Having none means nobody is watching the frames, and that
    /// is stated explicitly — so an orphaned headless process can be spotted just by opening the menu.
    static func outputsText(_ outputs: [String]) -> String {
        guard !outputs.isEmpty else { return "Output: none — nobody is watching these frames" }
        return "Output: " + outputs.joined(separator: ", ")
    }

    /// Converts an output plugin identifier into a human-readable name (a pure function, covered by tests).
    ///
    /// The live viewer is the one output whose connection state is also shown: a
    /// child keeps running when its parent dies, so telling "was connected, now
    /// disconnected" apart is worth something. Outputs from external modules
    /// (metaphor-syphon and friends) are shown with the conventional prefix and
    /// suffix stripped from the identifier.
    ///
    /// - Parameters:
    ///   - pluginID: The output plugin identifier.
    ///   - viewerConnected: The live viewer's connection state (ignored for other outputs).
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

/// The status item that shows a headless run in the menu bar.
///
/// ``SketchRunner`` creates it only for ``HeadlessIndicator/menuBar`` and
/// ``HeadlessIndicator/both``, and removes it on exit. The contents are built the
/// moment the menu opens and refreshed at ``refreshFPS`` only while it stays
/// open, so the cost while closed is zero (frame capture runs for the same
/// window of time).
@MainActor
final class HeadlessStatusItem: NSObject, NSMenuDelegate {
    /// The refresh rate while the menu is open, for both the numbers and the preview.
    private static let refreshFPS = 8.0

    private let statusItem: NSStatusItem
    private let snapshotProvider: () -> HeadlessStatusSnapshot
    private let previewProvider: (() -> CGImage?)?
    private let setPreviewActive: ((Bool) -> Void)?
    private let previewSize: NSSize
    private let onQuit: () -> Void

    private var infoItems: [NSMenuItem] = []
    private var previewView: HeadlessPreviewView?
    private var refreshTimer: Timer?

    /// Puts the status item into the menu bar.
    ///
    /// In environments without a window server session (CI, for instance) the
    /// item's button may be unavailable. Creation then fails and returns `nil`
    /// while the sketch keeps running — drawing is never stopped for the sake of display.
    ///
    /// - Parameters:
    ///   - snapshotProvider: A closure returning the current values when the menu opens.
    ///   - previewProvider: A closure returning the most recent frame (`nil` shows no preview).
    ///   - previewSize: The preview size, in points.
    ///   - setPreviewActive: A closure that starts and stops frame capture for the preview.
    ///   - onQuit: What to do when "Quit" is chosen.
    init?(
        snapshotProvider: @escaping () -> HeadlessStatusSnapshot,
        previewProvider: (() -> CGImage?)? = nil,
        previewSize: NSSize = .zero,
        setPreviewActive: ((Bool) -> Void)? = nil,
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
        self.previewProvider = previewProvider
        self.previewSize = previewSize
        self.setPreviewActive = setPreviewActive
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

    /// Removes the status item from the menu bar (cleanup on exit).
    func remove() {
        stopRefreshing()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the contents just before the menu opens, instead of polling continuously.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let snapshot = snapshotProvider()
        menu.removeAllItems()
        infoItems.removeAll()
        previewView = nil

        menu.addItem(NSMenuItem(title: snapshot.title, action: nil, keyEquivalent: ""))

        if previewProvider != nil, previewSize.width > 0, previewSize.height > 0 {
            let view = HeadlessPreviewView(previewSize: previewSize)
            view.image = previewProvider?()
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
            previewView = view
        }

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        for line in HeadlessStatusSnapshot.menuLines(snapshot) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: line, attributes: [.font: font])
            menu.addItem(item)
            infoItems.append(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit \(snapshot.title)", action: #selector(quitSelected), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    /// Keeps refreshing the numbers and the preview, but only while the menu is open.
    func menuWillOpen(_ menu: NSMenu) {
        setPreviewActive?(true)
        // メニュー追跡中の run loop は `.eventTracking` なので、`.common` で登録しないと
        // 開いている間だけ止まってしまう（＝いちばん動いてほしいときに動かない）。
        let timer = Timer(timeInterval: 1.0 / Self.refreshFPS, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        stopRefreshing()
    }

    // MARK: - Helpers

    /// Replaces the numbers and the preview in the open menu.
    private func refresh() {
        let snapshot = snapshotProvider()
        let lines = HeadlessStatusSnapshot.menuLines(snapshot)
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        for (item, line) in zip(infoItems, lines) {
            item.attributedTitle = NSAttributedString(string: line, attributes: [.font: font])
        }
        previewView?.image = previewProvider?()
    }

    /// Stops refreshing, and stops frame capture for the preview as well.
    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        setPreviewActive?(false)
    }

    @objc private func quitSelected() {
        onQuit()
    }
}

/// The preview placed inside the menu — the latest frame, clipped to rounded corners.
///
/// Until a frame has been captured it draws only a faint backing. A sketch halted
/// by `noLoop()` draws no new frames, so it stays at that backing.
@MainActor
final class HeadlessPreviewView: NSView {
    /// The picture to show. `nil` draws the backing only.
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    private static let margin: CGFloat = 14
    private static let cornerRadius: CGFloat = 4

    init(previewSize: NSSize) {
        super.init(
            frame: NSRect(
                x: 0, y: 0,
                width: previewSize.width + Self.margin * 2,
                height: previewSize.height + Self.margin
            ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = NSRect(
            x: Self.margin,
            y: Self.margin / 2,
            width: bounds.width - Self.margin * 2,
            height: bounds.height - Self.margin
        )
        let path = NSBezierPath(
            roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()

        guard let image else { return }
        context.saveGState()
        path.addClip()
        // 実行中に解像度が変わっても潰さないよう、絵の側の比率で内接させる。
        context.draw(
            image,
            in: Self.aspectFit(
                imageWidth: image.width, imageHeight: image.height, into: rect
            ))
        context.restoreGState()
    }

    /// Fits the picture inside `rect` while preserving its aspect ratio (a pure function, covered by tests).
    static func aspectFit(imageWidth: Int, imageHeight: Int, into rect: NSRect) -> NSRect {
        guard imageWidth > 0, imageHeight > 0 else { return rect }
        let scale = min(rect.width / CGFloat(imageWidth), rect.height / CGFloat(imageHeight))
        let size = NSSize(width: CGFloat(imageWidth) * scale, height: CGFloat(imageHeight) * scale)
        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
