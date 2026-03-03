import Foundation

// MARK: - Math Constants (Processing-compatible)

/// The ratio of a circle's circumference to its diameter.
public let PI: Float = .pi

/// Two times pi (full circle in radians).
public let TWO_PI: Float = .pi * 2

/// Half of pi (quarter circle in radians).
public let HALF_PI: Float = .pi / 2

/// One quarter of pi (eighth of a circle in radians).
public let QUARTER_PI: Float = .pi / 4

/// Tau, equal to 2 times pi (full circle in radians).
public let TAU: Float = .pi * 2

// MARK: - Key Code Constants (macOS Virtual Key Codes)

/// Virtual key code for the left arrow key.
public let LEFT: UInt16 = 123
/// Virtual key code for the right arrow key.
public let RIGHT: UInt16 = 124
/// Virtual key code for the down arrow key.
public let DOWN: UInt16 = 125
/// Virtual key code for the up arrow key.
public let UP: UInt16 = 126

/// Virtual key code for the Return key.
public let RETURN: UInt16 = 36
/// Virtual key code for the numeric keypad Enter key.
public let ENTER: UInt16 = 76
/// Virtual key code for the Tab key.
public let TAB: UInt16 = 48
/// Virtual key code for the Space key.
public let SPACE: UInt16 = 49
/// Virtual key code for the Backspace (Delete) key.
public let BACKSPACE: UInt16 = 51
/// Virtual key code for the Forward Delete key.
public let DELETE: UInt16 = 117
/// Virtual key code for the Escape key.
public let ESCAPE: UInt16 = 53

/// Virtual key code for the Shift key.
public let SHIFT: UInt16 = 56
/// Virtual key code for the Control key.
public let CONTROL: UInt16 = 59
/// Virtual key code for the Option key.
public let OPTION: UInt16 = 58
/// Virtual key code for the Alt key (alias for Option).
public let ALT: UInt16 = 58
/// Virtual key code for the Command key.
public let COMMAND: UInt16 = 55

// MARK: - Time

/// Internal time value updated by SketchContext each frame.
@MainActor
var _sketchElapsedTime: Float = 0

/// Return the number of milliseconds elapsed since the sketch started.
/// - Returns: The elapsed time in milliseconds.
@MainActor
public func millis() -> Int {
    Int(_sketchElapsedTime * 1000)
}
