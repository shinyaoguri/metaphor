import Foundation

// MARK: - Math Constants (Processing-compatible)

/// 円の円周と直径の比率。
public let PI: Float = .pi

/// 2パイ（ラジアンでの全円）。
public let TWO_PI: Float = .pi * 2

/// パイの半分（ラジアンでの四分円）。
public let HALF_PI: Float = .pi / 2

/// パイの4分の1（ラジアンでの八分円）。
public let QUARTER_PI: Float = .pi / 4

/// タウ。2パイに等しい（ラジアンでの全円）。
public let TAU: Float = .pi * 2

// MARK: - Key Code Constants (macOS Virtual Key Codes)

/// 左矢印キーの仮想キーコード。
public let LEFT: UInt16 = 123
/// 右矢印キーの仮想キーコード。
public let RIGHT: UInt16 = 124
/// 下矢印キーの仮想キーコード。
public let DOWN: UInt16 = 125
/// 上矢印キーの仮想キーコード。
public let UP: UInt16 = 126

/// Return キーの仮想キーコード。
public let RETURN: UInt16 = 36
/// テンキー Enter キーの仮想キーコード。
public let ENTER: UInt16 = 76
/// Tab キーの仮想キーコード。
public let TAB: UInt16 = 48
/// Space キーの仮想キーコード。
public let SPACE: UInt16 = 49
/// Backspace (Delete) キーの仮想キーコード。
public let BACKSPACE: UInt16 = 51
/// Forward Delete キーの仮想キーコード。
public let DELETE: UInt16 = 117
/// Escape キーの仮想キーコード。
public let ESCAPE: UInt16 = 53

/// Shift キーの仮想キーコード。
public let SHIFT: UInt16 = 56
/// Control キーの仮想キーコード。
public let CONTROL: UInt16 = 59
/// Option キーの仮想キーコード。
public let OPTION: UInt16 = 58
/// Alt キーの仮想キーコード（Option のエイリアス）。
public let ALT: UInt16 = 58
/// Command キーの仮想キーコード。
public let COMMAND: UInt16 = 55

// MARK: - Time

/// SketchContext が毎フレーム更新する内部時間値。
@MainActor
var _sketchElapsedTime: Float = 0

/// スケッチ開始からの経過時間をミリ秒で返します。
/// - Returns: ミリ秒単位の経過時間。
@MainActor
public func millis() -> Int {
    Int(_sketchElapsedTime * 1000)
}

// MARK: - Calendar Time (Processing-compatible)

/// 現在の秒（0〜59）を返します。
public func second() -> Int {
    Calendar.current.component(.second, from: Date())
}

/// 現在の分（0〜59）を返します。
public func minute() -> Int {
    Calendar.current.component(.minute, from: Date())
}

/// 現在の時（0〜23）を返します。
public func hour() -> Int {
    Calendar.current.component(.hour, from: Date())
}

/// 現在の日（1〜31）を返します。
public func day() -> Int {
    Calendar.current.component(.day, from: Date())
}

/// 現在の月（1〜12）を返します。
public func month() -> Int {
    Calendar.current.component(.month, from: Date())
}

/// 現在の年を返します。
public func year() -> Int {
    Calendar.current.component(.year, from: Date())
}
