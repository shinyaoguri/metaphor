# metaphor 実装計画書

> 各フェーズはコンテキストリセット後に独立実行可能なように設計。
> 各タスクに「対象ファイル」「現状」「変更内容」「コード例」「テスト方針」を記載。

---

## Phase A: 基盤修正 (信頼性)

### A-1: CFAbsoluteTimeGetCurrent → CACurrentMediaTime

**目的**: アニメーションタイミングを壁時計時刻から単調増加時刻に変更

**対象ファイル**:
- `Sources/metaphor/Core/MetaphorRenderer.swift`

**現状**:
- L45: `private let startTime: CFAbsoluteTime`
- L122: `self.startTime = CFAbsoluteTimeGetCurrent()`
- L200-202: `public var elapsedTime: Double { CFAbsoluteTimeGetCurrent() - startTime }`

**変更内容**:
1. `import QuartzCore` を追加（`CACurrentMediaTime` のため）
2. `startTime` の型を `CFAbsoluteTime` から `Double` に変更
3. 初期化を `CACurrentMediaTime()` に変更
4. `elapsedTime` の計算を `CACurrentMediaTime() - startTime` に変更

**コード例**:
```swift
import QuartzCore

private let startTime: Double  // was CFAbsoluteTime

// init 内:
self.startTime = CACurrentMediaTime()

// computed property:
public var elapsedTime: Double {
    CACurrentMediaTime() - startTime
}
```

**テスト方針**: 既存テストが通ること。追加テストは不要（動作の変化なし、精度向上のみ）

---

### A-2: _activeSketchContext の nil ハンドリング統一

**目的**: draw() 外からの API 呼び出し時に、沈黙の失敗でもクラッシュでもなく、明示的エラーを出す

**対象ファイル**:
- `Sources/metaphor/Sketch/Sketch.swift`

**現状**:
- ~85メソッドが `_activeSketchContext?.method()` (沈黙の失敗)
- 8メソッドが `_activeSketchContext!.method()` (クラッシュ)
- 1メソッドが `guard let ctx = _activeSketchContext else { throw }` (正しい)

**変更内容**:
1. ヘルパー関数を追加:
```swift
@MainActor
private func activeContext(function: String = #function) -> SketchContext {
    guard let ctx = _activeSketchContext else {
        fatalError("[\(function)] must be called inside setup() or draw()")
    }
    return ctx
}
```

2. **戻り値のあるメソッド（8+1個）**: `activeContext()` を使う（既存の force-unwrap を置換）
```swift
public func loadImage(_ path: String) throws -> MImage {
    try activeContext().loadImage(path)
}
```

3. **戻り値のないメソッド（~85個）**: 2つの方針から選択
   - **方針 A (推奨)**: `_activeSketchContext?.method()` のまま維持。draw 外の呼び出しは無視。Processing と同じ挙動。
   - **方針 B**: 全てを `activeContext().method()` に変更。厳密だが既存コードが壊れる可能性。

   → **方針 A を採用**: 戻り値なしは optional chain を維持、戻り値ありは `activeContext()` で明示的エラー。

4. `input` プロパティ (L112): `_activeSketchContext!.input` → `activeContext().input`

**テスト方針**: `_activeSketchContext = nil` 状態で戻り値ありメソッドを呼び fatalError を検証（テスト困難なら手動確認）

---

### A-3: Pipeline sampleCount デフォルト統一

**目的**: PipelineFactory のデフォルト sampleCount を TextureManager と一致させる

**対象ファイル**:
- `Sources/metaphor/Core/PipelineFactory.swift`

**現状**:
- L243: `private var rasterSampleCount: Int = 1`
- TextureManager のデフォルト: `sampleCount: Int = 4`

**変更内容**:
1. `PipelineFactory` のデフォルトを `4` に変更:
```swift
private var rasterSampleCount: Int = 4  // Match TextureManager default
```

2. `Canvas2D` と `Canvas3D` が明示的に `.sampleCount()` を呼んでいるか確認し、呼んでいれば変更の影響なし。呼んでいなければ修正が効く。

**注意**: Canvas2D (L358) と Canvas3D (L184, L201) は既に `.sampleCount(sampleCount)` を呼んでいるので、デフォルト変更は「直接 PipelineFactory を使うユーザー」のみに影響。

**テスト方針**: 既存テスト通過 + PipelineFactory のデフォルト sampleCount が 4 であることを検証するテスト追加

---

### A-4: CI テストワークフロー追加

**目的**: PR/push 時に自動でビルド・テスト実行

