import Foundation

/// テクスチャマージ（コンポジット）シェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// コンピュートカーネルを使用して、指定されたブレンドモードで2つのテクスチャを合成します。
/// サポートされる blend_mode 値: 0=加算, 1=アルファ, 2=乗算, 3=スクリーン。
public enum MergeShaders {

    /// マージシェーダー関数名定数。
    public enum FunctionName {
        /// テクスチャマージコンピュートカーネルのMSL関数名。
        public static let mergeTextures = "metaphor_mergeTextures"
    }
}
