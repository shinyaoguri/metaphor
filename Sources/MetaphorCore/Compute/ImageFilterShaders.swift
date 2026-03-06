import Foundation

/// GPU image filter compute shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Includes threshold, grayscale, invert, posterize, gaussian blur (H/V),
/// erode, dilate, edge detect (Sobel), sharpen, sepia, and pixelate filters.
enum ImageFilterShaders {

    /// Image filter shader function name constants.
    enum FunctionName {
        /// MSL function name for the threshold filter.
        static let threshold = "filter_threshold"
        /// MSL function name for the grayscale filter.
        static let gray = "filter_gray"
        /// MSL function name for the invert filter.
        static let invert = "filter_invert"
        /// MSL function name for the posterize filter.
        static let posterize = "filter_posterize"
        /// MSL function name for the horizontal gaussian blur filter.
        static let gaussianH = "filter_gaussian_h"
        /// MSL function name for the vertical gaussian blur filter.
        static let gaussianV = "filter_gaussian_v"
        /// MSL function name for the erode filter.
        static let erode = "filter_erode"
        /// MSL function name for the dilate filter.
        static let dilate = "filter_dilate"
        /// MSL function name for the edge detect (Sobel) filter.
        static let edgeDetect = "filter_edgeDetect"
        /// MSL function name for the sharpen filter.
        static let sharpen = "filter_sharpen"
        /// MSL function name for the sepia filter.
        static let sepia = "filter_sepia"
        /// MSL function name for the pixelate filter.
        static let pixelate = "filter_pixelate"
    }
}