**対象ファイル (新規)**:
- `.github/workflows/ci.yml`

**内容**:
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app
      - name: Build Syphon
        run: make setup
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

**テスト方針**: PR を作って CI が動作することを確認

---

### A-5: background() を render pass clear に変更

**目的**: 不要な全画面クアッド描画を排除し、深度バッファも正しくクリア

**対象ファイル**:
- `Sources/metaphor/Drawing/Canvas2D.swift`
- `Sources/metaphor/Core/TextureManager.swift`
- `Sources/metaphor/Core/MetaphorRenderer.swift`

**現状**:
- Canvas2D.background() (L631-639): 6頂点の全画面クアッド描画
- TextureManager (L129-133): `loadAction = .clear` + `clearColor` が毎フレーム設定済み
- つまり「Metal の clear + Canvas2D の quad」で二重クリアしている

**変更内容**:

1. **TextureManager に `clearColor` の動的変更メソッド追加**:
```swift
public mutating func setClearColor(_ color: MTLClearColor) {
    renderPassDescriptor.colorAttachments[0].clearColor = color
}
```

2. **MetaphorRenderer に clearColor 変更用の公開メソッド追加**:
```swift
public func setClearColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
    textureManager.setClearColor(MTLClearColor(red: r, green: g, blue: b, alpha: a))
}
```

3. **Canvas2D.background() を変更**:
```swift
public func background(_ color: Color) {
    let c = color.simd
    // render pass の clear color を更新（次フレームから適用）
    renderer?.setClearColor(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
    // 今フレームは quad で即時クリア（clear は既に実行済みのため）
    // ただし depth も clear する必要がある
    // → エンコーダーの endEncoding + 新しい renderPassDescriptor で再開が必要
    // → 複雑すぎるので、代替案: loadAction を .load に変更し、background() を唯一のクリア手段にする
}
```

**代替案 (よりシンプル)**:
- TextureManager の `loadAction` を `.load` に変更（クリアしない）
- `background()` 呼び出し時のみ全画面クアッド描画 + 深度クリアフラグ設定
- `background()` が呼ばれた場合、次の `renderFrame()` で `loadAction = .clear` に戻す

**最終設計**:
```
1. TextureManager の loadAction はデフォルト .clear のまま
2. Canvas2D.background() は MetaphorRenderer 経由で clearColor を変更
3. Canvas2D.background() 内の quad 描画は削除
4. background() が draw() の冒頭で呼ばれる場合:
   - clearColor が次フレームの clear に使われる
   - 今フレームは描画データ前なので clear 済みの上に何も描かない
5. background() が draw() の途中で呼ばれる場合:
   - 全画面 quad を描画（現状と同じ）して即座にクリア
   → つまり「冒頭か途中か」の判定が必要
```

**実装 (最終)**:
- `Canvas2D` に `hasDrawnAnything: Bool` フラグ追加（begin() で false、addVertex で true）
- `background()` で:
  - `hasDrawnAnything == false`: clearColor 設定のみ（quad なし）
  - `hasDrawnAnything == true`: 従来通り quad 描画 + depth clear
- **depth clear**: `background()` 呼び出し後に depth をリセットする仕組みが必要
  - depth clear は render encoder を閉じて新しい pass descriptor で再開するか、
  - または depth test を一時的に無効化する
  - → **現実的な妥協**: depth 書き込みを有効にした全画面 quad (z=0) で depth を上書き

**テスト方針**: background で色指定 → screenshot → ピクセル検証（可能なら）

---

## Phase B: 表現力の穴埋め (Processing パリティ)

### B-6: beginShape に頂点カラー + UV + 3D 版追加

**目的**: Processing の beginShape/vertex/endShape の完全な機能をカバー

**対象ファイル**:
- `Sources/metaphor/Drawing/Canvas2D.swift`
- `Sources/metaphor/Drawing/Canvas3D.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`
- `Sources/metaphor/Shaders/BuiltinShaders.swift`

**現状**:
- Canvas2D の `vertex(x, y)` は位置のみ記録 (ShapeVertexType.normal(Float, Float))
- 頂点カラーは形状全体に対して `fillColor` 一色
- UV 指定なし
- 3D 版の beginShape/endShape なし

**変更内容**:

#### B-6a: 頂点カラー対応 (2D)

