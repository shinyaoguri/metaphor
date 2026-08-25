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

    /// How far a drag rotates the camera, in radians per pixel.
    ///
    /// Independent of ``damping``: one pixel of drag turns the camera by this
    /// much whether or not damping is on.
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

    /// Inertia: how long the camera keeps gliding after you let go.
    ///
    /// `0` stops it the moment you let go; values closer to `1` glide longer.
    ///
    /// This sets **only how long the glide lasts**. How far a drag rotates the
    /// camera is decided by ``sensitivity`` alone and does not change when you
    /// raise or lower this value (Issue #1099).
    ///
    /// The useful range is `0 ..< 1`. Reading the property gives back whatever
    /// you assigned, but a value of `1` or more is treated as slightly less
    /// than `1` internally, because a glide that never decays never stops.
    ///
    /// Setting it to `0` also throws away any glide already in flight: no
    /// inertia means there is nothing left to carry. Keeping it would freeze
    /// the glide instead — ``update()`` returns early while damping is off, so
    /// the stored speed never decays — and the camera would take off on its own
    /// the moment you raised the value again, however long you waited in
    /// between (Issue #1128).
    public var damping: Float = 0 {
        didSet {
            if damping <= 0 { stopGlide() }
        }
    }

    /// ``damping`` clamped to `[0, 1)`, which is what the math actually uses.
    ///
    /// The upper bound stays below `1` because at exactly `1` the
    /// ``handleMouseDrag(dx:dy:)`` gain of `1 - damping` would be zero and no
    /// input would ever reach the camera.
    private var effectiveDamping: Float {
        min(max(damping, 0), 0.999)
    }

    /// Y軸周りの現在の回転速度
    private var velocityAzimuth: Float = 0
    /// 水平軸周りの現在の回転速度
    private var velocityElevation: Float = 0

    /// Throws away the glide, leaving both angles where they are.
    ///
    /// The velocities are only ever written while ``damping`` is above zero
    /// (``handleMouseDrag(dx:dy:)`` guards on it and ``update()`` returns before
    /// touching them), so dropping them here keeps "no damping means no stored
    /// speed" true at every point (Issue #1128).
    private func stopGlide() {
        velocityAzimuth = 0
        velocityElevation = 0
    }

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

    /// Rotates the camera by one drag delta.
    ///
    /// With ``damping`` on, the delta goes into the velocity rather than
    /// straight into the angles, scaled by `1 - damping` to cancel the gain of
    /// the integration that follows. ``update()`` adds the velocity to the
    /// angles every frame and then decays it, so one input eventually turns the
    /// camera by `d * (1 - damping) * (1 + damping + damping^2 + ...) = d` —
    /// the same amount as with no damping at all. Without the scaling the total
    /// would grow by `1 / (1 - damping)` (Issue #1099).
    ///
    /// - Parameters:
    ///   - dx: Horizontal drag distance, in pixels.
    ///   - dy: Vertical drag distance, in pixels.
    public func handleMouseDrag(dx: Float, dy: Float) {
        let dAzimuth = -dx * sensitivity
        let dElevation = -dy * sensitivity

        if damping > 0 {
            // 減衰しながら積分される分の利得を、入力側で先に打ち消す
            let gain = 1 - effectiveDamping
            velocityAzimuth += dAzimuth * gain
            velocityElevation += dElevation * gain
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

    /// Advances the camera by one frame of damped motion. Call it every frame.
    ///
    /// With ``damping`` off there is nothing to advance: the angles are already
    /// current, because ``handleMouseDrag(dx:dy:)`` wrote straight into them.
    ///
    /// Elevation stops at ``minElevation`` / ``maxElevation``. A frame that runs
    /// into one of those limits drops the elevation velocity along with pinning
    /// the angle, so letting go at the top does not leave the camera pressed
    /// against the limit for the rest of the glide, and a drag back down takes
    /// effect on the very next frame (Issue #1127). Azimuth has no limits and
    /// keeps gliding either way.
    public func update() {
        guard damping > 0 else { return }

        azimuth += velocityAzimuth

        // 壁に当たったら止まる。角度だけ丸めて速度を残すと、手を離したあとも
        // 数百 ms のあいだカメラが上下限を押し続け、逆向きのドラッグは残った
        // 速度を打ち消すまで効かない（#1127）。判定は clamp の前後の比較で取る
        // ので、丸めが起きなかったフレーム（壁のちょうど手前）の余韻は残る。
        let unclampedElevation = elevation + velocityElevation
        elevation = max(minElevation, min(maxElevation, unclampedElevation))
        if elevation != unclampedElevation {
            velocityElevation = 0
        }

        let decay = effectiveDamping
        velocityAzimuth *= decay
        velocityElevation *= decay

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
        stopGlide()
    }
}
