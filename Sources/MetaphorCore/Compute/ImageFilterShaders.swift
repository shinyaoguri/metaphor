import Foundation

/// GPU 画像フィルターコンピュートシェーダーの関数名定数
///
/// MSL ソースコードはバンドルされた .txt リソースファイルからランタイムで読み込まれます。
/// しきい値、グレースケール、反転、ポスタライズ、ガウシアンブラー (水平/垂直)、
/// 収縮、膨張、エッジ検出 (Sobel)、シャープン、セピア、ピクセレートフィルターを含みます。
enum ImageFilterShaders {

    /// 画像フィルターシェーダー関数名定数
    enum FunctionName {
        /// しきい値フィルターの MSL 関数名
        static let threshold = "filter_threshold"
        /// グレースケールフィルターの MSL 関数名
        static let gray = "filter_gray"
        /// 反転フィルターの MSL 関数名
        static let invert = "filter_invert"
        /// ポスタライズフィルターの MSL 関数名
        static let posterize = "filter_posterize"
        /// 水平ガウシアンブラーフィルターの MSL 関数名
        static let gaussianH = "filter_gaussian_h"
        /// 垂直ガウシアンブラーフィルターの MSL 関数名
        static let gaussianV = "filter_gaussian_v"
        /// 収縮フィルターの MSL 関数名
        static let erode = "filter_erode"
        /// 膨張フィルターの MSL 関数名
        static let dilate = "filter_dilate"
        /// エッジ検出 (Sobel) フィルターの MSL 関数名
        static let edgeDetect = "filter_edgeDetect"
        /// シャープンフィルターの MSL 関数名
        static let sharpen = "filter_sharpen"
        /// セピアフィルターの MSL 関数名
        static let sepia = "filter_sepia"
        /// ピクセレートフィルターの MSL 関数名
        static let pixelate = "filter_pixelate"
    }
}