1. `ShapeVertexType` を拡張:
```swift
private enum ShapeVertexType {
    case normal(Float, Float)
    case colored(Float, Float, SIMD4<Float>)  // NEW: with per-vertex color
    case textured(Float, Float, Float, Float)  // NEW: with UV
    case bezier(cx1: Float, cy1: Float, cx2: Float, cy2: Float, x: Float, y: Float)
    case curve(Float, Float)
}
```

2. 新しい vertex 関数:
```swift
/// Per-vertex color
public func vertex(_ x: Float, _ y: Float, _ color: Color) {
    guard isRecordingShape else { return }
    shapeVertexList.append(.colored(x, y, color.simd))
}

/// UV coordinates for textured shapes
public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
    guard isRecordingShape else { return }
    shapeVertexList.append(.textured(x, y, u, v))
}
```

3. `expandShapeVertices()` と `drawPolygonShape()` を拡張して per-vertex color を `addVertex` に渡す
4. テクスチャ付き頂点の場合は `drawTexturedQuad` 相当のパスで処理

#### B-6b: 3D beginShape/endShape

Canvas3D に新しい immediate-mode 3D 頂点システムを追加:

1. **Canvas3D に 3D 頂点バッファを追加**:
```swift
private var shapeVertices3D: [Vertex3D] = []
private var isRecordingShape3D = false

public func beginShape(_ mode: ShapeMode = .polygon) {
    isRecordingShape3D = true
    shapeVertices3D.removeAll(keepingCapacity: true)
}

public func vertex(_ x: Float, _ y: Float, _ z: Float) {
    guard isRecordingShape3D else { return }
    shapeVertices3D.append(Vertex3D(
        position: SIMD3(x, y, z),
        normal: SIMD3(0, 1, 0),  // default up normal
        color: fillColor
    ))
}

public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
    // UV 付き頂点 → Vertex3DTextured を使う
}

public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
    // 次の vertex に適用する法線を設定
    pendingNormal = SIMD3(nx, ny, nz)
}

public func endShape(_ close: ShapeClose = .open) {
    // shapeVertices3D から MTLBuffer を作成してレンダリング
    // EarClipTriangulator で三角形分割（polygon mode の場合）
    // 法線の自動計算
}
```

2. **SketchContext と Sketch extension にプロキシ追加** (3D vertex 関数)

**テスト方針**:
- 頂点カラー付き三角形の描画（クラッシュなし）
- 3D beginShape/vertex/endShape での基本形状描画
- UV 付き頂点のテクスチャマッピング

---

### B-7: Vec2 型の強化

**目的**: 既存の Vec2 typealias を活用しつつ、Processing の PVector 相当の使い勝手を提供

**対象ファイル**:
- `Sources/metaphor/Utilities/Vector.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**現状**:
- `Vector.swift` に `typealias Vec2 = SIMD2<Float>` + 拡張あり
- heading, rotate, limit, normalize, dist, dot, fromAngle, random2D, lerp が実装済み
- `createVector()` 関数がない

**変更内容**:
1. Sketch extension に `createVector()` 追加:
```swift
public func createVector(_ x: Float = 0, _ y: Float = 0) -> Vec2 {
    Vec2(x, y)
}
public func createVector(_ x: Float, _ y: Float, _ z: Float) -> Vec3 {
    Vec3(x, y, z)
}
```

2. Vec2/Vec3 に不足している演算を追加:
```swift
extension SIMD2<Float> {
    /// Processing PVector 互換: ベクトルの角度を設定
    public func withMagnitude(_ len: Float) -> SIMD2<Float> {
        normalized() * len
    }

    /// 2点間の角度
    public func angleBetween(_ other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }

    /// 2D cross product (z component of 3D cross)
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }
}
```

3. `polygon()` の引数を `[(Float, Float)]` から `[Vec2]` にも受け付けるオーバーロード追加

**テスト方針**: Vec2 の各メソッドの単体テスト

---

### B-8: image() のサブイメージ描画

**目的**: スプライトシート、タイルマップのサポート

**対象ファイル**:
- `Sources/metaphor/Drawing/Canvas2D.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**現状**:
- `drawTexturedQuad` (L1916-1949) で UV が (0,0)-(1,1) にハードコード

**変更内容**:
1. `drawTexturedQuad` にソース矩形パラメータ追加:
```swift
private func drawTexturedQuad(
    texture: MTLTexture, x: Float, y: Float, w: Float, h: Float,
    srcX: Float = 0, srcY: Float = 0, srcW: Float? = nil, srcH: Float? = nil
) {
    let tw = Float(texture.width)
    let th = Float(texture.height)
    let u0 = srcX / tw
    let v0 = srcY / th
    let u1 = (srcX + (srcW ?? tw)) / tw
    let v1 = (srcY + (srcH ?? th)) / th
    // TexturedVertex2D の UV に u0,v0,u1,v1 を使用
}
```

