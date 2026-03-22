/// Canvas3D インスタンス描画シェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// `instance_id` を使用してインスタンスごとのデータ（トランスフォーム、カラー）を読み取り、
/// 同一メッシュを単一のドローコールでバッチレンダリングします。
enum Canvas3DInstancedShaders {

    // MARK: - 関数名

    /// 非テクスチャインスタンス描画頂点シェーダーのMSL関数名。
    static let vertexFunctionName = "metaphor_canvas3DInstancedVertex"
    /// 非テクスチャインスタンス描画フラグメントシェーダーのMSL関数名。
    static let fragmentFunctionName = "metaphor_canvas3DInstancedFragment"
    /// テクスチャ付きインスタンス描画頂点シェーダーのMSL関数名。
    static let texturedVertexFunctionName = "metaphor_canvas3DTexInstancedVertex"
    /// テクスチャ付きインスタンス描画フラグメントシェーダーのMSL関数名。
    static let texturedFragmentFunctionName = "metaphor_canvas3DTexInstancedFragment"
}
