import MetaphorCore
import MetaphorVideo

// MARK: - ビデオ再生ブリッジ

extension Sketch {
    /// 再生用のビデオファイルを読み込みます。
    ///
    /// - Parameter path: ビデオファイルのファイルパス。
    /// - Returns: 新しい ``MetaphorVideo/VideoPlayer`` インスタンス。
    /// - Throws: ファイルが存在しない場合にエラーをスローします。
    public func loadVideo(_ path: String) throws -> VideoPlayer {
        try VideoPlayer(path: path, device: context.renderer.device)
    }

    /// ビデオプレーヤーの現在のフレームを指定位置に描画します。
    ///
    /// - Parameters:
    ///   - video: 描画元のビデオプレーヤー。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    public func image(_ video: VideoPlayer, _ x: Float, _ y: Float) {
        guard let tex = video.texture else { return }
        let img = MImage(texture: tex)
        context.canvas.image(img, x, y)
    }

    /// ビデオプレーヤーの現在のフレームを指定位置・サイズで描画します。
    ///
    /// - Parameters:
    ///   - video: 描画元のビデオプレーヤー。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ video: VideoPlayer, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        guard let tex = video.texture else { return }
        let img = MImage(texture: tex)
        context.canvas.image(img, x, y, w, h)
    }
}
