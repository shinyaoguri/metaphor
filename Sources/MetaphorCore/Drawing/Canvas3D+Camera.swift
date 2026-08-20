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

    /// Processing 風の既定カメラがキャンバス中央を写す距離。
    ///
    /// 垂直視野角 ``Canvas3D/defaultFov`` でキャンバスの高さがちょうど収まる z で、
    /// `begin()` が毎フレーム入れ直すカメラ位置の z 成分にあたる。投影の既定値は
    /// この距離を基準に決める（`ortho()` の省略時 near/far もここから導く。#777）。
    var defaultCameraZ: Float {
        (height / 2) / tan(Canvas3D.defaultFov / 2)
    }

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
    /// 省略した面は**既定カメラと噛み合う範囲**で埋まります。正射影は `proj * view` の
    /// 順で**ビュー空間**に効くのに対し、既定カメラはキャンバス中央を注視しているため、
    /// ビュー空間の原点は画面中央にあります。そこで省略時の範囲も原点を挟む形
    /// （`-width / 2 … width / 2` / `-height / 2 … height / 2`）にし、`ortho()` を
    /// 単独で呼ぶだけで 2D と同じピクセル座標の平行投影になるようにしています（#777）。
    ///
    /// - Important: `bottom` / `top` は投影行列の規約どおり「ビュー空間の y が
    ///   **小さい**側が `bottom`」です。metaphor の y は 2D と同じく画面下向きなので、
    ///   `bottom` は画面の**上端**、`top` は**下端**に対応します。上下を逆に渡すと
    ///   絵が上下反転します（透視投影・2D と向きが揃わなくなる）。
    ///
    /// - Parameters:
    ///   - left: ビューボリュームの左端（`nil` の場合 `-width / 2`）。
    ///   - right: ビューボリュームの右端（`nil` の場合 `width / 2`）。
    ///   - bottom: ビューボリュームの下端（`nil` の場合 `-height / 2`）。
    ///   - top: ビューボリュームの上端（`nil` の場合 `height / 2`）。
    ///   - near: ニアクリッピング面の距離（`nil` の場合 `-defaultCameraZ * 10`）。
    ///   - far: ファークリッピング面の距離（`nil` の場合 `defaultCameraZ * 10`）。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float? = nil, far: Float? = nil
    ) {
        flushInstanceBatch()  // 送信済みシェイプを変更前の投影で確定
        // 深さも既定カメラ基準。ビュー z は `-defaultCameraZ` を中心に散るので、
        // 固定の ±1000 では少し奥に置いたものがクリップされていた（#777）。
        // 透視投影の既定 far（defaultCameraZ * 10）と同じ奥行きまでを、
        // 原点を挟む対称範囲で覆う。
        let depth = defaultCameraZ * 10
        self.useOrthographic = true
        self.orthoLeft = left ?? -width / 2
        self.orthoRight = right ?? width / 2
        self.orthoBottom = bottom ?? -height / 2
        self.orthoTop = top ?? height / 2
        self.nearPlane = near ?? -depth
        self.farPlane = far ?? depth
        self.viewProjectionDirty = true
    }
}
