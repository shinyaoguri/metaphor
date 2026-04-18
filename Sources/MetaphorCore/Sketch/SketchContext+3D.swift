import Metal
import simd

extension SketchContext {

    // MARK: - 3D Custom Shapes (beginShape / endShape)

    /// 3D 頂点ベースのカスタムシェイプの記録を開始します。
    /// - Parameter mode: シェイプの描画モード（デフォルト `.polygon`）。
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        canvas3D.beginShape(mode)
    }

    /// 現在のシェイプに 3D 頂点を追加します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.vertex(x, y, z)
    }

    /// 頂点カラー付き 3D 頂点を追加します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        canvas3D.vertex(x, y, z, color)
    }

    /// 次の 3D 頂点の法線ベクトルを設定します。
    /// - Parameters:
    ///   - nx: 法線の x 成分。
    ///   - ny: 法線の y 成分。
    ///   - nz: 法線の z 成分。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        canvas3D.normal(nx, ny, nz)
    }

    /// 3D シェイプの記録を終了し描画します。
    /// - Parameter close: シェイプを閉じるかどうか（デフォルト `.open`）。
    public func endShape3D(_ close: CloseMode = .open) {
        canvas3D.endShape(close)
    }

    /// 4点を通る Catmull-Rom スプラインカーブを描画します。
    /// - Parameters:
    ///   - x1: 第1ガイドポイントの x 座標。
    ///   - y1: 第1ガイドポイントの y 座標。
    ///   - x2: 可視カーブ始点の x 座標。
    ///   - y2: 可視カーブ始点の y 座標。
    ///   - x3: 可視カーブ終点の x 座標。
    ///   - y3: 可視カーブ終点の y 座標。
    ///   - x4: 第2ガイドポイントの x 座標。
    ///   - y4: 第2ガイドポイントの y 座標。
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    // MARK: - 3D Camera

    /// カメラの位置と方向を設定します。
    /// - Parameters:
    ///   - eye: カメラの位置。
    ///   - center: カメラが注視する点。
    ///   - up: 上方向ベクトル（デフォルト Y-up）。
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        canvas3D.camera(eye: eye, center: center, up: up)
    }

    /// 位置引数でカメラの位置と方向を設定します（p5.js スタイル）。
    /// - Parameters:
    ///   - eyeX: カメラの x 位置。
    ///   - eyeY: カメラの y 位置。
    ///   - eyeZ: カメラの z 位置。
    ///   - centerX: 注視点の x 座標。
    ///   - centerY: 注視点の y 座標。
    ///   - centerZ: 注視点の z 座標。
    ///   - upX: 上方向ベクトルの x 成分。
    ///   - upY: 上方向ベクトルの y 成分。
    ///   - upZ: 上方向ベクトルの z 成分。
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        canvas3D.camera(
            eye: SIMD3(eyeX, eyeY, eyeZ),
            center: SIMD3(centerX, centerY, centerZ),
            up: SIMD3(upX, upY, upZ)
        )
    }

    /// 透視投影を設定します。
    /// - Parameters:
    ///   - fov: ラジアン単位の視野角（デフォルト pi/3）。
    ///   - near: ニアクリッピング面の距離（デフォルト 0.1）。
    ///   - far: ファークリッピング面の距離（デフォルト 10000）。
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        canvas3D.perspective(fov: fov, near: near, far: far)
    }

    /// 正射影に切り替えます。
    /// - Parameters:
    ///   - left: 左クリッピング面（nil の場合はキャンバス境界を使用）。
    ///   - right: 右クリッピング面（nil の場合はキャンバス境界を使用）。
    ///   - bottom: 下クリッピング面（nil の場合はキャンバス境界を使用）。
    ///   - top: 上クリッピング面（nil の場合はキャンバス境界を使用）。
    ///   - near: ニアクリッピング面の距離（デフォルト -1000）。
    ///   - far: ファークリッピング面の距離（デフォルト 1000）。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: - 3D Lighting

    /// デフォルトライティングを有効にします。
    public func lights() {
        canvas3D.lights()
    }

    /// シーンからすべてのライトを削除します。
    public func noLights() {
        canvas3D.noLights()
    }

    /// ディレクショナルライトの方向を設定します。
    /// - Parameters:
    ///   - x: 方向の x 成分。
    ///   - y: 方向の y 成分。
    ///   - z: 方向の z 成分。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// ディレクショナルライトの方向と色を設定します。
    /// - Parameters:
    ///   - x: 方向の x 成分。
    ///   - y: 方向の y 成分。
    ///   - z: 方向の z 成分。
    ///   - color: ライトの色。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// シーンにポイントライトを追加します。
    /// - Parameters:
    ///   - x: ライトの x 位置。
    ///   - y: ライトの y 位置。
    ///   - z: ライトの z 位置。
    ///   - color: ライトの色（デフォルト白）。
    ///   - falloff: 減衰係数（デフォルト 0.1）。
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// シーンにスポットライトを追加します。
    /// - Parameters:
    ///   - x: ライトの x 位置。
    ///   - y: ライトの y 位置。
    ///   - z: ライトの z 位置。
    ///   - dirX: スポットライト方向の x 成分。
    ///   - dirY: スポットライト方向の y 成分。
    ///   - dirZ: スポットライト方向の z 成分。
    ///   - angle: ラジアン単位のコーン角度（デフォルト pi/6）。
    ///   - falloff: 減衰係数（デフォルト 0.01）。
    ///   - color: ライトの色（デフォルト白）。
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// アンビエントライトの強度を設定します。
    /// - Parameter strength: アンビエントライトの強度。
    public func ambientLight(_ strength: Float) {
        canvas3D.ambientLight(strength)
    }

    /// RGB 成分でアンビエントライトの色を設定します。
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        canvas3D.ambientLight(r, g, b)
    }

    // MARK: - Shadow Mapping

    /// シャドウマッピングを有効にします。
    /// - Parameter resolution: シャドウマップの解像度（ピクセル単位、デフォルト 2048）。
    public func enableShadows(resolution: Int = 2048) {
        if canvas3D.shadowMap == nil {
            canvas3D.shadowMap = try? ShadowMap(
                device: renderer.device,
                shaderLibrary: renderer.shaderLibrary,
                resolution: resolution
            )
        }
    }

    /// シャドウマッピングを無効にします。
    public func disableShadows() {
        canvas3D.shadowMap = nil
    }

    /// シャドウアクネを防止するためのシャドウバイアスを設定します。
    /// - Parameter value: バイアス値。
    public func shadowBias(_ value: Float) {
        canvas3D.shadowMap?.shadowBias = value
    }

    // MARK: - 3D Material

    /// スペキュラーハイライトの色を設定します。
    /// - Parameter color: スペキュラー色。
    public func specular(_ color: Color) {
        canvas3D.specular(color)
    }

    /// グレースケール値でスペキュラーハイライトの色を設定します。
    /// - Parameter gray: グレースケールの強度。
    public func specular(_ gray: Float) {
        canvas3D.specular(gray)
    }

    /// スペキュラーの光沢度指数を設定します。
    /// - Parameter value: 光沢度。
    public func shininess(_ value: Float) {
        canvas3D.shininess(value)
    }

    /// エミッシブ色を設定します。
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) {
        canvas3D.emissive(color)
    }

    /// グレースケール値でエミッシブ色を設定します。
    /// - Parameter gray: グレースケールの強度。
    public func emissive(_ gray: Float) {
        canvas3D.emissive(gray)
    }

    /// メタリック係数を設定します。
    /// - Parameter value: 0.0〜1.0 のメタリック値。
    public func metallic(_ value: Float) {
        canvas3D.metallic(value)
    }

    /// PBR ラフネスを設定し自動的に PBR モードに切り替えます。
    /// - Parameter value: 0.0（鏡面）から 1.0（完全拡散）のラフネス。
    public func roughness(_ value: Float) {
        canvas3D.roughness(value)
    }

    /// PBR アンビエントオクルージョン係数を設定します。
    /// - Parameter value: 0.0（完全遮蔽）から 1.0（遮蔽なし）のオクルージョン。
    public func ambientOcclusion(_ value: Float) {
        canvas3D.ambientOcclusion(value)
    }

    /// PBR モードを明示的に切り替えます。
    /// - Parameter enabled: true で Cook-Torrance GGX、false で Blinn-Phong。
    public func pbr(_ enabled: Bool) {
        canvas3D.pbr(enabled)
    }

    // MARK: - 3D Custom Material

    /// MSL シェーダーソースからカスタムマテリアルを作成します。
    ///
    /// MSL ソースをコンパイルし、指定したフラグメント関数から `CustomMaterial` を構築します。
    /// ソースには `BuiltinShaders.canvas3DStructs` をプレフィクスとして含める必要があります。
    /// - Parameters:
    ///   - source: MSL シェーダーソースコード。
    ///   - fragmentFunction: フラグメントシェーダー関数名。
    ///   - vertexFunction: カスタム頂点シェーダー関数名（オプション）。
    /// - Returns: `CustomMaterial` インスタンス。
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunction))
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    /// カスタムマテリアルを以降の 3D 描画に適用します。
    /// - Parameter customMaterial: 使用するカスタムマテリアル。
    public func material(_ customMaterial: CustomMaterial) {
        canvas3D.material(customMaterial)
    }

    /// カスタムマテリアルを解除しビルトインシェーダーに戻します。
    public func noMaterial() {
        canvas3D.noMaterial()
    }

    // MARK: - 3D Texture

    /// 以降の 3D 描画のテクスチャを設定します。
    /// - Parameter img: テクスチャ画像。
    public func texture(_ img: MImage) {
        canvas3D.texture(img)
    }

    /// 現在のテクスチャを解除します。
    public func noTexture() {
        canvas3D.noTexture()
    }

    // MARK: - 3D Transform Stack

    /// 2D・3D 両方のキャンバスの変換行列を保存します。
    public func pushMatrix() {
        canvas.pushMatrix()
        canvas3D.pushMatrix()
    }

    /// 2D・3D 両方のキャンバスの変換行列を復元します。
    public func popMatrix() {
        canvas.popMatrix()
        canvas3D.popMatrix()
    }

    /// 3D 平行移動を適用します。
    /// - Parameters:
    ///   - x: x 軸方向の移動量。
    ///   - y: y 軸方向の移動量。
    ///   - z: z 軸方向の移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.translate(x, y, z)
    }

    /// X 軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateX(_ angle: Float) {
        canvas3D.rotateX(angle)
    }

    /// Y 軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateY(_ angle: Float) {
        canvas3D.rotateY(angle)
    }

    /// Z 軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateZ(_ angle: Float) {
        canvas3D.rotateZ(angle)
    }

    /// 3D スケールを適用します。
    /// - Parameters:
    ///   - x: x 軸方向のスケール係数。
    ///   - y: y 軸方向のスケール係数。
    ///   - z: z 軸方向のスケール係数。
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.scale(x, y, z)
    }

    // MARK: - 3D Shapes

    /// 指定したサイズのボックスを描画します。
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        canvas3D.box(width, height, depth)
    }

    /// 均一なボックス（キューブ）を指定した辺の長さで描画します。
    /// - Parameter size: 辺の長さ。
    public func box(_ size: Float) {
        canvas3D.box(size)
    }

    /// 球を描画します。
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: テッセレーションレベル（デフォルト 24）。
    public func sphere(_ radius: Float, detail: Int = 24) {
        canvas3D.sphere(radius, detail: detail)
    }

    /// 平面を描画します。
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    public func plane(_ width: Float, _ height: Float) {
        canvas3D.plane(width, height)
    }

    /// 円柱を描画します。
    /// - Parameters:
    ///   - radius: 円柱の半径（デフォルト 0.5）。
    ///   - height: 円柱の高さ（デフォルト 1）。
    ///   - detail: テッセレーションレベル（デフォルト 24）。
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cylinder(radius: radius, height: height, detail: detail)
    }

    /// 円錐を描画します。
    /// - Parameters:
    ///   - radius: 底面の半径（デフォルト 0.5）。
    ///   - height: 円錐の高さ（デフォルト 1）。
    ///   - detail: テッセレーションレベル（デフォルト 24）。
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cone(radius: radius, height: height, detail: detail)
    }

    /// トーラスを描画します。
    /// - Parameters:
    ///   - ringRadius: リング（メジャー）半径（デフォルト 0.5）。
    ///   - tubeRadius: チューブ（マイナー）半径（デフォルト 0.2）。
    ///   - detail: テッセレーションレベル（デフォルト 24）。
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// ビルド済みメッシュを描画します。
    /// - Parameter mesh: 描画するメッシュ。
    public func mesh(_ mesh: Mesh) {
        canvas3D.mesh(mesh)
    }

    /// ダイナミックメッシュを描画します。
    /// - Parameter mesh: 描画するダイナミックメッシュ。
    public func dynamicMesh(_ mesh: DynamicMesh) {
        canvas3D.dynamicMesh(mesh)
    }

    /// プロシージャルジオメトリ用の空のダイナミックメッシュを作成します。
    /// - Returns: 新しい `DynamicMesh` インスタンス。
    public func createDynamicMesh() -> DynamicMesh {
        DynamicMesh(device: renderer.device)
    }

    /// 3D モデルファイル（OBJ、USDZ、ABC 形式）を読み込みます。
    /// - Parameters:
    ///   - path: モデルのファイルパス。
    ///   - normalize: バウンディングボックスを [-1, 1] に正規化するかどうか（デフォルト true）。
    /// - Returns: 読み込まれたメッシュ。失敗時は nil。
    public func loadModel(_ path: String, normalize: Bool = true) -> Mesh? {
        let url = URL(fileURLWithPath: path)
        return try? Mesh.load(device: renderer.device, url: url, normalize: normalize)
    }

    // MARK: - Compute

    /// MSL ソースコードからコンピュートカーネルを作成します。
    /// - Parameters:
    ///   - source: MSL ソースコード。
    ///   - function: カーネル関数名。
    /// - Returns: `ComputeKernel` インスタンス。
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try ComputeKernel(device: renderer.device, source: source, functionName: function)
    }

    /// ゼロ初期化された型付き GPU バッファを作成します。
    /// - Parameters:
    ///   - count: 要素数。
    ///   - type: 要素の型。
    /// - Returns: 新しい `GPUBuffer`。失敗時は nil。
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, count: count)
    }

    /// データ配列から GPU バッファを作成します。
    /// - Parameter data: ソースデータ配列。
    /// - Returns: 新しい `GPUBuffer`。失敗時は nil。
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, data: data)
    }

    /// 1D コンピュートカーネルをディスパッチします。
    /// - Parameters:
    ///   - kernel: ディスパッチするコンピュートカーネル。
    ///   - threads: 総スレッド数。
    ///   - configure: ディスパッチ前にコンピュートエンコーダーを構成するクロージャ。
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: threads, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// 2D コンピュートカーネルをディスパッチします。
    /// - Parameters:
    ///   - kernel: ディスパッチするコンピュートカーネル。
    ///   - width: スレッド単位のグリッド幅。
    ///   - height: スレッド単位のグリッド高さ。
    ///   - configure: ディスパッチ前にコンピュートエンコーダーを構成するクロージャ。
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let h = max(1, kernel.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// データ依存関係を解決するためにコンピュートディスパッチ間にメモリバリアを挿入します。
    public func computeBarrier() {
        _computeEncoder?.memoryBarrier(scope: .buffers)
    }

    /// コンピュートコマンドエンコーダーを遅延生成して返します。
    func ensureComputeEncoder() -> MTLComputeCommandEncoder? {
        if let existing = _computeEncoder { return existing }
        guard let cb = _commandBuffer else { return nil }
        let encoder = cb.makeComputeCommandEncoder()
        _computeEncoder = encoder
        renderer.didEncodeComputeWork = true
        return encoder
    }

    // MARK: - Particle System

    /// GPU パーティクルシステムを作成します。
    /// - Parameter count: パーティクル数（デフォルト 100,000）。
    /// - Returns: `ParticleSystem` インスタンス。
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try ParticleSystem(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            sampleCount: renderer.textureManager.sampleCount,
            count: count
        )
    }

    /// パーティクルシステムを更新します（コンピュートフェーズ中に呼び出してください）。
    /// - Parameter system: 更新するパーティクルシステム。
    public func updateParticles(_ system: ParticleSystem) {
        guard let encoder = ensureComputeEncoder() else { return }
        system.update(encoder: encoder, deltaTime: deltaTime, time: time)
    }

    /// パーティクルシステムを描画します（描画フェーズ中に呼び出してください）。
    /// - Parameter system: 描画するパーティクルシステム。
    public func drawParticles(_ system: ParticleSystem) {
        canvas.flush()
        guard let enc = canvas.currentEncoder else { return }
        system.draw(
            encoder: enc,
            viewProjection: canvas3D.currentViewProjection,
            cameraRight: canvas3D.currentCameraRight,
            cameraUp: canvas3D.currentCameraUp
        )
    }

    // MARK: - Shader Hot Reload

    /// シェーダーソースを再コンパイルしパイプラインキャッシュをクリアします。
    ///
    /// `CustomMaterial.reload()` または `CustomPostEffect.reload()` と組み合わせて使用します。
    /// - Parameters:
    ///   - key: シェーダーライブラリの登録キー。
    ///   - source: 新しい MSL ソースコード。
    public func reloadShader(key: String, source: String) throws {
        try renderer.shaderLibrary.reload(key: key, source: source)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// 外部ファイルからシェーダーをリロードしパイプラインキャッシュをクリアします。
    /// - Parameters:
    ///   - key: シェーダーライブラリの登録キー。
    ///   - path: MSL ソースのファイルパス。
    public func reloadShaderFromFile(key: String, path: String) throws {
        try renderer.shaderLibrary.reloadFromFile(key: key, path: path)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// 外部 MSL ファイルからカスタムマテリアルを作成します。
    /// - Parameters:
    ///   - path: MSL ソースのファイルパス。
    ///   - fragmentFunction: フラグメントシェーダー関数名。
    ///   - vertexFunction: カスタム頂点シェーダー関数名（オプション）。
    /// - Returns: `CustomMaterial` インスタンス。
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.registerFromFile(path: path, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunction))
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    // MARK: - Tween

    /// トゥイーンを作成しトゥイーンマネージャに登録します。
    /// - Parameters:
    ///   - from: 開始値。
    ///   - to: 終了値。
    ///   - duration: トゥイーン時間（秒単位）。
    ///   - easing: イージング関数（デフォルト ease-in-out cubic）。
    /// - Returns: 作成された `Tween` インスタンス。
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        let t = Tween(from: from, to: to, duration: duration, easing: easing)
        tweenManager.add(t)
        return t
    }

    // MARK: - GIF Export (D-19)

    /// GIF 記録を開始します。
    /// - Parameter fps: GIF のフレームレート（デフォルト 15）。
    public func beginGIFRecord(fps: Int = 15) {
        gifExporter.beginRecord(
            fps: fps,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height
        )
    }

    /// GIF フレームをキャプチャします（各フレームで内部的に呼ばれます）。
    func captureGIFFrame() {
        guard gifExporter.isRecording else { return }
        gifExporter.captureFrame(
            texture: renderer.textureManager.colorTexture,
            device: renderer.device,
            commandQueue: renderer.commandQueue
        )
    }

    /// GIF 記録を終了しファイルに書き出します。
    /// - Parameter path: 出力ファイルパス（nil の場合はデスクトップに自動生成）。
    public func endGIFRecord(_ path: String? = nil) throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try gifExporter.endRecord(to: actualPath)
    }

    /// GIF 記録を終了しバックグラウンドスレッドで非同期にファイルを書き出します。
    /// - Parameter path: 出力ファイルパス（nil の場合はデスクトップに自動生成）。
    public func endGIFRecordAsync(_ path: String? = nil) async throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try await gifExporter.endRecordAsync(to: actualPath)
    }

    // MARK: - Orbit Camera (D-20)

    /// オービットカメラコントロールを有効にします（描画フェーズ中に呼び出してください）。
    ///
    /// マウスドラッグでカメラを回転し、スクロールでズームします。
    public func orbitControl() {
        let inp = input

        // マウスドラッグでカメラを回転
        if inp.isMouseDown {
            let dx = inp.mouseX - inp.pmouseX
            let dy = inp.mouseY - inp.pmouseY
            orbitCamera.handleMouseDrag(dx: dx, dy: dy)
        }

        // スクロールでズーム
        let sy = inp.scrollY
        if abs(sy) > 0.01 {
            orbitCamera.handleScroll(delta: sy)
        }

        // ダンピング更新
        orbitCamera.update()

        // Canvas3D に適用
        canvas3D.camera(eye: orbitCamera.eye, center: orbitCamera.target, up: orbitCamera.up)
    }

}
