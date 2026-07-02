import Metal
import MetaphorCore

/// ``RenderGraph`` 内のノードのインターフェースを定義します。
///
/// ``RenderPassNode`` に準拠する各ノードは
/// ``execute(commandBuffer:time:renderer:)`` メソッドでレンダリング処理を行い、
/// ``output`` テクスチャプロパティ経由で結果を公開します。
///
/// ## カスタムノードの実装要件
///
/// `execute` の冒頭で **frameToken によるメモ化** を必ず実装してください。
/// 組み込みノード（``SourcePass`` / ``EffectPass`` / ``MergePass``）はこの
/// パターンにより、diamond 状に共有されたノードもフレーム内で 1 回だけ実行
/// されます。メモ化がないと共有ノードが重複実行され、グラフに循環がある場合は
/// 無限再帰でスタックオーバーフローします。
///
/// ```swift
/// private var lastExecutedToken: UInt64 = .max  // .max = 未実行センチネル
///
/// func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
///     guard lastExecutedToken != renderer.frameToken else { return }
///     lastExecutedToken = renderer.frameToken  // 入力の execute より先にセットする
///     // ... 入力パスの execute → 自身の処理 ...
/// }
/// ```
@MainActor
public protocol RenderPassNode: AnyObject {
    /// このノードを識別するデバッグラベル。
    var label: String { get }

    /// 実行後に生成される出力テクスチャ。未実行の場合は `nil`。
    var output: MTLTexture? { get }

    /// このノードのレンダリング処理を実行し、``output`` テクスチャを生成します。
    ///
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする Metal コマンドバッファ。
    ///   - time: 経過時間（秒）。
    ///   - renderer: 共有リソースを提供する `MetaphorRenderer` 参照。
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer)
}
