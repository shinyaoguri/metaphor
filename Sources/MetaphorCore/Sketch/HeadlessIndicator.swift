import Foundation

/// Where to show that a headless (offscreen) run is in progress.
///
/// A sketch started headless (`METAPHOR_VIEWER=1`) has no window, so showing
/// nothing at all leaves **no way to tell whether it is running, how many are
/// running, or how to stop them** — and App Nap is suppressed by default, so it
/// keeps the GPU busy out of sight. This setting guarantees that an invisible
/// process always surfaces somewhere, and can be quit from there.
///
/// The default is ``menuBar``, which follows the macOS convention for a process
/// that keeps running in the background and leaves the Dock alone. Setting the
/// environment variable `METAPHOR_HEADLESS_INDICATOR` (`menubar` / `dock` /
/// `both` / `none`) takes precedence, so a built sketch can be switched over
/// without recompiling it.
///
/// ```swift
/// var config: SketchConfig {
///     SketchConfig(headlessIndicator: .both)   // show in both the menu bar and the Dock
/// }
/// ```
///
/// > Note: the ``menuBar`` status item **stays hidden while the live viewer
/// > (`metaphor watch`) is attached** — the parent window is already showing the
/// > same picture and the same numbers, so there is nothing to gain from listing
/// > it twice. It appears once the parent is gone and nobody is watching any
/// > more, which makes **its very presence the signal that this process is
/// > unobserved**. Runs with no parent window, such as `metaphor mcp` or a Syphon
/// > output, show it as they always did.
///
/// Runs with a window are unaffected (the Dock icon appears as before).
public enum HeadlessIndicator: String, Sendable, CaseIterable {
    /// Shows a status item in the menu bar (the default).
    ///
    /// Clicking it reads out the sketch name, **where the process lives**, the
    /// PID, the resolution, the target and measured fps, the elapsed time and the
    /// outputs, and it can save the frame being drawn. The process can also be
    /// quit from there.
    case menuBar = "menubar"

    /// Shows an icon in the Dock.
    ///
    /// It also appears in Cmd+Tab, and can be quit from the Dock icon's context menu.
    case dock = "dock"

    /// Shows both the menu bar item and the Dock icon.
    case both = "both"

    /// Shows nothing anywhere (the behaviour before this setting existed).
    case hidden = "hidden"

    /// Whether to show a status item in the menu bar.
    var showsMenuBarItem: Bool { self == .menuBar || self == .both }

    /// Whether to show a Dock icon (`NSApplication.ActivationPolicy.regular`).
    var showsDockIcon: Bool { self == .dock || self == .both }

    /// Interprets the value of the environment variable.
    ///
    /// Surrounding whitespace and letter case are ignored, and spelling variants
    /// (`menu-bar` / `none` / `off`) are accepted. A value that cannot be
    /// interpreted returns `nil`, and the caller falls back to the configured value.
    ///
    /// - Parameter raw: The raw string read from the environment variable.
    /// - Returns: The matching indicator, or `nil` when it cannot be interpreted.
    static func parse(_ raw: String) -> HeadlessIndicator? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "menubar", "menu-bar", "menu", "statusitem": return .menuBar
        case "dock": return .dock
        case "both", "all": return .both
        case "hidden", "none", "off", "0": return .hidden
        default: return nil
        }
    }
}
