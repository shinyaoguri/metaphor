/// Canvas2D インスタンス描画シェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// `instance_id` を使用してインスタンスごとのデータ（トランスフォーム、カラー）を読み取り、
/// 同一形状を単一のドローコールでバッチレンダリングします。
enum Canvas2DInstancedShaders {

    // MARK: - 関数名

    /// インスタンス描画頂点シェーダーのMSL関数名。
    static let vertexFunctionName = "metaphor_canvas2DInstancedVertex"
    /// インスタンス描画フラグメントシェーダーのMSL関数名。
    static let fragmentFunctionName = "metaphor_canvas2DInstancedFragment"
    /// インスタンス描画差分ブレンドフラグメントシェーダーのMSL関数名。
    static let differenceFragmentFunctionName = "metaphor_canvas2DInstancedDifferenceFragment"
    /// インスタンス描画除外ブレンドフラグメントシェーダーのMSL関数名。
    static let exclusionFragmentFunctionName = "metaphor_canvas2DInstancedExclusionFragment"
}
