import CoreImage
import simd

/// Provide curated CoreImage filter presets for creative coding.
public enum CIFilterPreset: Sendable {

    // MARK: - Distortion

    /// Apply a twirl distortion effect.
    case twirl(center: SIMD2<Float>? = nil, radius: Float = 300, angle: Float = .pi)
    /// Apply a vortex distortion effect.
    case vortex(center: SIMD2<Float>? = nil, radius: Float = 300, angle: Float = 56.55)
    /// Apply a bump distortion effect.
    case bump(center: SIMD2<Float>? = nil, radius: Float = 300, scale: Float = 0.5)
    /// Apply a pinch distortion effect.
    case pinch(center: SIMD2<Float>? = nil, radius: Float = 300, scale: Float = 0.5)
    /// Apply a circular wrap distortion effect.
    case circularWrap(center: SIMD2<Float>? = nil, radius: Float = 150, angle: Float = 0)

    // MARK: - Stylize

    /// Apply a pixelation effect (CoreImage version).
    case ciPixellate(scale: Float = 8)
    /// Apply a crystallize effect.
    case crystallize(radius: Float = 20)
    /// Apply a pointillism effect.
    case pointillize(center: SIMD2<Float>? = nil, radius: Float = 20)
    /// Apply edge detection (CoreImage version).
    case ciEdges(intensity: Float = 1)
    /// Apply a comic book style effect.
    case comic
    /// Apply a hexagonal pixelation effect.
    case hexPixellate(center: SIMD2<Float>? = nil, scale: Float = 8)

    // MARK: - Tile

    /// Apply a kaleidoscope effect.
    case kaleidoscope(count: Int = 6, center: SIMD2<Float>? = nil, angle: Float = 0)
    /// Apply a triangle kaleidoscope effect.
    case triangleKaleidoscope(point: SIMD2<Float>? = nil, size: Float = 700, rotation: Float = 5.924, decay: Float = 0.85)

    // MARK: - Generator (no input image required)

    /// Generate a checkerboard pattern.
    case checkerboard(center: SIMD2<Float>? = nil, color0: CIColor = .white, color1: CIColor = .black, width: Float = 80, sharpness: Float = 1)
    /// Generate a stripe pattern.
    case stripes(center: SIMD2<Float>? = nil, color0: CIColor = .white, color1: CIColor = .black, width: Float = 80, sharpness: Float = 1)
    /// Generate a star shine effect.
    case starShine(center: SIMD2<Float>? = nil, color: CIColor = .white, radius: Float = 50, crossScale: Float = 15, crossAngle: Float = 0.6, crossOpacity: Float = -2, crossWidth: Float = 2.5, epsilon: Float = -2)
    /// Generate a sunbeams effect.
    case sunbeams(center: SIMD2<Float>? = nil, color: CIColor = .white, sunRadius: Float = 40, maxStriationRadius: Float = 2.58, striationStrength: Float = 0.5, striationContrast: Float = 1.375, time: Float = 0)

    // MARK: - Color Effect

    /// Apply a false color effect (two-color gradient mapping).
    case falseColor(color0: CIColor = CIColor(red: 0.3, green: 0, blue: 0), color1: CIColor = CIColor(red: 1, green: 0.9, blue: 0.8))
    /// Apply a color posterize effect.
    case colorPosterize(levels: Float = 6)
    /// Apply a monochrome photo effect.
    case photoEffectMono
    /// Apply a chrome photo effect.
    case photoEffectChrome
    /// Apply a fade photo effect.
    case photoEffectFade
    /// Apply a noir photo effect.
    case photoEffectNoir

    // MARK: - Blur

    /// Apply a Gaussian blur (CoreImage version).
    case ciGaussianBlur(radius: Float = 10)
    /// Apply a motion blur effect.
    case motionBlur(radius: Float = 20, angle: Float = 0)
    /// Apply a zoom blur effect.
    case zoomBlur(center: SIMD2<Float>? = nil, amount: Float = 20)
    /// Apply a disc blur effect.
    case discBlur(radius: Float = 8)
    /// Apply a box blur effect.
    case boxBlur(radius: Float = 10)

    // MARK: - Internal

    /// Return the CIFilter name string for this preset.
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

    /// Return the parameter dictionary for this preset given a texture size.
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

    /// Indicate whether this preset is a generator filter (requires no input image).
    var isGenerator: Bool {
        switch self {
        case .checkerboard, .stripes, .starShine, .sunbeams:
            true
        default:
            false
        }
    }
}
