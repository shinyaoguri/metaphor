import Foundation
import simd

// MARK: - float4x4 Extensions

extension float4x4 {
    /// 単位行列を作成します。
    public static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    /// X軸まわりの回転行列を作成します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Y軸まわりの回転行列を作成します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Z軸まわりの回転行列を作成します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// 3Dベクトルから平行移動行列を作成します。
    ///
    /// - Parameter translation: 各軸方向の平行移動オフセット。
    public init(translation: SIMD3<Float>) {
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    /// 非均一スケール行列を作成します。
    ///
    /// - Parameter scale: 各軸のスケール係数。
    public init(scale: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
    }

    /// 均一スケール行列を作成します。
    ///
    /// - Parameter scale: すべての軸に適用される均一スケール係数。
    public init(scale: Float) {
        self.init(diagonal: SIMD4<Float>(scale, scale, scale, 1))
    }

    /// look-at 方式のビュー行列を作成します。
    ///
    /// - Parameters:
    ///   - eye: カメラの位置。
    ///   - center: カメラが注視する点。
    ///   - up: 上方向ベクトル。
    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        self.init(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// 透視投影行列を作成します。
    ///
    /// - Parameters:
    ///   - fov: ラジアン単位の垂直視野角。
    ///   - aspect: アスペクト比（幅 / 高さ）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public init(perspectiveFov fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        self.init(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }

    /// 正射影行列を作成します。
    ///
    /// - Parameters:
    ///   - left: ビューボリュームの左端。
    ///   - right: ビューボリュームの右端。
    ///   - bottom: ビューボリュームの下端。
    ///   - top: ビューボリュームの上端。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public init(orthographic left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (near - far)
        let tx = (left + right) / (left - right)
        let ty = (top + bottom) / (bottom - top)
        let tz = near / (near - far)

        self.init(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        ))
    }
}

// MARK: - Angle Conversions

/// 度数法をラジアンに変換します。
///
/// - Parameter degrees: 度数法の角度。
/// - Returns: ラジアン単位の角度。
public func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

/// ラジアンを度数法に変換します。
///
/// - Parameter radians: ラジアン単位の角度。
/// - Returns: 度数法の角度。
public func degrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

// MARK: - Interpolation

/// 2つの値の間を線形補間します。
///
/// - Parameters:
///   - a: 開始値。
///   - b: 終了値。
///   - t: 補間係数。通常 [0, 1] の範囲。
/// - Returns: 補間された値。
public func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    a + (b - a) * t
}

/// 2つの2Dベクトルの間を線形補間します。
///
/// - Parameters:
///   - a: 開始ベクトル。
///   - b: 終了ベクトル。
///   - t: 補間係数。通常 [0, 1] の範囲。
/// - Returns: 補間されたベクトル。
public func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

/// 2つの3Dベクトルの間を線形補間します。
///
/// - Parameters:
///   - a: 開始ベクトル。
///   - b: 終了ベクトル。
///   - t: 補間係数。通常 [0, 1] の範囲。
/// - Returns: 補間されたベクトル。
public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// 2つの4Dベクトルの間を線形補間します。
///
/// - Parameters:
///   - a: 開始ベクトル。
///   - b: 終了ベクトル。
///   - t: 補間係数。通常 [0, 1] の範囲。
/// - Returns: 補間されたベクトル。
public func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    a + (b - a) * t
}

/// 値を [0, 1] の範囲にクランプします。
///
/// - Parameter x: クランプする値。
/// - Returns: クランプされた値。
public func saturate(_ x: Float) -> Float {
    min(max(x, 0), 1)
}

