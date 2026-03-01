import Foundation

// MARK: - Math Constants (Processing互換)

/// 円周率
public let PI: Float = .pi

/// 2π
public let TWO_PI: Float = .pi * 2

/// π/2
public let HALF_PI: Float = .pi / 2

/// π/4
public let QUARTER_PI: Float = .pi / 4

/// τ = 2π
public let TAU: Float = .pi * 2

// MARK: - Key Code Constants (macOS Virtual Key Codes)

/// 左矢印キー
public let LEFT: UInt16 = 123
/// 右矢印キー
public let RIGHT: UInt16 = 124
/// 下矢印キー
public let DOWN: UInt16 = 125
/// 上矢印キー
public let UP: UInt16 = 126

/// Returnキー
public let RETURN: UInt16 = 36
/// テンキーEnter
public let ENTER: UInt16 = 76
/// Tabキー
public let TAB: UInt16 = 48
/// スペースキー
public let SPACE: UInt16 = 49
/// Backspace（Delete）キー
public let BACKSPACE: UInt16 = 51
/// Forward Deleteキー
public let DELETE: UInt16 = 117
/// Escapeキー
public let ESCAPE: UInt16 = 53

/// Shiftキー
public let SHIFT: UInt16 = 56
/// Controlキー
public let CONTROL: UInt16 = 59
/// Optionキー
public let OPTION: UInt16 = 58
/// Altキー（OPTIONの別名）
public let ALT: UInt16 = 58
/// Commandキー
public let COMMAND: UInt16 = 55

// MARK: - Time

/// スケッチ開始からの経過ミリ秒を返す
@MainActor
public func millis() -> Int {
    Int((_activeSketchContext?.time ?? 0) * 1000)
}