2. Processing 互換の `image()` オーバーロード追加:
```swift
/// image(img, dx, dy, dw, dh, sx, sy, sw, sh)
public func image(_ img: MImage,
                  _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
                  _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float) {
    drawTexturedQuad(texture: img.texture, x: dx, y: dy, w: dw, h: dh,
                     srcX: sx, srcY: sy, srcW: sw, srcH: sh)
}
```

3. SketchContext と Sketch extension にプロキシ追加

**テスト方針**: サブイメージ描画がクラッシュしないこと。UV 計算の単体テスト。

---

### B-9: 動的メッシュ API

**目的**: 頂点を動的に追加・変更できるメッシュ

**対象ファイル (新規)**:
- `Sources/metaphor/Geometry/DynamicMesh.swift`

**対象ファイル (変更)**:
- `Sources/metaphor/Drawing/Canvas3D.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**設計**:
```swift
@MainActor
public final class DynamicMesh {
    private let device: MTLDevice
    private var vertices: [Vertex3D] = []
    private var indices: [UInt32] = []
    private var isDirty = true
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?

    public init(device: MTLDevice) { self.device = device }

    // Processing ofMesh 互換 API
    public func addVertex(_ position: SIMD3<Float>) { ... }
    public func addVertex(_ x: Float, _ y: Float, _ z: Float) { ... }
    public func addNormal(_ normal: SIMD3<Float>) { ... }
    public func addColor(_ color: Color) { ... }
    public func addTexCoord(_ uv: SIMD2<Float>) { ... }
    public func addIndex(_ i: UInt32) { ... }
    public func addTriangle(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) { ... }

    public var vertexCount: Int { vertices.count }
    public var indexCount: Int { indices.count }

    public func getVertex(_ index: Int) -> SIMD3<Float> { ... }
    public func setVertex(_ index: Int, _ position: SIMD3<Float>) { ... }

    public func clear() { ... }

    /// GPU バッファを更新（isDirty の場合のみ）
    internal func ensureBuffers() {
        guard isDirty else { return }
        vertexBuffer = device.makeBuffer(bytes: vertices, length: ..., options: .storageModeShared)
        if !indices.isEmpty {
            indexBuffer = device.makeBuffer(bytes: indices, length: ..., options: .storageModeShared)
        }
        isDirty = false
    }
}
```

Canvas3D に `mesh(_ dynamicMesh: DynamicMesh)` メソッドを追加。

**テスト方針**: 頂点の追加・変更・描画の単体テスト

---

### B-10: カスタム頂点シェーダー対応

**目的**: CustomMaterial でフラグメントだけでなく頂点シェーダーもカスタマイズ可能に

**対象ファイル**:
- `Sources/metaphor/Drawing/CustomMaterial.swift`
- `Sources/metaphor/Drawing/Canvas3D.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`

**現状**:
- CustomMaterial は `fragmentFunction` のみ保持
- Canvas3D のカスタムパイプライン (L719-755) は頂点シェーダーが固定 (`metaphor_canvas3DVertex`)

**変更内容**:
1. CustomMaterial に optional な vertexFunction を追加:
```swift
public final class CustomMaterial {
    public let fragmentFunctionName: String
    public let vertexFunctionName: String?  // NEW
    let fragmentFunction: MTLFunction
    let vertexFunction: MTLFunction?  // NEW
    // ...
}
```

2. Canvas3D のパイプラインビルドで vertexFunction があればそれを使う:
```swift
let vertexFn = material.vertexFunction ?? shaderLib.function(named: "metaphor_canvas3DVertex", from: .canvas3D)
```

3. SketchContext.createMaterial にオプションパラメータ追加:
```swift
public func createMaterial(
    source: String,
    fragmentFunction: String,
    vertexFunction: String? = nil  // NEW
) throws -> CustomMaterial
```

4. パイプラインキャッシュキーに vertexFunction 名を含める

**テスト方針**: カスタム頂点シェーダー付きマテリアルのパイプライン構築テスト

---

## Phase C: 差別化 (Processing を超える)

### C-11: シェーダーホットリロード

**目的**: MSL シェーダーの外部ファイル読み込みとランタイム再コンパイル

**対象ファイル**:
- `Sources/metaphor/Core/ShaderLibrary.swift`
- `Sources/metaphor/Drawing/CustomMaterial.swift`
- `Sources/metaphor/PostProcess/CustomPostEffect.swift`

**変更内容**:
1. ShaderLibrary に reload メソッド追加:
```swift
public func reload(key: String) throws {
    // functions キャッシュからこのキーに関連するエントリを削除
    functions = functions.filter { !$0.key.hasPrefix("\(key).") }
    // library 自体はそのまま（再登録は呼び出し側の責任）
}

