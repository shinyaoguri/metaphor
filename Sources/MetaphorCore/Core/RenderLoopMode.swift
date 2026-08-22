/// レンダーループの駆動方法を記述します。
///
/// デフォルトの `.displayLink` モードは MTKView 内蔵のディスプレイリンクを
/// フレームペーシングに使用します。Syphon 出力や動画録画など、
/// 独立したフレームタイミングが必要なシナリオでは `.timer(fps:)` を使用してください。
public enum RenderLoopMode: Sendable, Equatable {
    /// MTKView 内蔵のディスプレイリンク駆動レンダリング（デフォルト）
    case displayLink

    /// 独立したフレームタイミング用の DispatchSourceTimer を使用
    ///
    /// レンダリングをウィンドウリフレッシュから分離し、
    /// ウィンドウがオクルージョン状態の時に `currentDrawable` がブロックするのを防ぎます。
    /// - Parameter fps: 目標フレームレート
    case timer(fps: Int)
}

extension RenderLoopMode {
    /// 要求されたモードと、プラグイン / 出力 provider が宣言した要件から、実際に使うモードを決めます
    /// （純粋関数。`SketchRunner` とセカンダリの `SketchWindow` が同じ規則を共有する）。
    ///
    /// - ヘッドレス（ウィンドウ無し）は `MTKView` が無くディスプレイリンクを駆動できないため常にタイマー。
    /// - ``displayLink`` が要求されていても、``PluginRequirements/externalRenderLoop`` を宣言する
    ///   プラグインか出力があればタイマーへ切り替える（ウィンドウが隠れても出力を止めない。従来の
    ///   「Syphon ありなら timer」と同じ規則を一般化したもの）。
    /// - 明示的な ``timer(fps:)`` はそのまま。
    ///
    /// - Parameters:
    ///   - requested: 設定で要求されたモード。
    ///   - fps: タイマーへ切り替えるときの目標フレームレート（環境変数の上書きを解決した実効値）。
    ///   - requirements: ``PluginFactory/requirements`` と ``MetaphorOutputProvider/requirements`` の和。
    ///   - isHeadless: ヘッドレス起動かどうか。
    /// - Returns: 実際に使うレンダーループモード。
    public static func resolve(
        requested: RenderLoopMode,
        fps: Int,
        requirements: PluginRequirements,
        isHeadless: Bool
    ) -> RenderLoopMode {
        if isHeadless { return .timer(fps: fps) }
        if requested == .displayLink, requirements.contains(.externalRenderLoop) {
            return .timer(fps: fps)
        }
        return requested
    }
}
