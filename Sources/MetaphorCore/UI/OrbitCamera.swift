import simd
import Foundation

/// マウスドラッグとスクロールで3Dカメラオービットをインタラクティブに制御します。
///
/// 球面座標でカメラ位置を管理します。マウスドラッグでカメラがターゲットの周りを
/// 回転し、スクロール入力でズーム距離を調整します。
///
/// ```swift
/// func draw() {
///     orbitControl()  // automatically maps mouse drag to camera rotation
///     box(100)
/// }
/// ```
@MainActor
public final class OrbitCamera {

    // MARK: - Camera Parameters

    /// カメラが注視する点
    public var target: SIMD3<Float> = .zero

    /// カメラからターゲットまでの距離
    public var distance: Float = 500

    /// 水平方向の角度（ラジアン、Y軸周りの回転）
    public var azimuth: Float = 0

    /// 垂直方向の角度（ラジアン、水平面からの上下回転）
    public var elevation: Float = 0.3

    // MARK: - Sensitivity

    /// マウスドラッグ回転の感度
    public var sensitivity: Float = 0.005

    /// スクロールホイールズームの感度
    public var zoomSensitivity: Float = 0.1

    // MARK: - Limits

    /// ターゲットからの最小許容距離
    public var minDistance: Float = 1.0

    /// ターゲットからの最大許容距離
    public var maxDistance: Float = 10000.0

    /// 最小仰角（ラジアン）
    public var minElevation: Float = -Float.pi / 2 + 0.01

    /// 最大仰角（ラジアン）
    public var maxElevation: Float = Float.pi / 2 - 0.01

    // MARK: - Damping

    /// ダンピング係数（0 = ダンピングなし、1に近いほど慣性が強い）
    public var damping: Float = 0

    /// Y軸周りの現在の回転速度
    private var velocityAzimuth: Float = 0
    /// 水平軸周りの現在の回転速度
    private var velocityElevation: Float = 0

    // MARK: - Computed Properties

    /// 球面座標をデカルト座標に変換してカメラ位置を計算します。
    public var eye: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    /// カメラの上方向ベクトル
    public var up: SIMD3<Float> {
        SIMD3(0, 1, 0)
    }

    /// デフォルトパラメータで新しい OrbitCamera を作成します。
    public init() {}

    /// カスタム初期設定で新しい OrbitCamera を作成します。
    /// - Parameters:
    ///   - distance: ターゲットからの初期距離。
    ///   - azimuth: 初期水平角度（ラジアン、デフォルト: 0）。
    ///   - elevation: 初期垂直角度（ラジアン、デフォルト: 0.3）。
    public init(distance: Float, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
    }

    // MARK: - Input Handling

    /// マウスドラッグの差分を適用してカメラを回転させます。
    /// - Parameters:
    ///   - dx: 水平ドラッグ量（ピクセル）。
    ///   - dy: 垂直ドラッグ量（ピクセル）。
    public func handleMouseDrag(dx: Float, dy: Float) {
        let dAzimuth = -dx * sensitivity
        let dElevation = -dy * sensitivity

        if damping > 0 {
            velocityAzimuth += dAzimuth
            velocityElevation += dElevation
        } else {
            azimuth += dAzimuth
            elevation += dElevation
            elevation = max(minElevation, min(maxElevation, elevation))
        }
    }

    /// スクロール入力を適用してズーム距離を調整します。
    /// - Parameter delta: スクロールデルタ値。
    public func handleScroll(delta: Float) {
        distance -= delta * zoomSensitivity * distance * 0.01
        distance = max(minDistance, min(maxDistance, distance))
    }

    /// 速度にダンピングを適用し角度を更新します（毎フレーム呼び出し）。
    public func update() {
        guard damping > 0 else { return }

        azimuth += velocityAzimuth
        elevation += velocityElevation
        elevation = max(minElevation, min(maxElevation, elevation))

        velocityAzimuth *= damping
        velocityElevation *= damping

        // 無視できる速度をゼロに設定
        if abs(velocityAzimuth) < 0.0001 { velocityAzimuth = 0 }
        if abs(velocityElevation) < 0.0001 { velocityElevation = 0 }
    }

    /// カメラを指定された状態にリセットします。
    /// - Parameters:
    ///   - distance: リセット先の距離（デフォルト: 500）。
    ///   - azimuth: リセット先の方位角（デフォルト: 0）。
    ///   - elevation: リセット先の仰角（デフォルト: 0.3）。
    public func reset(distance: Float = 500, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.velocityAzimuth = 0
        self.velocityElevation = 0
    }
}