public func registerFromFile(path: String, as key: String) throws {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    try register(source: source, as: key)
}
```

2. CustomMaterial / CustomPostEffect に reload メソッド追加:
```swift
public func reload(shaderLibrary: ShaderLibrary) throws {
    // libraryKey で再取得
    guard let fn = shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) else {
        throw CustomMaterialError.functionNotFound(fragmentFunctionName)
    }
    // fragmentFunction を差し替え（let → var に変更必要）
}
```

3. Canvas3D の `customPipelineCache` をクリアするメソッドを追加

4. SketchContext に `reloadShader(key:)` を追加

**テスト方針**: シェーダーソースを変更 → reload → 再コンパイル成功を検証

---

### C-12: GUI パラメータコントロール

**目的**: ランタイムでパラメータを調整できる軽量 GUI

**対象ファイル (新規)**:
- `Sources/metaphor/UI/ParameterGUI.swift`
- `Sources/metaphor/UI/GUIRenderer.swift`

**設計**:
```swift
@MainActor
public final class ParameterGUI {
    private var sliders: [(label: String, binding: Binding<Float>, min: Float, max: Float)] = []
    private var toggles: [(label: String, binding: Binding<Bool>)] = []
    private var colorPickers: [(label: String, binding: Binding<Color>)] = []

    public func slider(_ label: String, value: inout Float, min: Float = 0, max: Float = 1)
    public func toggle(_ label: String, value: inout Bool)
    public func colorPicker(_ label: String, value: inout Color)

    /// Canvas2D 上に GUI を描画
    internal func draw(canvas: Canvas2D)
}
```

**実装方針**:
- Canvas2D のプリミティブ (rect, text, line) を使って GUI を自己描画
- マウスイベントと連携してインタラクション処理
- `Binding<T>` ではなくクロージャベース getter/setter で値を橋渡し
- 最初は slider + toggle のみの最小実装

**Sketch API**:
```swift
func draw() {
    gui.slider("radius", value: &radius, min: 10, max: 200)
    gui.slider("speed", value: &speed, min: 0.1, max: 5.0)
    circle(width/2, height/2, radius)
}
```

**テスト方針**: GUI のレンダリング（クラッシュなし）、値の変更反映

---

### C-13: オフライン決定論レンダリングモード

**目的**: フレーム落ちなしの高品質動画レンダリング

**対象ファイル**:
- `Sources/metaphor/Core/MetaphorRenderer.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Export/VideoExporter.swift`

**変更内容**:
1. MetaphorRenderer に offline mode フラグ追加:
```swift
public var isOfflineRendering: Bool = false
public var offlineFrameRate: Double = 60.0
private var offlineFrameIndex: Int = 0

public var elapsedTime: Double {
    if isOfflineRendering {
        return Double(offlineFrameIndex) / offlineFrameRate
    }
    return CACurrentMediaTime() - startTime
}

public var deltaTime: Double {
    if isOfflineRendering {
        return 1.0 / offlineFrameRate
    }
    return _deltaTime
}
```

2. `renderOfflineFrame()` メソッド追加:
```swift
public func renderOfflineFrame() {
    isOfflineRendering = true
    renderFrame()
    offlineFrameIndex += 1
}
```

3. Sketch API:
```swift
public func beginOfflineRender(fps: Double = 60, totalFrames: Int) {
    // MTKView のレンダーループを停止
    // totalFrames 回 renderOfflineFrame() を呼ぶ
    // 各フレームで VideoExporter.captureFrame()
}
```

**テスト方針**: offlineFrameRate=30 で 10 フレーム → elapsedTime が 0, 1/30, 2/30... であること

---

### C-14: FBO フィードバック API

**目的**: 前フレームのレンダリング結果を次フレームのテクスチャとして利用

**対象ファイル**:
- `Sources/metaphor/Core/MetaphorRenderer.swift`
- `Sources/metaphor/Core/TextureManager.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**設計**:
```
フレーム N:
  1. previousFrameTexture = colorTexture のコピー (blit)
  2. renderPass で colorTexture に描画
  3. ユーザーが previousFrame() で MImage として取得可能

フレーム N+1:
  1. previousFrameTexture = 前フレームの colorTexture
  ...
```

