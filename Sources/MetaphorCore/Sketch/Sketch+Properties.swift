// MARK: - Convenience Properties

extension Sketch {
    /// キャンバスの幅（ピクセル単位）。
    public var width: Float {
        context.width    }

    /// キャンバスの高さ（ピクセル単位）。
    public var height: Float {
        context.height    }

    /// 入力マネージャ（イベントハンドラ内で使用）。
    public var input: InputManager {
        context.input
    }

    /// 現在のマウス x 座標。
    public var mouseX: Float {
        context.input.mouseX    }

    /// 現在のマウス y 座標。
    public var mouseY: Float {
        context.input.mouseY    }

    /// 前フレームのマウス x 座標。
    public var pmouseX: Float {
        context.input.pmouseX    }

    /// 前フレームのマウス y 座標。
    public var pmouseY: Float {
        context.input.pmouseY    }

    /// マウスボタンが現在押されているかどうか。
    public var isMousePressed: Bool {
        context.input.isMouseDown    }

    /// 現在のフレームの水平スクロール量。
    public var scrollX: Float {
        context.input.scrollX    }

    /// 現在のフレームの垂直スクロール量。
    public var scrollY: Float {
        context.input.scrollY    }

    /// 最後に**押された**マウスボタン。まだ一度も押されていなければ `nil`。
    ///
    /// 更新は押下時だけで、ボタンを離しても値は保持される。そのため
    /// ``mouseReleased()`` の中で読むと「**いま離したボタン**」ではなく
    /// 「最後に押されたボタン」が返る。**単一ボタンの操作なら両者は一致する**ので
    /// Processing と同じように書けるが、複数ボタンを同時に押している場合は
    /// 一致しない（左押下 → 右押下 → 左リリースで `.right` が返る。Processing は
    /// リリースでも更新するため `.left`）。
    ///
    /// 離したボタンを取る API は [#958] で検討中。それまでは押下側で覚えておく。
    /// 「いま押されているか」は ``isMousePressed`` と併用する。
    ///
    /// [#958]: https://github.com/shinyaoguri/metaphor/issues/958
    ///
    /// ```swift
    /// if isMousePressed && mouseButton == .right { … }
    /// ```
    public var mouseButton: MouseButton? {
        context.input.mouseButton    }

    /// キーが現在押されているかどうか。
    public var isKeyPressed: Bool {
        context.input.isKeyPressed    }

    /// 最後に**押された**キー。
    ///
    /// 更新は押下時だけなので、``keyReleased()`` の中で読むと
    /// 「**いま離したキー**」ではなく「最後に押されたキー」が返る。
    /// **単一キーの操作なら両者は一致する**が、複数キーを同時に押している場合は
    /// 一致しない（A 押下 → B 押下 → A リリースで `"b"` が返る。Processing は
    /// リリースでも更新するため `"a"`）。詳しくは ``keyCode`` を参照。
    public var key: Character? {
        context.input.lastKey
    }

    /// 最後に**押された**キーのキーコード。
    ///
    /// ``key`` と同じく更新は押下時だけで、``keyReleased()`` の中で読むと
    /// 「いま離したキー」ではなく「最後に押されたキー」が返る。つまり
    /// `keyReleased()` の中の `keyCode == SPACE` は「Space が離された」ではなく
    /// 「最後に押されたキーが Space」を意味し、Space を押したまま別のキーを
    /// 離したときにも成立してしまう。
    ///
    /// 離したキーを取る API は [#958] で検討中。それまでは押下側で覚えておく:
    ///
    /// ```swift
    /// var pending: UInt16?
    /// func keyPressed()  { pending = keyCode }
    /// func keyReleased() { if pending == SPACE { … }; pending = nil }
    /// ```
    ///
    /// いま押されているかを見るだけなら ``isKeyDown(_:)`` で足りる。
    ///
    /// [#958]: https://github.com/shinyaoguri/metaphor/issues/958
    public var keyCode: UInt16? {
        context.input.lastKeyCode
    }

    /// 特定のキーが現在押下されているかを確認します。
    ///
    /// - Parameter keyCode: 確認するハードウェアキーコード。
    /// - Returns: キーが現在押されている場合は `true`。
    public func isKeyDown(_ keyCode: UInt16) -> Bool {
        context.input.isKeyDown(keyCode)    }

    /// 最新のキーダウンイベントがオートリピートかどうか。
    public var isKeyRepeat: Bool {
        context.input.isKeyRepeat    }

    /// スケッチ開始からの経過時間（秒単位）。
    public var time: Float {
        context.time    }

    /// 前フレームからの経過時間（秒単位）。
    ///
    /// ``noLoop()`` で止めていた時間はここに乗りません。``loop()`` で再開した直後の
    /// フレームも 1 フレームぶんの経過になります（``time`` のほうは実時間に追いつきます）。
    public var deltaTime: Float {
        context.deltaTime    }

    /// これまでにレンダリングされた総フレーム数。
    public var frameCount: Int {
        context.frameCount    }
}

// MARK: - Canvas Setup

extension Sketch {
    /// キャンバスサイズを設定します（`setup()` 内で呼び出してください、p5.js スタイル）。
    ///
    /// - Important: `draw()` の中からの呼び出しは警告を出して無視されます（#856）。
    ///   リサイズは全インフライトフレームの完了待ちを伴うため、フレームの中では成立しません。
    ///
    /// - Parameters:
    ///   - width: キャンバスの幅（ピクセル単位）。
    ///   - height: キャンバスの高さ（ピクセル単位）。
    public func createCanvas(width: Int, height: Int) {
        context.createCanvas(width: width, height: height)
    }
}

// MARK: - Vector Factory

extension Sketch {
    /// 2D ベクトルを作成します（Processing PVector 互換）。
    ///
    /// - Parameters:
    ///   - x: x 成分。
    ///   - y: y 成分。
    /// - Returns: 指定した成分の新しい ``Vec2``。
    public func createVector(_ x: Float = 0, _ y: Float = 0) -> Vec2 {
        Vec2(x, y)
    }

    /// 3D ベクトルを作成します（Processing PVector 互換）。
    ///
    /// - Parameters:
    ///   - x: x 成分。
    ///   - y: y 成分。
    ///   - z: z 成分。
    /// - Returns: 指定した成分の新しい ``Vec3``。
    public func createVector(_ x: Float, _ y: Float, _ z: Float) -> Vec3 {
        Vec3(x, y, z)
    }
}

// MARK: - Animation Control

extension Sketch {
    /// アニメーションループが現在実行中かどうか。
    public var isLooping: Bool {
        context.isLooping    }

    /// アニメーションループを再開します。
    ///
    /// 再開後の最初のフレームの ``deltaTime`` は 1 フレームぶんの経過になります。
    /// 止めていた実時間は ``time`` にだけ反映されます。
    public func loop() {
        context.loop()
    }

    /// アニメーションループを停止します。
    public func noLoop() {
        context.noLoop()
    }

    /// 単一フレームをレンダリングします（``noLoop()`` 呼び出し後に使用）。
    public func redraw() {
        context.redraw()
    }

    /// フレームレートを動的に変更します。
    ///
    /// - Parameter fps: 目標フレーム毎秒。
    public func frameRate(_ fps: Int) {
        context.frameRate(fps)
    }
}
