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
    /// Where this process lives (the base directory for `.metaphor/`).
    ///
    /// When several sketches of the same name are running, this is the only way
    /// to tell them apart.
    var location: String
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
    /// The sketch name and the location are not included — the caller uses them as
    /// the heading. What remains is exactly the set of values replaced at 8fps
    /// while the menu is open, kept one-to-one with the rows being replaced.
    ///
    /// - Returns: One string per item.
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

    /// The location row (a pure function, covered by tests).
    ///
    /// Paths under the home directory are folded to `~`. A `.app` launched through
    /// LaunchServices runs with `/` as its working directory (when
    /// `METAPHOR_STATE_DIR` is unset — see "the base directory for `.metaphor/`" in
    /// CONTRACT.md), and that case says as much: a bare `/` would read as if the
    /// sketch lived there.
    ///
    /// A long path is shortened from the front, because the tail is the part that
    /// tells two runs apart — and because this row would otherwise set the lower
    /// bound on the menu's width. The whole path stays available as the row's tooltip.
    ///
    /// - Parameters:
    ///   - path: The base directory the process is running in.
    ///   - maxLength: The length past which leading components are dropped.
    static func locationText(_ path: String, maxLength: Int = 48) -> String {
        guard path != "/" else { return "/ (no project directory)" }
        let abbreviated = NSString(string: path).abbreviatingWithTildeInPath
        guard abbreviated.count > maxLength else { return abbreviated }

        var components = abbreviated.split(separator: "/", omittingEmptySubsequences: false)
        while components.count > 1 {
            components.removeFirst()
            let candidate = "…/" + components.joined(separator: "/")
            if candidate.count <= maxLength { return candidate }
        }
        return "…/" + (components.last.map(String.init) ?? abbreviated)
    }

    /// The row stating where a saved frame went (a pure function, covered by tests).
    ///
    /// A destination inside the location is written relative to it: the absolute
    /// path would repeat the location shown just above, and that single row would
    /// set the lower bound on the menu's width. The whole path is shown only when
    /// the frame had to go elsewhere (`~/Desktop`).
    ///
    /// - Parameters:
    ///   - path: The absolute path the frame was written to.
    ///   - base: Where the process lives (``HeadlessStatusSnapshot/location``).
    static func savedText(path: String, base: String) -> String {
        // 基準が `/`（プロジェクトの外）のときに相対化すると、先頭の `/` が落ちた
        // 絶対パスになってしまう。そこは「場所」として意味を持たないので畳まない。
        let prefix = base.hasSuffix("/") ? base : base + "/"
        if prefix != "/", path.hasPrefix(prefix) {
            return "Saved to " + String(path.dropFirst(prefix.count))
        }
        return "Saved to " + NSString(string: path).abbreviatingWithTildeInPath
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

/// The status item that makes a headless process findable when nobody is watching it.
///
/// ``SketchRunner`` creates it only for ``HeadlessIndicator/menuBar`` and
/// ``HeadlessIndicator/both``, and removes it on exit.
///
/// This is not an always-on HUD. While the live viewer (`metaphor watch`) is
/// attached it stays out of the menu bar — the parent window already shows the
/// same picture and the same numbers — and it appears the moment nobody is
/// watching any more, so **its very presence means "this process is unobserved"**.
///
/// The contents are built the moment the menu opens and refreshed at ``refreshFPS``
/// only while it stays open, so the cost while closed is zero (frame capture runs
/// for the same window of time).
@MainActor
final class HeadlessStatusItem: NSObject, NSMenuDelegate {
    /// The refresh rate while the menu is open, for both the numbers and the preview.
    private static let refreshFPS = 8.0

    /// How often to re-check for an observer while the item is hidden, in seconds.
    ///
    /// Nothing runs while the item is visible — once it is out, there is nothing more to show.
    private static let visibilityPollInterval = 1.0

    private let statusItem: NSStatusItem
    private let snapshotProvider: () -> HeadlessStatusSnapshot
    private let previewProvider: (() -> CGImage?)?
    private let setPreviewActive: ((Bool) -> Void)?
    private let previewSize: NSSize
    /// Returns whether this surface should be shown (`nil` always shows it).
    private let visibilityProvider: (() -> Bool)?
    /// Saves one frame, returning where it went, or `nil` when it could not be saved.
    private let onSaveFrame: (() -> String?)?
    private let onQuit: () -> Void

    private var infoItems: [NSMenuItem] = []
    private var previewView: HeadlessPreviewView?
    private var refreshTimer: Timer?
    private var visibilityTimer: Timer?
    /// Where the most recently saved frame went, kept so the menu can say so.
    private var lastSavedPath: String?

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
    ///   - visibilityProvider: A closure returning whether this surface should be shown
    ///     (the result of ``shouldShow(viewerSocketConfigured:viewerConnected:)``).
    ///   - onSaveFrame: A closure saving one frame, returning where it went, or `nil` on failure.
    ///   - onQuit: What to do when "Quit" is chosen.
    init?(
        snapshotProvider: @escaping () -> HeadlessStatusSnapshot,
        previewProvider: (() -> CGImage?)? = nil,
        previewSize: NSSize = .zero,
        setPreviewActive: ((Bool) -> Void)? = nil,
        visibilityProvider: (() -> Bool)? = nil,
        onSaveFrame: (() -> String?)? = nil,
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
        self.visibilityProvider = visibilityProvider
        self.onSaveFrame = onSaveFrame
        self.onQuit = onQuit
        super.init()

        let snapshot = snapshotProvider()
        // VoiceOver からも、複数走っているうちのどれかが分かるようにスケッチ名を入れる。
        if let image = NSImage(
            systemSymbolName: "rectangle.dashed",
            accessibilityDescription: "\(snapshot.title) — metaphor (headless)"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            // SF Symbol が引けない環境でも「何かある」ことは分かるようにする。
            button.title = "◌"
        }
        button.toolTip = "\(snapshot.title) — metaphor (headless, PID \(snapshot.pid))"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        updateVisibility()
    }

    /// Removes the status item from the menu bar (cleanup on exit).
    func remove() {
        stopRefreshing()
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Whether this surface should be shown (a pure function, covered by tests).
    ///
    /// While the live viewer is attached it stays out of the way: the parent window
    /// is already showing the same picture and the same numbers. Runs where no
    /// socket was requested (`metaphor mcp`, `run --syphon`, a plain headless
    /// launch) have no parent window, so it is always shown.
    ///
    /// - Parameters:
    ///   - viewerSocketConfigured: Whether `METAPHOR_VIEWER_SOCKET` was given.
    ///   - viewerConnected: Whether the live viewer is attached.
    nonisolated static func shouldShow(
        viewerSocketConfigured: Bool, viewerConnected: Bool
    ) -> Bool {
        !(viewerSocketConfigured && viewerConnected)
    }

    /// Decides where a saved frame goes (a pure function, covered by tests).
    ///
    /// The first choice is `output/` under the base directory (`METAPHOR_STATE_DIR`
    /// or the working directory) — the same place and the same name as
    /// ``Sketch/save()``. **When that directory cannot be written to, the frame
    /// goes to `~/Desktop` instead**: a `.app` launched through LaunchServices has
    /// `/` as its base, and saving nothing without saying so is the worst outcome.
    ///
    /// - Parameters:
    ///   - base: The base directory for `.metaphor/` (``MetaphorPaths/baseDirectory``).
    ///   - timestamp: The stamp used in the file name (``MetaphorOutputPaths/timestamp(_:)``).
    ///   - isWritable: Whether the given directory can be written to (injectable for tests).
    /// - Returns: The absolute path to save to.
    nonisolated static func saveDestination(
        base: String,
        timestamp: String,
        isWritable: (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }
    ) -> String {
        if isWritable(base) {
            return MetaphorOutputPaths.timestampedScreenshot(timestamp: timestamp, base: base)
        }
        let desktop = NSString(string: "~/Desktop").expandingTildeInPath
        return MetaphorPaths.resolve("metaphor_\(timestamp).png", base: desktop)
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the contents just before the menu opens, instead of polling continuously.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let snapshot = snapshotProvider()
        menu.removeAllItems()
        infoItems.removeAll()
        previewView = nil

        // 見出し（スケッチ名）と、その従属としての場所。「このプロセスは何か」の答えを
        // 最初の 2 行に置き、以下の数値はそれに従属させる。
        menu.addItem(styledItem(snapshot.title, attributes: Self.headingAttributes))
        let location = styledItem(
            HeadlessStatusSnapshot.locationText(snapshot.location),
            attributes: Self.secondaryAttributes)
        location.toolTip = snapshot.location
        menu.addItem(location)

        if previewProvider != nil, previewSize.width > 0, previewSize.height > 0 {
            let view = HeadlessPreviewView(previewSize: previewSize, sketchTitle: snapshot.title)
            view.image = previewProvider?()
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
            previewView = view
        }

        for line in HeadlessStatusSnapshot.menuLines(snapshot) {
            let item = styledItem(line, attributes: Self.infoAttributes)
            menu.addItem(item)
            infoItems.append(item)
        }

        if let lastSavedPath {
            let item = styledItem(
                HeadlessStatusSnapshot.savedText(path: lastSavedPath, base: snapshot.location),
                attributes: Self.secondaryAttributes)
            item.toolTip = lastSavedPath
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if onSaveFrame != nil {
            let save = NSMenuItem(
                title: "Save Frame", action: #selector(saveFrameSelected), keyEquivalent: "s"
            )
            save.target = self
            menu.addItem(save)
        }
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

    private static let headingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: NSColor.labelColor,
    ]

    private static let secondaryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    private static let infoAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    /// Builds a row that is there to be read, not chosen.
    private func styledItem(
        _ text: String, attributes: [NSAttributedString.Key: Any]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: attributes)
        return item
    }

    /// Replaces the numbers and the preview in the open menu.
    private func refresh() {
        let lines = HeadlessStatusSnapshot.menuLines(snapshotProvider())
        for (item, line) in zip(infoItems, lines) {
            item.attributedTitle = NSAttributedString(
                string: line, attributes: Self.infoAttributes)
        }
        previewView?.image = previewProvider?()
    }

    /// Stops refreshing, and stops frame capture for the preview as well.
    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        setPreviewActive?(false)
    }

    /// Re-checks whether anyone is watching, and shows or hides the item accordingly.
    ///
    /// The check keeps running at a low rate, but only while the item is hidden. It
    /// does not rely on an event announcing the disconnection: a `noLoop()` sketch
    /// draws no frames and so never reaches the point where it would notice — it
    /// can be orphaned in silence. Stopping the timer once the item is visible keeps
    /// this off the permanent cost.
    private func updateVisibility() {
        guard let visibilityProvider else { return }
        let shouldShow = visibilityProvider()
        statusItem.isVisible = shouldShow

        if shouldShow {
            visibilityTimer?.invalidate()
            visibilityTimer = nil
        } else if visibilityTimer == nil {
            let timer = Timer(
                timeInterval: Self.visibilityPollInterval, repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
            RunLoop.main.add(timer, forMode: .common)
            visibilityTimer = timer
        }
    }

    @objc private func saveFrameSelected() {
        guard let onSaveFrame else { return }
        lastSavedPath = onSaveFrame()
    }

    @objc private func quitSelected() {
        onQuit()
    }
}

/// The preview placed inside the menu — the latest frame, clipped to rounded corners.
///
/// This is a thumbnail for recalling what is being drawn, not the main event of the
/// menu. A border keeps a dark piece from dissolving into the menu's own background.
@MainActor
final class HeadlessPreviewView: NSView {
    /// The picture to show. `nil` draws the backing and the placeholder text only.
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    private static let margin: CGFloat = 14
    private static let cornerRadius: CGFloat = 4

    init(previewSize: NSSize, sketchTitle: String = "") {
        super.init(
            frame: NSRect(
                x: 0, y: 0,
                width: previewSize.width + Self.margin * 2,
                height: previewSize.height + Self.margin
            ))
        setAccessibilityRole(.image)
        setAccessibilityElement(true)
        setAccessibilityLabel(
            sketchTitle.isEmpty ? "Sketch preview" : "Preview of \(sketchTitle)")
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

        guard let image else {
            drawPlaceholder(in: rect)
            strokeBorder(around: rect)
            return
        }
        context.saveGState()
        path.addClip()
        // 実行中に解像度が変わっても潰さないよう、絵の側の比率で内接させる。
        context.draw(
            image,
            in: Self.aspectFit(
                imageWidth: image.width, imageHeight: image.height, into: rect
            ))
        context.restoreGState()
        strokeBorder(around: rect)
    }

    /// Draws the line between the picture and the menu's own background, so that a
    /// dark piece still has an outline.
    private func strokeBorder(around rect: NSRect) {
        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        border.lineWidth = 1
        NSColor.separatorColor.setStroke()
        border.stroke()
    }

    /// Says in words that no frame has been captured yet, rather than showing a grey plate.
    private func drawPlaceholder(in rect: NSRect) {
        let text = "No frame yet" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
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
