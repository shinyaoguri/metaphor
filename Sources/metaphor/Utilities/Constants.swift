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

// MARK: - Time

/// スケッチ開始からの経過ミリ秒を返す
@MainActor
public func millis() -> Int {
    Int((_activeSketchContext?.time ?? 0) * 1000)
}
