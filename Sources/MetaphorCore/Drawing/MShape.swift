import Metal
import simd

// MARK: - ShapeKind

/// リテインドシェイプのタイプと作成パラメータを定義します。
///
/// ``MShape`` と共に使用し、シェイプが表すジオメトリを指定します。
/// プリミティブはパラメータをインラインで保持し、カスタムシェイプは `.path2D` / `.path3D` を使用します。
public enum ShapeKind: Sendable {
    /// 子シェイプを保持するグループコンテナ。
    case group

    // MARK: 2D Primitives
    /// 位置とサイズで定義される矩形。
    case rect(x: Float, y: Float, width: Float, height: Float)
    /// 中心とサイズで定義される楕円。
    case ellipse(x: Float, y: Float, width: Float, height: Float)
    /// 3つの頂点で定義される三角形。
    case triangle(x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float)
    /// 4つの頂点で定義される四角形。
    case quad(x1: Float, y1: Float, x2: Float, y2: Float,
              x3: Float, y3: Float, x4: Float, y4: Float)
    /// 中心、サイズ、角度範囲、閉じモードで定義される弧。
    case arc(x: Float, y: Float, width: Float, height: Float,
             start: Float, stop: Float, mode: ArcMode)
    /// 2点間の線分。
    case line(x1: Float, y1: Float, x2: Float, y2: Float)
    /// 単一の点。
    case point(x: Float, y: Float)

    // MARK: 3D Primitives
    /// 幅、高さ、奥行きを持つボックス。
    case box(width: Float, height: Float, depth: Float)
    /// 半径とテッセレーション詳細度を持つ UV 球体。
    case sphere(radius: Float, detail: Int = 24)
    /// 幅と高さを持つ平面。
    case plane(width: Float, height: Float)
    /// 半径、高さ、テッセレーション詳細度を持つシリンダー。
    case cylinder(radius: Float, height: Float, detail: Int = 24)
    /// 半径、高さ、テッセレーション詳細度を持つコーン。
    case cone(radius: Float, height: Float, detail: Int = 24)
    /// リング半径、チューブ半径、テッセレーション詳細度を持つトーラス。
    case torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24)

    // MARK: Custom Geometry
    /// `beginShape`/`vertex`/`endShape` で定義されるカスタム2Dシェイプ。
    case path2D
    /// `beginShape`/`vertex`/`endShape` で定義されるカスタム3Dシェイプ。
    case path3D

    /// このタイプがカスタムジオメトリ（path2D または path3D）かどうか。
    var isPath: Bool {
        switch self {
        case .path2D, .path3D: return true
        default: return false
        }
    }

    /// このシェイプタイプが3Dジオメトリを表すかどうか。
    public var is3D: Bool {
        switch self {
        case .box, .sphere, .plane, .cylinder, .cone, .torus, .path3D:
            return true
        case .group:
            return false  // グループの次元は子に依存
        default:
            return false
        }
    }
}

// MARK: - ShapeVertex2D

/// リテインド2Dシェイプの頂点。オプションの頂点ごとの色と UV 座標を持ちます。
public struct ShapeVertex2D: Sendable {
    /// 2D空間での位置。
    public var position: SIMD2<Float>
    /// 頂点ごとの色オーバーライド。nil の場合はシェイプの塗りつぶし色を使用。
    public var color: SIMD4<Float>?
    /// テクスチャ座標。nil の場合はテクスチャマッピングなし。
    public var uv: SIMD2<Float>?

    public init(position: SIMD2<Float>, color: SIMD4<Float>? = nil, uv: SIMD2<Float>? = nil) {
        self.position = position
        self.color = color
        self.uv = uv
    }
}

// MARK: - ShapeVertex3D

/// リテインド3Dシェイプの頂点。法線、オプションの色、UV 座標を持ちます。
public struct ShapeVertex3D: Sendable {
    /// 3D空間での位置。
    public var position: SIMD3<Float>
    /// ライティング計算用の頂点法線。
    public var normal: SIMD3<Float>
    /// 頂点ごとの色オーバーライド。nil の場合はシェイプの塗りつぶし色を使用。
    public var color: SIMD4<Float>?
    /// テクスチャ座標。nil の場合はテクスチャマッピングなし。
    public var uv: SIMD2<Float>?

    public init(position: SIMD3<Float>, normal: SIMD3<Float> = SIMD3(0, 1, 0),
                color: SIMD4<Float>? = nil, uv: SIMD2<Float>? = nil) {
        self.position = position
        self.normal = normal
        self.color = color
        self.uv = uv
    }
}

// MARK: - ShapeStyle

