import Foundation

/// シャドウマッピングシェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
public enum ShadowShaders {

    /// シャドウシェーダー関数名定数。
    public enum FunctionName {
        /// シャドウデプス頂点シェーダーのMSL関数名。
        public static let shadowDepthVertex = "metaphor_shadowDepthVertex"
    }
}
