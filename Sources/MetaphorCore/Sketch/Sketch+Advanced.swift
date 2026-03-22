@preconcurrency import Metal

// MARK: - Plugin Management

extension Sketch {
    /// このスケッチにプラグインを登録します。
    ///
    /// プラグインはライフサイクルコールバック（``MetaphorPlugin/pre(commandBuffer:time:)``、
    /// ``MetaphorPlugin/post(texture:commandBuffer:)``）、入力イベント
    /// （``MetaphorPlugin/mouseEvent(x:y:button:type:)``）などを受け取ります。
    ///
    /// ```swift
    /// func setup() {
    ///     registerPlugin(MyPlugin())
    /// }
    /// ```
    /// - Parameter plugin: 登録するプラグイン。
    public func registerPlugin(_ plugin: MetaphorPlugin) {
        context.renderer.addPlugin(plugin, sketch: self)
    }

    /// 識別子を指定して登録済みプラグインを削除します。
    /// - Parameter id: 削除するプラグインの ``MetaphorPlugin/pluginID``。
    public func removePlugin(id: String) {
        context.renderer.removePlugin(id: id)
    }

    /// 識別子を指定して登録済みプラグインを検索します。
    /// - Parameter id: 検索する ``MetaphorPlugin/pluginID``。
    /// - Returns: 一致するプラグイン。見つからない場合は `nil`。
    public func plugin(id: String) -> MetaphorPlugin? {
        context.renderer.plugin(id: id)
    }
}

// MARK: - Compute

extension Sketch {

    /// MSL ソースコードから GPU コンピュートカーネルを作成します。
    ///
    /// - Parameters:
    ///   - source: Metal Shading Language のソースコード。
    ///   - function: コンピュート関数の名前。
    /// - Returns: 新しい ``ComputeKernel`` インスタンス。
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try context.createComputeKernel(source: source, function: function)
    }

    /// 指定した要素数と型の GPU バッファを作成します。
    ///
    /// - Parameters:
    ///   - count: 要素数。
    ///   - type: 要素の型。
    /// - Returns: 新しい ``GPUBuffer``。作成に失敗した場合は `nil`。
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        context.createBuffer(count: count, type: type)
    }

    /// 指定したデータで初期化された GPU バッファを作成します。
    ///
    /// - Parameter data: 初期データ配列。
    /// - Returns: 新しい ``GPUBuffer``。作成に失敗した場合は `nil`。
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        context.createBuffer(data)
    }

    /// 1D コンピュートカーネルをディスパッチします。
    ///
    /// - Parameters:
    ///   - kernel: ディスパッチするコンピュートカーネル。
    ///   - threads: 総スレッド数。
    ///   - configure: ディスパッチ前にコンピュートコマンドエンコーダーを構成するクロージャ。
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        context.dispatch(kernel, threads: threads, configure)
    }

    /// 2D コンピュートカーネルをディスパッチします。
    ///
    /// - Parameters:
    ///   - kernel: ディスパッチするコンピュートカーネル。
    ///   - width: スレッド単位のグリッド幅。
    ///   - height: スレッド単位のグリッド高さ。
    ///   - configure: ディスパッチ前にコンピュートコマンドエンコーダーを構成するクロージャ。
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        context.dispatch(kernel, width: width, height: height, configure)
    }

    /// ディスパッチ間の同期のためにコンピュートコマンドエンコーダーにバリアを挿入します。
    public func computeBarrier() {
        context.computeBarrier()
    }
}

// MARK: - Particle System

extension Sketch {
    /// GPU パーティクルシステムを作成します。
    ///
    /// - Parameter count: パーティクルの最大数。
    /// - Returns: 新しい ``ParticleSystem`` インスタンス。
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try context.createParticleSystem(count: count)
    }

    /// パーティクルシステムを更新します（``compute()`` 内で呼び出してください）。
    ///
    /// - Parameter system: 更新するパーティクルシステム。
    public func updateParticles(_ system: ParticleSystem) {
        context.updateParticles(system)
    }

    /// パーティクルシステムを描画します（``draw()`` 内で呼び出してください）。
    ///
    /// - Parameter system: 描画するパーティクルシステム。
    public func drawParticles(_ system: ParticleSystem) {
        context.drawParticles(system)
    }
}

// MARK: - Tween

extension Sketch {
    /// トゥイーンアニメーションを作成し登録します（トゥイーンマネージャに自動追加されます）。
    ///
    /// - Parameters:
    ///   - from: 開始値。
    ///   - to: 終了値。
    ///   - duration: アニメーション時間（秒単位）。
    ///   - easing: イージング関数。
    /// - Returns: 新しい ``Tween`` インスタンス。コンテキストが利用できない場合は `nil`。
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T>? {
        context.tween(from: from, to: to, duration: duration, easing: easing)
    }
}

// MARK: - Shader Hot Reload

