import Foundation

// MARK: - Math Constants (Processing-compatible)

/// The ratio of a circle's circumference to its diameter.
public let PI: Float = .pi

/// Two pi (a full circle in radians).
public let TWO_PI: Float = .pi * 2

/// Half of pi (a quarter circle in radians).
public let HALF_PI: Float = .pi / 2

/// A quarter of pi (an eighth of a circle in radians).
public let QUARTER_PI: Float = .pi / 4

/// Tau. Equal to two pi (a full circle in radians).
public let TAU: Float = .pi * 2

// MARK: - Key Code Constants (macOS Virtual Key Codes)
//
// 値の正典は ``KeyCode``（Sources/MetaphorCore/Input/KeyCode.swift）で、ここはその
// Processing 互換な別名です。`import Foundation` を併用すると Darwin の `sys/tty.h` が持つ
// 同名マクロと衝突して書けなくなるものがあるため（Issue #794）、そのときは `KeyCode.return`
// のように名前空間を経由してください。

/// The virtual key code for the left arrow key.
public let LEFT: UInt16 = KeyCode.left
/// The virtual key code for the right arrow key.
public let RIGHT: UInt16 = KeyCode.right
/// The virtual key code for the down arrow key.
public let DOWN: UInt16 = KeyCode.down
/// The virtual key code for the up arrow key.
public let UP: UInt16 = KeyCode.up

/// The virtual key code for the Return key.
///
/// - Important: When `import Foundation` is also in scope, this name becomes ambiguous
///   with the Darwin macro of the same name (qualifying it as `metaphor.RETURN` does not
///   narrow it either). Use ``KeyCode/return``, or add a type annotation such as
///   `let r: UInt16 = RETURN`.
public let RETURN: UInt16 = KeyCode.return
/// The virtual key code for the numeric keypad Enter key.
public let ENTER: UInt16 = KeyCode.enter
/// The virtual key code for the Tab key.
///
/// - Important: When `import Foundation` is also in scope, this name becomes ambiguous
///   with the Darwin macro of the same name. Use ``KeyCode/tab`` or add a type annotation.
public let TAB: UInt16 = KeyCode.tab
/// The virtual key code for the Space key.
public let SPACE: UInt16 = KeyCode.space
/// The virtual key code for the Backspace (Delete) key.
///
/// - Important: When `import Foundation` is also in scope, this name becomes ambiguous
///   with the Darwin macro of the same name. Use ``KeyCode/backspace`` or add a type annotation.
public let BACKSPACE: UInt16 = KeyCode.backspace
/// The virtual key code for the Forward Delete key.
public let DELETE: UInt16 = KeyCode.delete
/// The virtual key code for the Escape key.
public let ESCAPE: UInt16 = KeyCode.escape

/// The virtual key code for the Shift key.
public let SHIFT: UInt16 = KeyCode.shift
/// The virtual key code for the Control key.
///
/// - Important: When `import Foundation` is also in scope, this name becomes ambiguous
///   with the Darwin macro of the same name. Use ``KeyCode/control`` or add a type annotation.
public let CONTROL: UInt16 = KeyCode.control
/// The virtual key code for the Option key.
public let OPTION: UInt16 = KeyCode.option
/// The virtual key code for the Alt key (an alias for Option).
public let ALT: UInt16 = KeyCode.alt
/// The virtual key code for the Command key.
public let COMMAND: UInt16 = KeyCode.command

// MARK: - Time

/// The internal time value that SketchContext updates every frame.
/// Held at Double precision (a Float loses millisecond resolution after about 4.6 hours).
@MainActor
var _sketchElapsedTime: Double = 0

/// Returns the number of milliseconds elapsed since the sketch started.
/// - Returns: The elapsed time in milliseconds.
@MainActor
public func millis() -> Int {
    Int(_sketchElapsedTime * 1000)
}

// MARK: - Calendar Time (Processing-compatible)

/// Returns the current second as a value from 0 to 59.
public func second() -> Int {
    Calendar.current.component(.second, from: Date())
}

/// Returns the current minute as a value from 0 to 59.
public func minute() -> Int {
    Calendar.current.component(.minute, from: Date())
}

/// Returns the current hour as a value from 0 to 23.
public func hour() -> Int {
    Calendar.current.component(.hour, from: Date())
}

/// Returns the current day of the month as a value from 1 to 31.
public func day() -> Int {
    Calendar.current.component(.day, from: Date())
}

/// Returns the current month as a value from 1 to 12.
public func month() -> Int {
    Calendar.current.component(.month, from: Date())
}

/// Returns the current year.
public func year() -> Int {
    Calendar.current.component(.year, from: Date())
}