**変更内容**:
1. MetaphorRenderer に前フレームテクスチャ保持:
```swift
private var previousFrameTexture: MTLTexture?

// renderFrame() の最初で blit コピー
private func capturePreviousFrame(commandBuffer: MTLCommandBuffer) {
    guard feedbackEnabled else { return }
    let src = textureManager.colorTexture!
    if previousFrameTexture == nil || ... {
        // テクスチャ作成
    }
    let blit = commandBuffer.makeBlitCommandEncoder()!
    blit.copy(from: src, to: previousFrameTexture!)
    blit.endEncoding()
}
```

2. SketchContext に `previousFrame() -> MImage`:
```swift
public func previousFrame() -> MImage? {
    guard let tex = renderer.previousFrameTexture else { return nil }
    return MImage(texture: tex, device: renderer.device)
}
```

3. Sketch API: `func previousFrame() -> MImage?`

**テスト方針**: feedback 有効化 → 2フレーム描画 → previousFrame が nil でないこと

---

### C-15: Indirect Draw によるパーティクル最適化

**目的**: 生存パーティクルのみを描画して GPU 負荷を削減

**対象ファイル**:
- `Sources/metaphor/Particle/ParticleSystem.swift`
- `Sources/metaphor/Shaders/ParticleShaders.swift`

**変更内容**:
1. `MTLDrawPrimitivesIndirectArguments` 用バッファ追加:
```swift
private var indirectBuffer: MTLBuffer!
private var counterBuffer: MTLBuffer!  // atomic counter
```

2. コンピュートシェーダーに生存カウント機能追加:
```msl
// カウンタをリセットするカーネル
kernel void resetCounter(device atomic_uint *counter [[buffer(0)]]) {
    atomic_store_explicit(counter, 0, memory_order_relaxed);
}

// update カーネル内で生存パーティクルを compact
if (p.sizeAndFlags.w >= 0.5) {
    uint idx = atomic_fetch_add_explicit(counter, 1, memory_order_relaxed);
    particlesOut[idx] = p;
}
```

3. Indirect arguments バッファを更新するカーネル:
```msl
kernel void buildIndirectArgs(
    device atomic_uint *counter [[buffer(0)]],
    device MTLDrawPrimitivesIndirectArguments *args [[buffer(1)]]
) {
    args->vertexCount = 4;
    args->instanceCount = atomic_load_explicit(counter, memory_order_relaxed);
    args->vertexStart = 0;
    args->baseInstance = 0;
}
```

4. `draw()` で `drawPrimitives(type:indirectBuffer:indirectBufferOffset:)` を使用

**テスト方針**: indirect draw 後にクラッシュしないこと。パフォーマンス計測。

---

## Phase D: エコシステム (コミュニティ成長)

### D-16: オーディオファイル再生

**目的**: MP3/WAV ファイルの再生とスペクトル解析

**対象ファイル**:
- `Sources/metaphor/Audio/AudioAnalyzer.swift`
- `Sources/metaphor/Audio/SoundFile.swift` (新規)
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**設計**:
```swift
@MainActor
public final class SoundFile {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let mixerNode: AVAudioMixerNode
    private let file: AVAudioFile

    public init(path: String) throws { ... }

    public func play() { ... }
    public func pause() { ... }
    public func stop() { ... }
    public func loop() { ... }

    public var isPlaying: Bool { ... }
    public var duration: Double { ... }
    public var position: Double { get set }
    public var volume: Float { get set }
    public var rate: Float { get set }

    /// AudioAnalyzer との統合
    public func connectAnalyzer(_ analyzer: AudioAnalyzer) {
        // mixerNode の出力にタップを設置
        // → analyzer の sampleBuffer に供給
    }
}
```

**Sketch API**:
```swift
var sound: SoundFile!
func setup() {
    sound = try! loadSound("music.mp3")
    sound.play()
}
func draw() {
    let spectrum = sound.analyzer.spectrum
}
```

**テスト方針**: ファイルロード成功、play/stop 状態遷移

---

### D-17: MIDI 入出力

**目的**: MIDI コントローラーとの接続

**対象ファイル (新規)**:
- `Sources/metaphor/Network/MIDIManager.swift`
- `Sources/metaphor/Network/MIDIMessage.swift`

