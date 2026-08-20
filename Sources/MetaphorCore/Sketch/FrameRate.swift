/// 目標フレームレートを有効な範囲へ丸めます（0 以下は 1 にクランプ）。
///
/// `frameRate(_:)` は複数の経路から届きます（`SketchRunner.handleFrameRate(_:)` と
/// `SketchView` の `onFrameRate`）。クランプと警告をそれぞれで書くと、片方だけ
/// 無効値が素通りする形（#358 で実際に起きた）へ戻りやすいので入口を 1 本にまとめます。
///
/// - Parameter fps: 呼び出し側から渡された目標フレーム毎秒。
/// - Returns: 1 以上に丸めた値。丸めが起きたときは警告を 1 度だけ出します。
func clampedFrameRate(_ fps: Int) -> Int {
    let clamped = max(fps, 1)
    if clamped != fps {
        metaphorWarning("frameRate(\(fps)) is invalid (must be positive); clamping to \(clamped).")
    }
    return clamped
}
