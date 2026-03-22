import Foundation

/// Kawase（デュアルフィルタ）ブラーシェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// ピクセル単位のカーネルループの代わりに階層的なダウン/アップサンプルパスを使用し、
/// ガウシアンブラーと同等の品質を大幅に高速で実現します。
enum KawaseBlurShaders {

    /// Kawase ブラーシェーダー関数名定数。
    enum FunctionName {
        /// Kawase ダウンサンプルシェーダーのMSL関数名。
        static let kawaseDownsample = "metaphor_kawaseDownsample"
        /// Kawase アップサンプルシェーダーのMSL関数名。
        static let kawaseUpsample = "metaphor_kawaseUpsample"
    }
}