**設計**:
```swift
import CoreMIDI

public struct MIDIMessage: Sendable {
    public let status: UInt8    // note on/off, CC, etc.
    public let channel: UInt8
    public let data1: UInt8     // note number / CC number
    public let data2: UInt8     // velocity / CC value

    public var isNoteOn: Bool { ... }
    public var isNoteOff: Bool { ... }
    public var isControlChange: Bool { ... }
}

@MainActor
public final class MIDIManager {
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var messageQueue: [MIDIMessage] = []

    public func start() { ... }
    public func stop() { ... }

    // 入力
    public func onNoteOn(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) { ... }
    public func onControlChange(_ handler: @escaping (UInt8, UInt8, UInt8) -> Void) { ... }
    public func controllerValue(_ cc: UInt8, channel: UInt8 = 0) -> Float { ... }

    // 出力
    public func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) { ... }
    public func sendControlChange(cc: UInt8, value: UInt8, channel: UInt8 = 0) { ... }

    // ポーリング（Sketch draw() 内で使用）
    public func poll() -> [MIDIMessage] { ... }
}
```

**Sketch API**:
```swift
var midi: MIDIManager!
func setup() {
    midi = createMIDI()
    midi.start()
}
func draw() {
    let val = midi.controllerValue(1) // mod wheel
}
```

**テスト方針**: MIDIManager の初期化、メッセージパースの単体テスト

---

### D-18: SVG/PDF ベクトル出力

**目的**: ベクトルフォーマットでの出力によるプリント品質のジェネラティブアート

**対象ファイル (新規)**:
- `Sources/metaphor/Export/VectorExporter.swift`
- `Sources/metaphor/Export/SVGWriter.swift`
- `Sources/metaphor/Export/PDFWriter.swift`

**設計**:
```swift
@MainActor
public final class VectorExporter {
    private var commands: [VectorCommand] = []
    private var isRecording = false

    public func beginRecord(format: VectorFormat = .svg) { ... }
    public func endRecord(to path: String) { ... }

    // Canvas2D の描画コマンドをキャプチャ
    internal func recordRect(x: Float, y: Float, w: Float, h: Float, fill: Color?, stroke: Color?) { ... }
    internal func recordEllipse(cx: Float, cy: Float, rx: Float, ry: Float, fill: Color?, stroke: Color?) { ... }
    internal func recordLine(x1: Float, y1: Float, x2: Float, y2: Float, stroke: Color, weight: Float) { ... }
    internal func recordPath(points: [(Float, Float)], closed: Bool, fill: Color?, stroke: Color?) { ... }
    internal func recordText(text: String, x: Float, y: Float, font: String, size: Float, fill: Color) { ... }
}

public enum VectorFormat {
    case svg
    case pdf
}

enum VectorCommand {
    case rect(x: Float, y: Float, w: Float, h: Float, fill: Color?, stroke: Color?, strokeWeight: Float)
    case ellipse(cx: Float, cy: Float, rx: Float, ry: Float, fill: Color?, stroke: Color?, strokeWeight: Float)
    case line(x1: Float, y1: Float, x2: Float, y2: Float, stroke: Color, strokeWeight: Float)
    case path(points: [(Float, Float)], closed: Bool, fill: Color?, stroke: Color?, strokeWeight: Float)
    case text(String, x: Float, y: Float, font: String, size: Float, fill: Color)
    case pushTransform(float3x3)
    case popTransform
}
```

**実装方針**:
- Canvas2D の各描画メソッド内で `vectorExporter?.recordXxx()` を呼ぶ
- SVGWriter: VectorCommand → SVG XML 文字列
- PDFWriter: VectorCommand → CGContext PDF 描画

**Sketch API**:
```swift
func keyPressed() {
    if key == "s" {
        beginRecord(.svg)
        draw()  // draw を再実行してキャプチャ
        endRecord("output.svg")
    }
}
```

**テスト方針**: SVG 出力が valid XML であること。PDF 出力ファイルが空でないこと。

---

### D-19: GIF 出力

**目的**: SNS 共有用の GIF アニメーション出力

**対象ファイル (新規)**:
- `Sources/metaphor/Export/GIFExporter.swift`

**設計**:
```swift
import ImageIO

@MainActor
public final class GIFExporter {
    private var frames: [CGImage] = []
    private var frameDelay: Double = 1.0 / 30.0

    public func beginRecord(fps: Int = 30) { ... }
    public func captureFrame(texture: MTLTexture) { ... }
    public func endRecord(to path: String) { ... }
}
```

