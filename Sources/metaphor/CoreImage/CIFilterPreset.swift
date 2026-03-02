import CoreImage
import simd

/// CoreImage フィルタのクリエイティブコーディング向けプリセット
public enum CIFilterPreset: Sendable {

    // MARK: - Distortion

    /// ツイスト歪み
    case twirl(center: SIMD2<Float>? = nil, radius: Float = 300, angle: Float = .pi)
    /// 渦巻き歪み
    case vortex(center: SIMD2<Float>? = nil, radius: Float = 300, angle: Float = 56.55)
    /// バンプ（凸凹）歪み
    case bump(center: SIMD2<Float>? = nil, radius: Float = 300, scale: Float = 0.5)
    /// ピンチ歪み
    case pinch(center: SIMD2<Float>? = nil, radius: Float = 300, scale: Float = 0.5)
    /// 円形ラップ
    case circularWrap(center: SIMD2<Float>? = nil, radius: Float = 150, angle: Float = 0)

    // MARK: - Stylize

    /// ピクセレート（CoreImage版）
    case ciPixellate(scale: Float = 8)
    /// クリスタライズ
    case crystallize(radius: Float = 20)
    /// ポインティリズム
    case pointillize(center: SIMD2<Float>? = nil, radius: Float = 20)
    /// エッジ検出（CoreImage版）
    case ciEdges(intensity: Float = 1)
    /// コミック風
    case comic
    /// 六角形ピクセレート
    case hexPixellate(center: SIMD2<Float>? = nil, scale: Float = 8)

    // MARK: - Tile

    /// 万華鏡
    case kaleidoscope(count: Int = 6, center: SIMD2<Float>? = nil, angle: Float = 0)
    /// 三角万華鏡
    case triangleKaleidoscope(point: SIMD2<Float>? = nil, size: Float = 700, rotation: Float = 5.924, decay: Float = 0.85)

    // MARK: - Generator (入力不要)

    /// チェッカーボード
    case checkerboard(center: SIMD2<Float>? = nil, color0: CIColor = .white, color1: CIColor = .black, width: Float = 80, sharpness: Float = 1)
    /// ストライプ
    case stripes(center: SIMD2<Float>? = nil, color0: CIColor = .white, color1: CIColor = .black, width: Float = 80, sharpness: Float = 1)
    /// スターシャイン
    case starShine(center: SIMD2<Float>? = nil, color: CIColor = .white, radius: Float = 50, crossScale: Float = 15, crossAngle: Float = 0.6, crossOpacity: Float = -2, crossWidth: Float = 2.5, epsilon: Float = -2)
    /// サンビーム
    case sunbeams(center: SIMD2<Float>? = nil, color: CIColor = .white, sunRadius: Float = 40, maxStriationRadius: Float = 2.58, striationStrength: Float = 0.5, striationContrast: Float = 1.375, time: Float = 0)

    // MARK: - Color Effect

    /// フォルスカラー（2色グラデーション）
    case falseColor(color0: CIColor = CIColor(red: 0.3, green: 0, blue: 0), color1: CIColor = CIColor(red: 1, green: 0.9, blue: 0.8))
    /// ポスタライズ
    case colorPosterize(levels: Float = 6)
    /// モノクロ写真
    case photoEffectMono
    /// クローム写真
    case photoEffectChrome
    /// フェード写真
    case photoEffectFade
    /// ノワール写真
    case photoEffectNoir

    // MARK: - Blur

    /// ガウシアンブラー（CoreImage版）
    case ciGaussianBlur(radius: Float = 10)
    /// モーションブラー
    case motionBlur(radius: Float = 20, angle: Float = 0)
    /// ズームブラー
    case zoomBlur(center: SIMD2<Float>? = nil, amount: Float = 20)
    /// ディスクブラー
    case discBlur(radius: Float = 8)
    /// ボックスブラー
    case boxBlur(radius: Float = 10)

    // MARK: - Internal

    /// CIFilter 名を返す
    var filterName: String {
        switch self {
        case .twirl: "CITwirlDistortion"
        case .vortex: "CIVortexDistortion"
        case .bump: "CIBumpDistortion"
        case .pinch: "CIPinchDistortion"
        case .circularWrap: "CICircularWrap"
        case .ciPixellate: "CIPixellate"
        case .crystallize: "CICrystallize"
        case .pointillize: "CIPointillize"
        case .ciEdges: "CIEdges"
        case .comic: "CIComicEffect"
        case .hexPixellate: "CIHexagonalPixellate"
        case .kaleidoscope: "CIKaleidoscope"
        case .triangleKaleidoscope: "CITriangleKaleidoscope"
        case .checkerboard: "CICheckerboardGenerator"
        case .stripes: "CIStripesGenerator"
        case .starShine: "CIStarShineGenerator"
        case .sunbeams: "CISunbeamsGenerator"
        case .falseColor: "CIFalseColor"
        case .colorPosterize: "CIColorPosterize"
        case .photoEffectMono: "CIPhotoEffectMono"
        case .photoEffectChrome: "CIPhotoEffectChrome"
        case .photoEffectFade: "CIPhotoEffectFade"
        case .photoEffectNoir: "CIPhotoEffectNoir"
        case .ciGaussianBlur: "CIGaussianBlur"
        case .motionBlur: "CIMotionBlur"
        case .zoomBlur: "CIZoomBlur"
        case .discBlur: "CIDiscBlur"
        case .boxBlur: "CIBoxBlur"
        }
    }