/// 2つのエッジ間でエルミート補間を行います。
///
/// `x` が `edge0` より小さい場合は 0、`edge1` より大きい場合は 1 を返し、
/// それ以外の場合は 0 から 1 の間の滑らかなエルミート補間値を返します。
///
/// - Parameters:
///   - edge0: 遷移の下端エッジ。
///   - edge1: 遷移の上端エッジ。
///   - x: 入力値。
/// - Returns: [0, 1] の範囲で滑らかに補間された値。
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = saturate((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

// MARK: - Mapping & Clamping

/// 値をある範囲から別の範囲にリマップします。
///
/// - Parameters:
///   - value: リマップする入力値。
///   - start1: 元の範囲の下限。
///   - stop1: 元の範囲の上限。
///   - start2: 変換先の範囲の下限。
///   - stop2: 変換先の範囲の上限。
/// - Returns: リマップされた値。
public func map(_ value: Float, _ start1: Float, _ stop1: Float, _ start2: Float, _ stop2: Float) -> Float {
    start2 + (stop2 - start2) * ((value - start1) / (stop1 - start1))
}

/// 値を指定された範囲に制約します。
///
/// - Parameters:
///   - value: 制約する値。
///   - low: 許容される最小値。
///   - high: 許容される最大値。
/// - Returns: 制約された値。
public func constrain(_ value: Float, _ low: Float, _ high: Float) -> Float {
    min(max(value, low), high)
}

/// 値を指定された範囲から [0, 1] の範囲に正規化します。
///
/// - Parameters:
///   - value: 正規化する値。
///   - start: 元の範囲の下限。
///   - stop: 元の範囲の上限。
/// - Returns: 正規化された値。
public func norm(_ value: Float, _ start: Float, _ stop: Float) -> Float {
    (value - start) / (stop - start)
}

// MARK: - Distance & Magnitude

/// 2つの2D点間のユークリッド距離を計算します。
///
/// - Parameters:
///   - x1: 1番目の点のx座標。
///   - y1: 1番目の点のy座標。
///   - x2: 2番目の点のx座標。
///   - y2: 2番目の点のy座標。
/// - Returns: 2点間の距離。
public func dist(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    return sqrt(dx * dx + dy * dy)
}

/// 2つの3D点間のユークリッド距離を計算します。
///
/// - Parameters:
///   - x1: 1番目の点のx座標。
///   - y1: 1番目の点のy座標。
///   - z1: 1番目の点のz座標。
///   - x2: 2番目の点のx座標。
///   - y2: 2番目の点のy座標。
///   - z2: 2番目の点のz座標。
/// - Returns: 2点間の距離。
public func dist(_ x1: Float, _ y1: Float, _ z1: Float, _ x2: Float, _ y2: Float, _ z2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    let dz = z2 - z1
    return sqrt(dx * dx + dy * dy + dz * dz)
}

/// 値の二乗を計算します。
///
/// - Parameter value: 二乗する値。
/// - Returns: 二乗された値。
public func sq(_ value: Float) -> Float {
    value * value
}

/// 2Dベクトルの大きさを計算します。
///
/// - Parameters:
///   - x: ベクトルのx成分。
///   - y: ベクトルのy成分。
/// - Returns: ベクトルの大きさ（長さ）。
public func mag(_ x: Float, _ y: Float) -> Float {
    sqrt(x * x + y * y)
}

/// 3Dベクトルの大きさを計算します。
///
/// - Parameters:
///   - x: ベクトルのx成分。
///   - y: ベクトルのy成分。
///   - z: ベクトルのz成分。
/// - Returns: ベクトルの大きさ（長さ）。
public func mag(_ x: Float, _ y: Float, _ z: Float) -> Float {
    sqrt(x * x + y * y + z * z)
}

// MARK: - Random

/// 線形合同法に基づくシード指定可能な乱数生成器。
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@MainActor
private var _seededRNG: SeededRandomNumberGenerator?

/// 0 から指定された上限（上限を含まない）までのランダムな Float 値を返します。
///
/// - Parameter high: 上限（この値を含まない）。
/// - Returns: [0, `high`) の範囲のランダムな Float 値。
@MainActor
public func random(_ high: Float) -> Float {
    random(0, high)
}

/// 指定された範囲内のランダムな Float 値を返します。
///
/// - Parameters:
///   - low: 下限（この値を含む）。
///   - high: 上限（この値を含まない）。
/// - Returns: [`low`, `high`) の範囲のランダムな Float 値。
@MainActor
public func random(_ low: Float, _ high: Float) -> Float {
    let lo = min(low, high)
    let hi = max(low, high)
    guard lo < hi else { return lo }
    if var rng = _seededRNG {
        let result = Float.random(in: lo..<hi, using: &rng)
        _seededRNG = rng
        return result
    }
    return Float.random(in: lo..<hi)
}

/// 乱数生成器のシードを設定します。
///
/// 以降の ``random(_:)`` および ``random(_:_:)`` の呼び出しは、このシードを使用して
/// 決定論的な乱数列を生成します。
///
/// - Parameter seed: シード値。
@MainActor
public func randomSeed(_ seed: UInt64) {
    _seededRNG = SeededRandomNumberGenerator(seed: seed)
}

/// Box-Muller 変換を使用してガウス（正規）分布に従うランダムな値を返します。
///
/// - Parameters:
///   - mean: 分布の平均値（デフォルトは 0）。
///   - sd: 分布の標準偏差（デフォルトは 1）。
/// - Returns: 指定されたガウス分布から抽出されたランダムな Float 値。
@MainActor
public func randomGaussian(_ mean: Float = 0, _ sd: Float = 1) -> Float {
    let u1 = random(Float.leastNormalMagnitude, 1.0)
    let u2 = random(0, 1.0)
    let z = sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
    return mean + z * sd
}

// MARK: - Bezier Math

/// 指定されたパラメータにおける3次ベジェ曲線上の点を評価します。
///
/// - Parameters:
///   - a: 1番目の制御点（始点）。
///   - b: 2番目の制御点。
///   - c: 3番目の制御点。
///   - d: 4番目の制御点（終点）。
///   - t: 曲線上のパラメータ。通常 [0, 1] の範囲。
/// - Returns: パラメータ `t` におけるベジェ曲線上の値。
public func bezierPoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
}

/// 指定されたパラメータにおける3次ベジェ曲線の接線を評価します。
///
/// - Parameters:
///   - a: 1番目の制御点（始点）。
///   - b: 2番目の制御点。
///   - c: 3番目の制御点。
///   - d: 4番目の制御点（終点）。
///   - t: 曲線上のパラメータ。通常 [0, 1] の範囲。
/// - Returns: パラメータ `t` におけるベジェ曲線の接線値。
public func bezierTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
}

