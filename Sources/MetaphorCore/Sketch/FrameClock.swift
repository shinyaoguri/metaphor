/// フレーム間の経過時間（`deltaTime`）を算出するための「直前フレームの時刻」。
///
/// `SketchRunner` の compute / draw / 記録の各コールバックが同じ起点を共有し、
/// ループを止めている間に進んだ実時間が `deltaTime` に化けないよう
/// 起点を寄せ直せるようにするための小さな器です（#793）。
///
/// 時計そのもの（``MetaphorRenderer/elapsedTime``）は実時間ベースで、
/// ``noLoop()`` で止めている間も進み続けます。フレームは発火しないので、
/// 起点を寄せ直さないと再開後の最初のフレームで
/// 「止めていた実時間まるごと」が 1 フレームぶんの経過として渡ります。
final class FrameClock {
    /// 直前のフレームの時刻（秒）。
    private(set) var previousTime: Float

    /// - Parameter startTime: 起点となる時刻（秒）。
    init(startTime: Float = 0) {
        previousTime = startTime
    }

    /// 起点からの経過時間を返します（起点は進めません）。
    ///
    /// 同一フレームの compute フェーズのように、draw より前に同じ経過時間を
    /// 読みたい場所で使います。
    ///
    /// - Parameter time: 現在の時刻（秒）。
    /// - Returns: 起点からの経過秒。巻き戻り（負の経過）は 0 に丸めます。
    func delta(at time: Float) -> Float {
        max(0, time - previousTime)
    }

    /// 起点からの経過時間を返し、起点を現在の時刻へ進めます。
    ///
    /// - Parameter time: 現在の時刻（秒）。
    /// - Returns: 起点からの経過秒。巻き戻り（負の経過）は 0 に丸めます。
    func advance(to time: Float) -> Float {
        let dt = delta(at: time)
        previousTime = time
        return dt
    }

    /// 経過時間を返さずに起点だけを寄せ直します。
    ///
    /// ``SketchContext/loop()`` での再開時や、リロードで時計を引き継いだとき
    /// （`preserveClock`）のように、**フレームを 1 枚も描いていないのに時計だけが
    /// 進んだ**場面で使います。次のフレームの `deltaTime` はここからの経過になります。
    ///
    /// - Parameter time: 新しい起点となる時刻（秒）。
    func resync(to time: Float) {
        previousTime = time
    }
}
