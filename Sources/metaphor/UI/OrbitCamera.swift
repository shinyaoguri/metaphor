import simd
import Foundation

/// マウスドラッグによるインタラクティブ 3D カメラオービットコントローラー
///
/// 球面座標系でカメラ位置を管理し、マウスドラッグで回転、スクロールでズームを行う。
///
/// ```swift
/// func draw() {
///     orbitControl()  // 自動でマウスドラッグ → カメラ回転
///     box(100)
/// }
/// ```
@MainActor
public final class OrbitCamera {

    // MARK: - Camera Parameters

    /// 注視点
    public var target: SIMD3<Float> = .zero

    /// カメラ距離
    public var distance: Float = 500

    /// 水平角（ラジアン）
    public var azimuth: Float = 0

    /// 垂直角（ラジアン）
    public var elevation: Float = 0.3

    // MARK: - Sensitivity

    /// マウスドラッグの感度
    public var sensitivity: Float = 0.005

    /// スクロールズームの感度
    public var zoomSensitivity: Float = 0.1

    // MARK: - Limits

    /// 最小距離
    public var minDistance: Float = 1.0

    /// 最大距離
    public var maxDistance: Float = 10000.0

    /// 最小仰角
    public var minElevation: Float = -Float.pi / 2 + 0.01

    /// 最大仰角
    public var maxElevation: Float = Float.pi / 2 - 0.01

    // MARK: - Damping

    /// ダンピング係数（0 = ダンピングなし、1 に近いほど慣性が強い）
    public var damping: Float = 0

    private var velocityAzimuth: Float = 0
    private var velocityElevation: Float = 0

    // MARK: - Computed Properties

    /// カメラの位置（球面座標 → 直交座標）
    public var eye: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    /// カメラのアップベクトル
    public var up: SIMD3<Float> {
        SIMD3(0, 1, 0)
    }

    public init() {}

    /// カスタム初期設定
    public init(distance: Float, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
    }

    // MARK: - Input Handling

    /// マウスドラッグを処理
    /// - Parameters:
    ///   - dx: X方向のドラッグ量（ピクセル）
    ///   - dy: Y方向のドラッグ量（ピクセル）
    public func handleMouseDrag(dx: Float, dy: Float) {
        let dAzimuth = -dx * sensitivity
        let dElevation = dy * sensitivity

        if damping > 0 {
            velocityAzimuth += dAzimuth
            velocityElevation += dElevation
        } else {
            azimuth += dAzimuth
            elevation += dElevation
            elevation = max(minElevation, min(maxElevation, elevation))
        }
    }

    /// スクロール（ズーム）を処理
    /// - Parameter delta: スクロール量
    public func handleScroll(delta: Float) {
        distance -= delta * zoomSensitivity * distance * 0.01
        distance = max(minDistance, min(maxDistance, distance))
    }

    /// ダンピング更新（毎フレーム呼ぶ）
    public func update() {
        guard damping > 0 else { return }

        azimuth += velocityAzimuth
        elevation += velocityElevation
        elevation = max(minElevation, min(maxElevation, elevation))

        velocityAzimuth *= damping
        velocityElevation *= damping

        // 微小な速度はゼロに
        if abs(velocityAzimuth) < 0.0001 { velocityAzimuth = 0 }
        if abs(velocityElevation) < 0.0001 { velocityElevation = 0 }
    }

    /// カメラをリセット
    public func reset(distance: Float = 500, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.velocityAzimuth = 0
        self.velocityElevation = 0
    }
}