/// シェイプ作成時にキャプチャされるビジュアルスタイルプロパティのスナップショット。
///
/// ``MShape`` 内部で塗りつぶし、ストローク、マテリアルの状態を保存するために使用されます。
/// シェイプの `styleEnabled` が true の場合、描画時にこのスタイルが適用されます。
/// false の場合はスケッチの現在のスタイルが代わりに使用されます。
public struct ShapeStyle {
    /// 塗りつぶし色（RGBA、0-1範囲）。
    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    /// ストローク色（RGBA、0-1範囲）。
    public var strokeColor: SIMD4<Float> = SIMD4(0, 0, 0, 1)
    /// ストロークの線幅（ピクセル単位）。
    public var strokeWeight: Float = 1.0
    /// 塗りつぶしが有効かどうか。
    public var hasFill: Bool = true
    /// ストロークが有効かどうか。
    public var hasStroke: Bool = true
    /// テクスチャ付きシェイプのティント色。
    public var tintColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    /// ティントが適用されるかどうか。
    public var hasTint: Bool = false
    /// 3Dマテリアルプロパティ。2D専用シェイプの場合は nil。
    var material: Material3D?

    /// デフォルトスタイルを作成します。
    public init() {}
}

// MARK: - MShape

/// ジオメトリ、スタイル、トランスフォームを保存して効率的に再利用するリテインドモードシェイプ。
///
/// ``Sketch/createShape(_:)`` または ``Sketch/createShape()`` でシェイプを作成し、
/// ``Sketch/shape(_:)`` で描画します。
///
/// ```swift
/// // In setup():
/// let star = createShape()
/// star.beginShape()
/// star.fill(.yellow)
/// star.noStroke()
/// for i in 0..<10 {
///     let angle = Float(i) * Float.pi / 5
///     let r: Float = (i % 2 == 0) ? 100 : 40
///     star.vertex(cos(angle) * r, sin(angle) * r)
/// }
/// star.endShape(.close)
///
/// // In draw():
/// shape(star, width / 2, height / 2)
/// star.rotate(0.01)
/// ```
@MainActor
public final class MShape {

    // MARK: - Identity

    /// 階層内でこのシェイプを識別するためのオプションの名前。
    public var name: String?

    /// GPU リソース作成に使用する Metal デバイス。
    let device: MTLDevice

    // MARK: - Kind & Dimensionality

    /// このインスタンスが表すシェイプの種類。
    public internal(set) var kind: ShapeKind

    /// このシェイプが3Dジオメトリを含むかどうか。
    ///
    /// グループの場合、いずれかの子が3Dであれば true を返します。
    public var is3D: Bool {
        switch kind {
        case .group:
            return children.contains { $0.is3D }
        default:
            return kind.is3D
        }
    }

    // MARK: - Style

    /// 作成時にキャプチャされたスタイルスナップショット。
    public var capturedStyle: ShapeStyle

    /// 描画時にシェイプ自体のスタイルが適用されるかどうか。
    /// false の場合はスケッチの現在のスタイルが代わりに使用されます。
    public private(set) var styleEnabled: Bool = true

    /// このシェイプに割り当てられたテクスチャ。
    public var texture: MTLTexture?

    // MARK: - Per-Shape Transform

    /// このシェイプの累積2D変換行列。
    /// `translate`、`rotate`、`scale` で変更され、`resetMatrix` でリセットされます。
    public var localTransform2D: float3x3 = float3x3(1)

    /// このシェイプの累積3D変換行列。
    /// `translate`、`rotate`、`rotateX/Y/Z`、`scale` で変更され、`resetMatrix` でリセットされます。
    public var localTransform3D: float4x4 = .identity

    // MARK: - Hierarchy

    /// 子シェイプ（グループシェイプ用）。
    public private(set) var children: [MShape] = []

    /// 親シェイプへの弱参照。
    weak var parent: MShape?

    // MARK: - 2D Custom Geometry (path2D)

    /// カスタム2Dシェイプの頂点。
    var vertices2D: [ShapeVertex2D] = []

    /// コンターホールを定義する `vertices2D` 内の範囲。
    var contourRanges: [Range<Int>] = []

    /// 2Dカスタムシェイプの描画モード。
    var shapeMode2D: ShapeMode = .polygon

    /// 2Dカスタムシェイプが閉じているかどうか。
    var closeMode2D: CloseMode = .open

    // MARK: - 3D Custom Geometry (path3D)

    /// カスタム3Dシェイプの頂点。
    var vertices3D: [ShapeVertex3D] = []

    /// 3Dカスタムシェイプの描画モード。
    var shapeMode3D: ShapeMode = .polygon