**実装方針**:
- `CGImageDestination` + `kUTTypeGIF` を使用
- 各フレームで staging texture → CGImage → 配列に追加
- endRecord で全フレームを GIF ファイルに書き出し

**Sketch API**:
```swift
beginGIFRecord(fps: 15)
// ... フレーム描画 ...
endGIFRecord("output.gif")
```

**テスト方針**: 3フレームの GIF 出力 → ファイルサイズ > 0

---

### D-20: カメラオービットコントローラー

**目的**: マウスドラッグによるインタラクティブ 3D カメラ

**対象ファイル (新規)**:
- `Sources/metaphor/UI/OrbitCamera.swift`

**対象ファイル (変更)**:
- `Sources/metaphor/Drawing/Canvas3D.swift`
- `Sources/metaphor/Sketch/SketchContext.swift`
- `Sources/metaphor/Sketch/Sketch.swift`

**設計**:
```swift
@MainActor
public final class OrbitCamera {
    public var target: SIMD3<Float> = .zero
    public var distance: Float = 5.0
    public var azimuth: Float = 0       // 水平角 (radians)
    public var elevation: Float = 0.3   // 垂直角 (radians)
    public var sensitivity: Float = 0.005
    public var zoomSensitivity: Float = 0.1
    public var minDistance: Float = 0.1
    public var maxDistance: Float = 100.0
    public var minElevation: Float = -Float.pi / 2 + 0.01
    public var maxElevation: Float =  Float.pi / 2 - 0.01

    public var eye: SIMD3<Float> {
        // spherical to cartesian
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    public func handleMouseDrag(dx: Float, dy: Float) {
        azimuth -= dx * sensitivity
        elevation += dy * sensitivity
        elevation = max(minElevation, min(maxElevation, elevation))
    }

    public func handleScroll(delta: Float) {
        distance -= delta * zoomSensitivity
        distance = max(minDistance, min(maxDistance, distance))
    }

    public func apply(to canvas3D: Canvas3D) {
        canvas3D.camera(eye: eye, center: target, up: SIMD3(0, 1, 0))
    }
}
```

**Sketch API**:
```swift
func draw() {
    orbitControl()  // 自動でマウスドラッグ → カメラ回転
}
```

**テスト方針**: カメラ座標計算の数値テスト

---

## 追加改善 (各フェーズに組み込み)

### Phase A に追加:

**A-6: TextureManager の force-unwrap 除去**
- `colorTexture: MTLTexture!` → `MTLTexture` (非オプショナル、init で必ず作成)
- `makeTexture` 失敗時に明示的エラー

**A-7: VideoExporter のデータレース修正**
- `captureFrame` の `nonisolated(unsafe)` を `@Sendable` クロージャ + actor 分離に変更
- `finishWriting` と `captureFrame` のレース条件を serial queue で解決

### Phase B に追加:

**B-11: pushStyle/pushMatrix の名前修正**
- Canvas2D: `pushStyle()` を実際にスタイルのみ保存するように変更（トランスフォームを除外）
- Canvas3D: `pushMatrix()` を `pushState()` にリネーム、`pushMatrix()` は行列のみ保存に変更
- 互換性: 既存の `push()` / `pop()` は全状態保存のまま維持

**B-12: 不足ユーティリティ関数追加**
- `map()`, `constrain()`, `dist()`, `mag()`, `norm()` → 既に MathUtils.swift にあるか確認
  - ※ 調査の結果 MathUtils.swift に存在する模様。Sketch extension に未公開なら公開。
- `random()`, `randomSeed()`, `randomGaussian()` → 同上
- `millis()` → SketchContext.elapsedTime * 1000

---

## フェーズ間の依存関係

```
Phase A (基盤)
  └── Phase B (表現力) ← A完了が前提
       └── Phase C (差別化) ← B完了が望ましいが独立実行可能
            └── Phase D (エコシステム) ← 独立実行可能
```

Phase C と Phase D は互いに独立しており、並行して進められる。

---

## 実行時の注意事項

各フェーズ開始時に必ず:
1. `make build` で現在のビルド状態を確認
2. `make test` で現在のテスト状態を確認
3. MEMORY.md と IMPLEMENTATION_PLAN.md を読んでコンテキスト復帰
4. 各タスク完了後に `make test` でリグレッションチェック

コンテキストリセット時の指示テンプレート:
```
IMPLEMENTATION_PLAN.md の Phase X を実行してください。
現在のタスクは X-N からです。
まず make build && make test で現在の状態を確認し、
計画書に従って実装を進めてください。
```
