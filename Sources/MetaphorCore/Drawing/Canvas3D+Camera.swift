import Metal
import simd

extension Canvas3D {
    // MARK: - パブリックカメラアクセサ

    /// 現在のビュー投影行列を返します。
    public var currentViewProjection: float4x4 {
        computeViewProjection()
    }

    /// カメラの右方向ベクトルを返します。ビルボーディングに便利です。
    public var currentCameraRight: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        return normalize(cross(cameraUp, z))
    }

    /// カメラの上方向ベクトルを返します。ビルボーディングに便利です。
    public var currentCameraUp: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        let x = normalize(cross(cameraUp, z))
        return cross(z, x)
    }

    // MARK: - カメラ

    /// カメラの位置と向きを設定します。
    ///
    /// - Parameters:
    ///   - eye: ワールド空間でのカメラ位置。
    ///   - center: カメラの注視点。
    ///   - up: 上方向ベクトル。
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        // ビュー投影とライトはフラッシュ時にバッチへ適用されるため、
        // すでに送信済みのシェイプは「送信時点の」カメラ／ライトで描画
        // されなければならない。状態を変更する前に保留分を確定する。
        flushInstanceBatch()
        self.cameraEye = eye
        self.cameraCenter = center
        self.cameraUp = up
        self.viewProjectionDirty = true
    }

    /// 透視投影パラメータを設定します。
    ///
    /// - Parameters:
    ///   - fov: 垂直視野角（ラジアン）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func perspective(
        fov: Float = Float.pi / 3,
        near: Float = 0.1,
        far: Float = 10000
    ) {
        flushInstanceBatch()  // 送信済みシェイプを変更前の投影で確定
        self.fov = fov
        self.nearPlane = near
        self.farPlane = far
        self.useOrthographic = false
        self.viewProjectionDirty = true
    }

    /// 正射影に切り替えます。
    ///
    /// - Parameters:
    ///   - left: ビューボリュームの左端（`nil` の場合デフォルト 0）。
    ///   - right: ビューボリュームの右端（`nil` の場合デフォルトはキャンバス幅）。
    ///   - bottom: ビューボリュームの下端（`nil` の場合デフォルトはキャンバス高さ）。
    ///   - top: ビューボリュームの上端（`nil` の場合デフォルト 0）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        flushInstanceBatch()  // 送信済みシェイプを変更前の投影で確定
        self.useOrthographic = true
        self.orthoLeft = left ?? 0
        self.orthoRight = right ?? width
        self.orthoBottom = bottom ?? height
        self.orthoTop = top ?? 0
        self.nearPlane = near
        self.farPlane = far
        self.viewProjectionDirty = true
    }
}