extension Sketch {
    /// シェーダーをソースから再コンパイルしパイプラインキャッシュをクリアします。
    ///
    /// - Parameters:
    ///   - key: リロードするシェーダーライブラリキー。
    ///   - source: 新しい MSL ソースコード。
    public func reloadShader(key: String, source: String) throws {
        try context.reloadShader(key: key, source: source)
    }

    /// 外部ファイルからシェーダーをリロードしパイプラインキャッシュをクリアします。
    ///
    /// - Parameters:
    ///   - key: リロードするシェーダーライブラリキー。
    ///   - path: MSL ソースファイルのファイルパス。
    public func reloadShaderFromFile(key: String, path: String) throws {
        try context.reloadShaderFromFile(key: key, path: path)
    }

    /// 外部ファイルから MSL ソースを読み込んでカスタムマテリアルを作成します。
    ///
    /// - Parameters:
    ///   - path: MSL ソースファイルのファイルパス。
    ///   - fragmentFunction: フラグメント関数の名前。
    ///   - vertexFunction: カスタム頂点関数の名前（オプション）。
    /// - Returns: 新しい ``CustomMaterial`` インスタンス。
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try context.createMaterialFromFile(path: path, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }
}

// MARK: - GUI

extension Sketch {
    /// イミディエイトモード UI コントロール作成用のパラメータ GUI へのアクセス。
    public var gui: ParameterGUI? {
        context.gui
    }
}

// MARK: - Performance HUD

extension Sketch {
    /// パフォーマンスヘッドアップディスプレイオーバーレイを有効にします。
    public func enablePerformanceHUD() {
        context.enablePerformanceHUD()
    }

    /// パフォーマンスヘッドアップディスプレイオーバーレイを無効にします。
    public func disablePerformanceHUD() {
        context.disablePerformanceHUD()
    }
}

// MARK: - Post Process

extension Sketch {
    /// MSL ソースコードからカスタムポストプロセスエフェクトを作成します。
    ///
    /// - Parameters:
    ///   - name: エフェクトの表示名。
    ///   - source: Metal Shading Language のソースコード。
    ///   - fragmentFunction: フラグメント関数の名前。
    /// - Returns: 新しい ``CustomPostEffect`` インスタンス。
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        try context.createPostEffect(name: name, source: source, fragmentFunction: fragmentFunction)
    }

    /// ポストプロセスエフェクトをパイプラインに追加します。
    ///
    /// - Parameter effect: 追加するポストプロセスエフェクト。
    public func addPostEffect(_ effect: any PostEffect) {
        context.addPostEffect(effect)
    }

    /// 指定インデックスのポストプロセスエフェクトを削除します。
    ///
    /// - Parameter index: 削除するエフェクトのインデックス。
    public func removePostEffect(at index: Int) {
        context.removePostEffect(at: index)
    }

    /// パイプラインからすべてのポストプロセスエフェクトを削除します。
    public func clearPostEffects() {
        context.clearPostEffects()
    }

    /// すべてのポストプロセスエフェクトを指定した配列で置き換えます。
    ///
    /// - Parameter effects: 新しいポストプロセスエフェクトの配列。
    public func setPostEffects(_ effects: [any PostEffect]) {
        context.setPostEffects(effects)
    }
}

// MARK: - Cursor Control

extension Sketch {
    /// カーソルを表示します。
    public func cursor() {
        context.cursor()
    }

    /// カーソルを非表示にします。
    public func noCursor() {
        context.noCursor()
    }
}

// MARK: - GIF Export (D-19)

extension Sketch {
    /// GIF エクスポート用のフレーム記録を開始します。
    ///
    /// - Parameter fps: GIF の目標フレーム毎秒。
    public func beginGIFRecord(fps: Int = 15) {
        context.beginGIFRecord(fps: fps)
    }

    /// 記録を停止し GIF ファイルに書き出します。
    ///
    /// - Parameter path: 出力ファイルパス（`nil` の場合は自動生成）。
    public func endGIFRecord(_ path: String? = nil) throws {
        try context.endGIFRecord(path)
    }

    /// 記録を停止し GIF ファイルを非同期で書き出します。
    ///
    /// ブロッキングを避けるためファイル書き込みをバックグラウンドスレッドで実行します。
    /// - Parameter path: 出力ファイルパス（`nil` の場合は自動生成）。
    public func endGIFRecord(_ path: String? = nil) async throws {
        try await context.endGIFRecordAsync(path)
    }
}

// MARK: - Orbit Camera (D-20)

extension Sketch {
    /// オービットカメラコントロールを有効にします（``draw()`` 内で呼び出してください）。
    public func orbitControl() {
        context.orbitControl()
    }

    /// 手動設定用のオービットカメラへのアクセス。
    public var orbitCamera: OrbitCamera? {
        context.orbitCamera
    }
}

// MARK: - Cache Management

extension Sketch {
    /// GPU メモリを解放するためにすべての内部キャッシュをクリアします。
    public func clearCaches() {
        context.clearCaches()
    }
}
