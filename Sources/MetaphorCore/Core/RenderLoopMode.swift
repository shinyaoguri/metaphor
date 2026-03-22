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