// MARK: - Catmull-Rom Curve Math

/// 指定されたパラメータにおける Catmull-Rom スプライン上の点を評価します。
///
/// - Parameters:
///   - a: 1番目の制御点。
///   - b: 2番目の制御点（`t = 0` でこの点を通過）。
///   - c: 3番目の制御点（`t = 1` でこの点を通過）。
///   - d: 4番目の制御点。
///   - t: スプライン上のパラメータ。通常 [0, 1] の範囲。
/// - Returns: パラメータ `t` における Catmull-Rom スプライン上の値。
public func curvePoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    let t3 = t2 * t
    return 0.5 * ((2 * b) +
                   (-a + c) * t +
                   (2 * a - 5 * b + 4 * c - d) * t2 +
                   (-a + 3 * b - 3 * c + d) * t3)
}

/// 指定されたパラメータにおける Catmull-Rom スプラインの接線を評価します。
///
/// - Parameters:
///   - a: 1番目の制御点。
///   - b: 2番目の制御点。
///   - c: 3番目の制御点。
///   - d: 4番目の制御点。
///   - t: スプライン上のパラメータ。通常 [0, 1] の範囲。
/// - Returns: パラメータ `t` における Catmull-Rom スプラインの接線値。
public func curveTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    return 0.5 * ((-a + c) +
                   (4 * a - 10 * b + 8 * c - 2 * d) * t +
                   (-3 * a + 9 * b - 9 * c + 3 * d) * t2)
}
