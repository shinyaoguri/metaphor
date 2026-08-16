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
//
// 値の正典は ``KeyCode``（Sources/MetaphorCore/Input/KeyCode.swift）で、ここはその
// Processing 互換な別名です。`import Foundation` を併用すると Darwin の `sys/tty.h` が持つ
// 同名マクロと衝突して書けなくなるものがあるため（Issue #794）、そのときは `KeyCode.return`
// のように名前空間を経由してください。

/// 左矢印キーの仮想キーコード。
public let LEFT: UInt16 = KeyCode.left
/// 右矢印キーの仮想キーコード。
public let RIGHT: UInt16 = KeyCode.right
/// 下矢印キーの仮想キーコード。
public let DOWN: UInt16 = KeyCode.down
/// 上矢印キーの仮想キーコード。
public let UP: UInt16 = KeyCode.up

/// Return キーの仮想キーコード。
///
/// - Important: `import Foundation` を併用すると Darwin の同名マクロと曖昧になります
///   （`metaphor.RETURN` と修飾しても絞れません）。``KeyCode/return`` を使うか、
///   `let r: UInt16 = RETURN` のように型注釈を付けてください。
public let RETURN: UInt16 = KeyCode.return
/// テンキー Enter キーの仮想キーコード。
public let ENTER: UInt16 = KeyCode.enter
/// Tab キーの仮想キーコード。
///
/// - Important: `import Foundation` を併用すると Darwin の同名マクロと曖昧になります。
///   ``KeyCode/tab`` を使うか型注釈を付けてください。
public let TAB: UInt16 = KeyCode.tab
/// Space キーの仮想キーコード。
public let SPACE: UInt16 = KeyCode.space
/// Backspace (Delete) キーの仮想キーコード。
///
/// - Important: `import Foundation` を併用すると Darwin の同名マクロと曖昧になります。
///   ``KeyCode/backspace`` を使うか型注釈を付けてください。
public let BACKSPACE: UInt16 = KeyCode.backspace
/// Forward Delete キーの仮想キーコード。
public let DELETE: UInt16 = KeyCode.delete
/// Escape キーの仮想キーコード。
public let ESCAPE: UInt16 = KeyCode.escape

/// Shift キーの仮想キーコード。
public let SHIFT: UInt16 = KeyCode.shift
/// Control キーの仮想キーコード。
///
/// - Important: `import Foundation` を併用すると Darwin の同名マクロと曖昧になります。
///   ``KeyCode/control`` を使うか型注釈を付けてください。
public let CONTROL: UInt16 = KeyCode.control
/// Option キーの仮想キーコード。
public let OPTION: UInt16 = KeyCode.option
/// Alt キーの仮想キーコード（Option のエイリアス）。
public let ALT: UInt16 = KeyCode.alt
/// Command キーの仮想キーコード。
public let COMMAND: UInt16 = KeyCode.command

// MARK: - Time

/// SketchContext が毎フレーム更新する内部時間値。
/// Double 精度で保持する（Float だと約 4.6 時間で ms 分解能が失われる）。
@MainActor
var _sketchElapsedTime: Double = 0

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
