// MARK: - 3D Drawing (Camera, Lighting, Material, Shapes, Transform)

extension Sketch {

    // MARK: 3D Custom Shapes

    /// 3D カスタムシェイプの頂点記録を開始します。
    ///
    /// - Parameter mode: シェイプモード（例: polygon、triangles、lines）。
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        context.beginShape3D(mode)
    }

    /// 現在のシェイプに 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        context.vertex(x, y, z)
    }

    /// 現在のシェイプに頂点カラー付き 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        context.vertex(x, y, z, color)
    }

    /// 以降の 3D 頂点の法線ベクトルを設定します。
    ///
    /// - Parameters:
    ///   - nx: 法線の x 成分。
    ///   - ny: 法線の y 成分。
    ///   - nz: 法線の z 成分。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        context.normal(nx, ny, nz)
    }

    /// 現在の 3D シェイプの記録を終了し描画します。
    ///
    /// - Parameter close: 最後の頂点と最初の頂点を接続してシェイプを閉じるかどうか。
    public func endShape3D(_ close: CloseMode = .open) {
        context.endShape3D(close)
    }

    // MARK: 3D Camera

    /// eye、center、up ベクトルで 3D カメラを設定します。
    ///
    /// - Parameters:
    ///   - eye: カメラの位置。
    ///   - center: カメラが注視する点。
    ///   - up: 上方向ベクトル。
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        context.camera(eye: eye, center: center, up: up)
    }

    /// 個別の float 成分で 3D カメラを設定します。
    ///
    /// - Parameters:
    ///   - eyeX: カメラ位置の x 座標。
    ///   - eyeY: カメラ位置の y 座標。
    ///   - eyeZ: カメラ位置の z 座標。
    ///   - centerX: 注視点の x 座標。
    ///   - centerY: 注視点の y 座標。
    ///   - centerZ: 注視点の z 座標。
    ///   - upX: 上方向ベクトルの x 成分。
    ///   - upY: 上方向ベクトルの y 成分。
    ///   - upZ: 上方向ベクトルの z 成分。
    @available(*, deprecated, message: "Use camera(eye:center:up:) with SIMD3 instead")
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        context.camera(
            eye: SIMD3(eyeX, eyeY, eyeZ),
            center: SIMD3(centerX, centerY, centerZ),
            up: SIMD3(upX, upY, upZ)
        )
    }

    /// 透視投影を設定します。
    ///
    /// - Parameters:
    ///   - fov: ラジアン単位の視野角。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        context.perspective(fov: fov, near: near, far: far)
    }

    /// 正射影を設定します。
    ///
    /// - Parameters:
    ///   - left: 左クリッピング面（デフォルトはキャンバス境界）。
    ///   - right: 右クリッピング面（デフォルトはキャンバス境界）。
    ///   - bottom: 下クリッピング面（デフォルトはキャンバス境界）。
    ///   - top: 上クリッピング面（デフォルトはキャンバス境界）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        context.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    /// デフォルトライティング（ディレクショナルライトとアンビエントライト）を有効にします。
    public func lights() {
        context.lights()
    }

    /// すべてのライトを無効にします。
    public func noLights() {
        context.noLights()
    }

    /// デフォルト色のディレクショナルライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト方向の x 成分。
    ///   - y: ライト方向の y 成分。
    ///   - z: ライト方向の z 成分。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        context.directionalLight(x, y, z)
    }

    /// 色を指定してディレクショナルライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト方向の x 成分。
    ///   - y: ライト方向の y 成分。
    ///   - z: ライト方向の z 成分。
    ///   - color: ライトの色。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        context.directionalLight(x, y, z, color: color)
    }

    /// 指定位置にポイントライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置の x 座標。
    ///   - y: ライト位置の y 座標。
    ///   - z: ライト位置の z 座標。
    ///   - color: ライトの色。
    ///   - falloff: 減衰係数。
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        context.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// 指定位置・方向にスポットライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置の x 座標。
    ///   - y: ライト位置の y 座標。
    ///   - z: ライト位置の z 座標。
    ///   - dirX: ライト方向の x 成分。
    ///   - dirY: ライト方向の y 成分。
    ///   - dirZ: ライト方向の z 成分。
    ///   - angle: ラジアン単位のコーン角度。
    ///   - falloff: 減衰係数。
    ///   - color: ライトの色。
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        context.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// グレースケール値でアンビエントライトの強度を設定します。
    ///
    /// - Parameter strength: アンビエントライトの強度。
    public func ambientLight(_ strength: Float) {
        context.ambientLight(strength)
    }

    /// RGB 値でアンビエントライトの色を設定します。
    ///
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        context.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// シャドウマッピングを有効にします。
    ///
    /// - Parameter resolution: シャドウマップの解像度（ピクセル単位）。
    public func enableShadows(resolution: Int = 2048) {
        context.enableShadows(resolution: resolution)
    }

    /// シャドウマッピングを無効にします。
    public func disableShadows() {
        context.disableShadows()
    }

    /// シャドウアクネを軽減するためのシャドウデプスバイアスを設定します。
    ///
    /// - Parameter value: バイアス値。
    public func shadowBias(_ value: Float) {
        context.shadowBias(value)
    }

    // MARK: 3D Material

    /// スペキュラーハイライトの色を設定します。
    ///
    /// - Parameter color: スペキュラー色。
    public func specular(_ color: Color) {
        context.specular(color)
    }

    /// グレースケール値でスペキュラーハイライトの色を設定します。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func specular(_ gray: Float) {
        context.specular(gray)
    }

    /// スペキュラーの光沢度指数を設定します。
    ///
    /// - Parameter value: 光沢度（値が大きいほどハイライトが小さくなります）。
    public func shininess(_ value: Float) {
        context.shininess(value)
    }

    /// エミッシブ（自己発光）色を設定します。
    ///
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) {
        context.emissive(color)
    }

    /// グレースケール値でエミッシブ色を設定します。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func emissive(_ gray: Float) {
        context.emissive(gray)
    }

    /// マテリアルのメタリック係数を設定します。
    ///
    /// - Parameter value: メタリック値（0 = 誘電体、1 = 金属）。
    public func metallic(_ value: Float) {
        context.metallic(value)
    }

    /// PBR ラフネスを設定します（自動的に PBR モードに切り替わります）。
    ///
    /// - Parameter value: ラフネス値（0 = 滑らか、1 = 粗い）。
    public func roughness(_ value: Float) {
        context.roughness(value)
    }

    /// PBR アンビエントオクルージョン係数を設定します。
    ///
    /// - Parameter value: アンビエントオクルージョン値（0 = 完全に遮蔽、1 = 遮蔽なし）。
    public func ambientOcclusion(_ value: Float) {
        context.ambientOcclusion(value)
    }

    /// PBR レンダリングモードを明示的に切り替えます。
    ///
    /// - Parameter enabled: PBR レンダリングを有効にするかどうか。
    public func pbr(_ enabled: Bool) {
        context.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// MSL ソースコードからカスタムシェーダーマテリアルを作成します。
    ///
    /// - Parameters:
    ///   - source: Metal Shading Language のソースコード。
    ///   - fragmentFunction: フラグメント関数の名前。
    ///   - vertexFunction: カスタム頂点関数の名前（オプション）。
    /// - Returns: 新しい ``CustomMaterial`` インスタンス。
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try context.createMaterial(source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// カスタムマテリアルを以降の 3D 描画に適用します。
    ///
    /// - Parameter customMaterial: 適用するカスタムマテリアル。
    public func material(_ customMaterial: CustomMaterial) {
        context.material(customMaterial)
    }

    /// アクティブなカスタムマテリアルを解除しデフォルトシェーディングに戻します。
    public func noMaterial() {
        context.noMaterial()
    }

    // MARK: 3D Texture

    /// 以降の 3D シェイプのテクスチャを設定します。
    ///
    /// - Parameter img: テクスチャ画像。
    public func texture(_ img: MImage) {
        context.texture(img)
    }

    /// アクティブなテクスチャを解除します。
    public func noTexture() {
        context.noTexture()
    }

    // MARK: 3D Transform Stack

    /// 現在の 3D 変換行列をスタックに保存します。
    public func pushMatrix() {
        context.pushMatrix()
    }

    /// 最後に保存された 3D 変換行列をスタックから復元します。
    public func popMatrix() {
        context.popMatrix()
    }

    /// 現在の変換に 3D 平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: x 軸方向の移動量。
    ///   - y: y 軸方向の移動量。
    ///   - z: z 軸方向の移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        context.translate(x, y, z)
    }

    /// x 軸周りの回転を適用します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateX(_ angle: Float) {
        context.rotateX(angle)
    }

    /// y 軸周りの回転を適用します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateY(_ angle: Float) {
        context.rotateY(angle)
    }

    /// z 軸周りの回転を適用します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateZ(_ angle: Float) {
        context.rotateZ(angle)
    }

    /// 現在の変換に非均一 3D スケールを適用します。
    ///
    /// - Parameters:
    ///   - x: x 軸方向のスケール係数。
    ///   - y: y 軸方向のスケール係数。
    ///   - z: z 軸方向のスケール係数。
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        context.scale(x, y, z)
    }

    // MARK: 3D Shapes

    /// 指定したサイズのボックスを描画します。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        context.box(width, height, depth)
    }

    /// 辺の長さが等しいキューブを描画します。
    ///
    /// - Parameter size: 辺の長さ。
    public func box(_ size: Float) {
        context.box(size)
    }

    /// 球を描画します。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: メッシュテッセレーションの分割数。
    public func sphere(_ radius: Float, detail: Int = 24) {
        context.sphere(radius, detail: detail)
    }

    /// 平面を描画します。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    public func plane(_ width: Float, _ height: Float) {
        context.plane(width, height)
    }

    /// 円柱を描画します。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 円周方向の分割数。
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        context.cylinder(radius: radius, height: height, detail: detail)
    }

    /// 円錐を描画します。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 円周方向の分割数。
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        context.cone(radius: radius, height: height, detail: detail)
    }

    /// トーラス（ドーナツ形状）を描画します。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブの中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: 分割数。
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        context.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// ビルド済みメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するメッシュ。
    public func mesh(_ mesh: Mesh) {
        context.mesh(mesh)
    }

    /// ダイナミックメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するダイナミックメッシュ。
    public func dynamicMesh(_ mesh: DynamicMesh) {
        context.dynamicMesh(mesh)
    }

    /// 新しい空のダイナミックメッシュを作成します。
    ///
    /// - Returns: 新しい ``DynamicMesh`` インスタンス。
    public func createDynamicMesh() -> DynamicMesh {
        context.createDynamicMesh()
    }

    /// ファイルから 3D モデルを読み込みます（OBJ、USDZ、ABC）。
    ///
    /// - Parameter path: モデルのファイルパス。
    /// - Returns: 読み込まれたメッシュ。読み込みに失敗した場合は `nil`。
    public func loadModel(_ path: String) -> Mesh? {
        context.loadModel(path)
    }

    /// 3D モデルを非同期で読み込みます（パース処理をメインスレッド外で実行）。
    ///
    /// - Parameters:
    ///   - path: モデルのファイルパス。
    ///   - normalize: バウンディングボックスを正規化するかどうか（デフォルトは `true`）。
    /// - Returns: 読み込まれたメッシュ。
    public func loadModelAsync(_ path: String, normalize: Bool = true) async throws -> Mesh {
        try await context.resourceLoader.loadModelAsync(path: path, normalize: normalize)
    }
}