    /// 3Dカスタムシェイプが閉じているかどうか。
    var closeMode3D: CloseMode = .open

    // MARK: - Geometry Cache

    /// path2D 塗りつぶし用のキャッシュされたテッセレーション三角形（三角形ごとに3つの SIMD2）。
    var cachedTriangles2D: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)]?

    /// path2D ストローク用のキャッシュされたストロークアウトラインポイント。
    var cachedStrokeOutline2D: [(Float, Float)]?

    /// 3Dカスタムシェイプ（path3D）用のキャッシュされたメッシュ。
    var cachedMesh3D: Mesh?

    /// 3Dプリミティブ（box、sphere など）用のキャッシュされたメッシュ。
    var primitiveMesh3D: Mesh?

    /// 最後のキャッシュビルド以降にジオメトリが変更されたかどうか。
    var isDirty: Bool = true

    // MARK: - Shape Building State

    /// beginShape() が呼ばれ、endShape() がまだ呼ばれていないかどうか。
    var isRecording: Bool = false

    /// 次の3D頂点に適用する保留中の法線。
    var pendingNormal3D: SIMD3<Float>?

    /// コンター定義内にいるかどうかを追跡。
    var isInContour: Bool = false

    /// vertices2D 内の現在のコンターの開始インデックス。
    var contourStartIndex: Int = 0

    // MARK: - Initialization

    /// 指定された種類とキャプチャされたスタイルで新しいシェイプを作成します。
    ///
    /// - Parameters:
    ///   - device: GPU リソース用の Metal デバイス。
    ///   - kind: 作成するシェイプのタイプ。
    ///   - style: 初期スタイルスナップショット。
    init(device: MTLDevice, kind: ShapeKind, style: ShapeStyle = ShapeStyle()) {
        self.device = device
        self.kind = kind
        self.capturedStyle = style
    }

    // MARK: - Style Modification

    /// このシェイプの塗りつぶし色を設定します。
    public func setFill(_ color: Color) {
        capturedStyle.fillColor = color.simd
        capturedStyle.hasFill = true
    }

    /// このシェイプの塗りつぶしを有効または無効にします。
    public func setFill(_ enabled: Bool) {
        capturedStyle.hasFill = enabled
    }

    /// このシェイプのストローク色を設定します。
    public func setStroke(_ color: Color) {
        capturedStyle.strokeColor = color.simd
        capturedStyle.hasStroke = true
    }

    /// このシェイプのストロークを有効または無効にします。
    public func setStroke(_ enabled: Bool) {
        capturedStyle.hasStroke = enabled
    }

    /// このシェイプのストロークの太さを設定します。
    public func setStrokeWeight(_ weight: Float) {
        capturedStyle.strokeWeight = weight
    }

    /// このシェイプのテクスチャを設定します。
    public func setTexture(_ img: MImage) {
        self.texture = img.texture
    }

    /// テクスチャレンダリング用のティント色を設定します。
    public func setTint(_ color: Color) {
        capturedStyle.tintColor = color.simd
        capturedStyle.hasTint = true
    }

    /// シェイプ自体のスタイルを無効にし、描画時にスケッチの現在のスタイルを使用します。
    public func disableStyle() {
        styleEnabled = false
    }

    /// シェイプ自体のスタイルを有効にします（デフォルトの動作）。
    public func enableStyle() {
        styleEnabled = true
    }

    // MARK: - Transform (Accumulated)

    /// シェイプを2Dで平行移動します。
    public func translate(_ x: Float, _ y: Float) {
        var t = float3x3(1)
        t[2][0] = x
        t[2][1] = y
        localTransform2D = localTransform2D * t
    }

    /// シェイプを3Dで平行移動します。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        localTransform3D = localTransform3D * float4x4(translation: SIMD3(x, y, z))
    }

    /// シェイプを2Dで回転します（ラジアン）。
    public func rotate(_ angle: Float) {
        let c = cos(angle), s = sin(angle)
        var r = float3x3(1)
        r[0][0] = c; r[0][1] = s
        r[1][0] = -s; r[1][1] = c
        localTransform2D = localTransform2D * r
    }

    /// シェイプをX軸周りに回転します（ラジアン）。
    public func rotateX(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationX: angle)
    }

    /// シェイプをY軸周りに回転します（ラジアン）。
    public func rotateY(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationY: angle)
    }

    /// シェイプをZ軸周りに回転します（ラジアン）。
    public func rotateZ(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationZ: angle)
    }

    /// シェイプを2Dで均一にスケーリングします。
    public func scale(_ s: Float) {
        var m = float3x3(1)
        m[0][0] = s; m[1][1] = s
        localTransform2D = localTransform2D * m
    }

    /// シェイプを2Dで非均一にスケーリングします。
    public func scale(_ sx: Float, _ sy: Float) {
        var m = float3x3(1)
        m[0][0] = sx; m[1][1] = sy
        localTransform2D = localTransform2D * m
    }

    /// シェイプを3Dで非均一にスケーリングします。
    public func scale(_ sx: Float, _ sy: Float, _ sz: Float) {
        localTransform3D = localTransform3D * float4x4(scale: SIMD3(sx, sy, sz))
    }

    /// シェイプのトランスフォームを単位行列にリセットします。
    public func resetMatrix() {
        localTransform2D = float3x3(1)
        localTransform3D = .identity
    }

    // MARK: - Hierarchy

    /// このグループに子シェイプを追加します。
    ///
    /// - Parameter child: 追加する子シェイプ。以前の親がある場合は削除されます。
    public func addChild(_ child: MShape) {
        if let oldParent = child.parent {
            oldParent.children.removeAll { $0 === child }
        }
        child.parent = self
        children.append(child)
    }

    /// インデックスで子シェイプを取得します。
    ///
    /// - Parameter index: ゼロベースのインデックス。
    /// - Returns: 子シェイプ。インデックスが範囲外の場合は nil。
    public func getChild(_ index: Int) -> MShape? {
        guard index >= 0 && index < children.count else { return nil }
        return children[index]
    }

    /// 名前で子シェイプを取得します（幅優先探索）。
    ///
    /// - Parameter name: 検索する名前。
    /// - Returns: 一致する名前を持つ最初の子。見つからない場合は nil。
    public func getChild(_ name: String) -> MShape? {
        for child in children {
            if child.name == name { return child }
        }
        for child in children {
            if let found = child.getChild(name) { return found }
        }
        return nil
    }

    /// 直接の子の数。
    public var childCount: Int { children.count }

    // MARK: - Vertex Access

    /// このシェイプの合計頂点数。
    ///
    /// カスタムシェイプの場合は頂点数を返します。プリミティブの場合は0を返します。
    /// グループの場合はすべての子の頂点数の合計を返します。
    public var vertexCount: Int {
        switch kind {
        case .path2D:
            return vertices2D.count
        case .path3D:
            return vertices3D.count
        case .group:
            return children.reduce(0) { $0 + $1.vertexCount }
        default:
            return 0
        }
    }

    /// インデックスで頂点位置を取得します。
    ///
    /// 2Dシェイプの場合、z成分は0です。
    /// - Parameter index: ゼロベースの頂点インデックス。
    /// - Returns: 3成分ベクトルとしての頂点位置。範囲外の場合は nil。
    public func getVertex(_ index: Int) -> SIMD3<Float>? {
        switch kind {
        case .path2D:
            guard index >= 0 && index < vertices2D.count else { return nil }
            let p = vertices2D[index].position
            return SIMD3(p.x, p.y, 0)
        case .path3D:
            guard index >= 0 && index < vertices3D.count else { return nil }
            return vertices3D[index].position
        default:
            return nil
        }
    }

    /// インデックスで頂点位置を設定します（2D）。
    ///
    /// シェイプをダーティとしてマークし、次の描画時に再テッセレーションをトリガーします。
    /// - Parameters:
    ///   - index: ゼロベースの頂点インデックス。
    ///   - x: 新しいx座標。
    ///   - y: 新しいy座標。
    public func setVertex(_ index: Int, _ x: Float, _ y: Float) {
        guard case .path2D = kind, index >= 0 && index < vertices2D.count else { return }
        vertices2D[index].position = SIMD2(x, y)
        invalidateCache()
    }

    /// インデックスで頂点位置を設定します（3D）。
    ///
    /// シェイプをダーティとしてマークし、次の描画時にメッシュ再構築をトリガーします。
    /// - Parameters:
    ///   - index: ゼロベースの頂点インデックス。
    ///   - x: 新しいx座標。
    ///   - y: 新しいy座標。
    ///   - z: 新しいz座標。
    public func setVertex(_ index: Int, _ x: Float, _ y: Float, _ z: Float) {
        guard case .path3D = kind, index >= 0 && index < vertices3D.count else { return }
        vertices3D[index].position = SIMD3(x, y, z)
        invalidateCache()
    }

    // MARK: - Cache Invalidation

    /// ジオメトリキャッシュを無効としてマークし、次の描画時に再構築を強制します。
    func invalidateCache() {
        isDirty = true
        cachedTriangles2D = nil
        cachedStrokeOutline2D = nil
        cachedMesh3D = nil
    }
}
