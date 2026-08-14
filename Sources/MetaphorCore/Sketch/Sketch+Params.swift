import Foundation

/// `@Param` で宣言したパラメータのストアへのアクセス。
///
/// ```swift
/// @main final class MySketch: Sketch {
///     @Param(min: 10, max: 200) var radius: Float = 50
///
///     func draw() {
///         circle(width / 2, height / 2, radius)   // 通常のプロパティとして読む
///         probe("radius", radius)
///     }
/// }
/// ```
///
/// 値の読み書きは宣言したプロパティを直接使えば十分で、``params`` は
/// 名前でのアクセス（GUI・デバッグ・ツール実装）のための入口です。
///
/// 人間が触るパネルが要るときは `draw()` で ``ParameterGUI/params()`` を呼びます
/// （`gui.params()` の 1 行。GUI と外部エージェントは同じストアの対称なクライアント）。
@MainActor
public extension Sketch {
    /// `@Param` で宣言されたパラメータのストア。
    var params: ParameterStore {
        context.params
    }
}