    /// パラメータ辞書を返す
    func parameters(textureSize: CGSize) -> [String: Any] {
        let defaultCenter = CIVector(x: textureSize.width / 2, y: textureSize.height / 2)

        func center(_ c: SIMD2<Float>?) -> CIVector {
            c.map { CIVector(x: CGFloat($0.x), y: CGFloat($0.y)) } ?? defaultCenter
        }

        switch self {
        case .twirl(let c, let radius, let angle):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius, kCIInputAngleKey: angle]
        case .vortex(let c, let radius, let angle):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius, kCIInputAngleKey: angle]
        case .bump(let c, let radius, let scale):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius, kCIInputScaleKey: scale]
        case .pinch(let c, let radius, let scale):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius, kCIInputScaleKey: scale]
        case .circularWrap(let c, let radius, let angle):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius, kCIInputAngleKey: angle]
        case .ciPixellate(let scale):
            return [kCIInputScaleKey: scale]
        case .crystallize(let radius):
            return [kCIInputRadiusKey: radius]
        case .pointillize(let c, let radius):
            return [kCIInputCenterKey: center(c), kCIInputRadiusKey: radius]
        case .ciEdges(let intensity):
            return [kCIInputIntensityKey: intensity]
        case .comic:
            return [:]
        case .hexPixellate(let c, let scale):
            return [kCIInputCenterKey: center(c), kCIInputScaleKey: scale]
        case .kaleidoscope(let count, let c, let angle):
            return ["inputCount": count, kCIInputCenterKey: center(c), kCIInputAngleKey: angle]
        case .triangleKaleidoscope(let point, let size, let rotation, let decay):
            return ["inputPoint": point.map { CIVector(x: CGFloat($0.x), y: CGFloat($0.y)) } ?? defaultCenter,
                    "inputSize": size, "inputRotation": rotation, "inputDecay": decay]
        case .checkerboard(let c, let color0, let color1, let w, let sharpness):
            return [kCIInputCenterKey: center(c), "inputColor0": color0, "inputColor1": color1,
                    "inputWidth": w, kCIInputSharpnessKey: sharpness]
        case .stripes(let c, let color0, let color1, let w, let sharpness):
            return [kCIInputCenterKey: center(c), "inputColor0": color0, "inputColor1": color1,
                    "inputWidth": w, kCIInputSharpnessKey: sharpness]
        case .starShine(let c, let color, let radius, let crossScale, let crossAngle, let crossOpacity, let crossWidth, let epsilon):
            return [kCIInputCenterKey: center(c), "inputColor": color, kCIInputRadiusKey: radius,
                    "inputCrossScale": crossScale, "inputCrossAngle": crossAngle,
                    "inputCrossOpacity": crossOpacity, "inputCrossWidth": crossWidth, "inputEpsilon": epsilon]
        case .sunbeams(let c, let color, let sunRadius, let maxStriationRadius, let striationStrength, let striationContrast, let time):
            return [kCIInputCenterKey: center(c), "inputColor": color, "inputSunRadius": sunRadius,
                    "inputMaxStriationRadius": maxStriationRadius, "inputStriationStrength": striationStrength,
                    "inputStriationContrast": striationContrast, kCIInputTimeKey: time]
        case .falseColor(let color0, let color1):
            return ["inputColor0": color0, "inputColor1": color1]
        case .colorPosterize(let levels):
            return ["inputLevels": levels]
        case .photoEffectMono, .photoEffectChrome, .photoEffectFade, .photoEffectNoir:
            return [:]
        case .ciGaussianBlur(let radius):
            return [kCIInputRadiusKey: radius]
        case .motionBlur(let radius, let angle):
            return [kCIInputRadiusKey: radius, kCIInputAngleKey: angle]
        case .zoomBlur(let c, let amount):
            return [kCIInputCenterKey: center(c), "inputAmount": amount]
        case .discBlur(let radius):
            return [kCIInputRadiusKey: radius]
        case .boxBlur(let radius):
            return [kCIInputRadiusKey: radius]
        }
    }

    /// ジェネレーターフィルタかどうか
    var isGenerator: Bool {
        switch self {
        case .checkerboard, .stripes, .starShine, .sunbeams:
            true
        default:
            false
        }
    }
}
