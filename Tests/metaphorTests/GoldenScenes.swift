import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// ゴールデンの標準解像度。小さいほど速く、退行の検出力は十分に残る。
///
/// `@MainActor` なスイート内の `static let` は既定引数から参照できないため、
/// ファイルスコープに置く。
let goldenImageSize = 128

/// ゴールデン PNG（`Tests/metaphorTests/Golden/<name>.png`）を持つシーンの名前。
///
/// `@Test(arguments:)` は Suite の外（nonisolated）から評価されるため、`@MainActor` な
/// ``GoldenScenes`` の static プロパティは渡せない。名前だけをここへ置き、本体は
/// ``GoldenScenes/scene(named:)`` で引く。
let goldenSceneNames: [String] = [
    "shapes-2d",
    "blend-modes",
    "lighting-blinn-phong",
    "lighting-pbr",
    "shadow-cast",
    "post-process",
    "transform-2d-on-3d",
]

/// コマンド記録 ON/OFF の全画素パリティ（#375）で見るシーンの名前。
///
/// ゴールデンの代表シーンをそのまま流用し、記録経路の要である
/// **2D-3D 交互**シーンを足す。パリティは経路を明示的に選んで比較するため、
/// ``GoldenScene/goldenMode``（`shadow-cast` だけ `.shadows`）は使わない。
let commandRecordParitySceneNames: [String] = goldenSceneNames + ["interleaved-2d-3d"]

/// ゴールデン照合とコマンド記録パリティが共有する代表シーンの定義。
///
/// シーンを 1 箇所に集約するのは、同じ絵を 2 つのテストが別々に書き下すと
/// 「ゴールデンだけ更新されてパリティは古い絵を見ている」といった食い違いが
/// 起きるため（#375 / #357）。
@MainActor
struct GoldenScene {

    /// ゴールデン PNG のファイル名（拡張子なし）兼、失敗メッセージ用の識別子。
    let name: String

    /// 正方形の一辺（ピクセル）。
    let size: Int

    /// ゴールデンを撮るときのメインパス経路。パリティ検証はこれを使わず経路を明示指定する。
    let goldenMode: MainPassMode

    /// ゴールデン照合の許容差。パリティ検証は閾値なし（完全一致）で見るため使わない。
    let tolerance: GoldenTolerance

    /// ポストエフェクトの生成。同じインスタンスを 2 回のレンダリングで使い回さないよう
    /// 毎回作り直す。
    let makeEffects: () -> [any PostEffect]

    /// 1 フレームぶんの描画。
    let draw: (SketchContext) -> Void

    init(
        name: String,
        size: Int = goldenImageSize,
        goldenMode: MainPassMode = .immediate,
        tolerance: GoldenTolerance = .default,
        makeEffects: @escaping () -> [any PostEffect] = { [] },
        draw: @escaping (SketchContext) -> Void
    ) {
        self.name = name
        self.size = size
        self.goldenMode = goldenMode
        self.tolerance = tolerance
        self.makeEffects = makeEffects
        self.draw = draw
    }
}

/// 代表シーンのカタログ。
@MainActor
enum GoldenScenes {

    /// 名前でシーンを引く。`@Test(arguments:)` から渡された名前を本体へ解決するのに使う。
    static func scene(named name: String) throws -> GoldenScene {
        try #require(all.first { $0.name == name }, "未知のシーン名: \(name)")
    }

    /// カタログ全体（ゴールデン用 + パリティ専用）。
    static let all: [GoldenScene] = [
        shapes2D,
        blendModes,
        lightingBlinnPhong,
        lightingPBR,
        shadowCast,
        postProcess,
        transform2DOn3D,
        interleaved2D3D,
    ]

    // MARK: - ゴールデンを持つシーン

    static let shapes2D = GoldenScene(name: "shapes-2d") { c in
        c.background(Color(r: 0.08, g: 0.09, b: 0.12))
        c.noStroke()
        c.fill(Color(r: 0.90, g: 0.30, b: 0.25))
        c.rect(10, 10, 44, 30)
        c.fill(Color(r: 0.20, g: 0.70, b: 0.90))
        c.circle(92, 30, 40)
        c.fill(Color(r: 0.95, g: 0.80, b: 0.20))
        c.triangle(20, 118, 60, 62, 100, 118)
        c.noFill()
        c.stroke(Color(r: 1, g: 1, b: 1))
        c.strokeWeight(3)
        c.arc(64, 64, 90, 90, 0, Float.pi)
        c.stroke(Color(r: 0.35, g: 1.0, b: 0.55))
        c.strokeWeight(1)
        c.line(4, 64, 124, 64)
    }

    static let blendModes = GoldenScene(name: "blend-modes") { c in
        c.background(Color(r: 0.10, g: 0.10, b: 0.12))
        c.noStroke()
        c.fill(Color(r: 0.55, g: 0.20, b: 0.20))
        c.rect(0, 0, 128, 128)

        c.blendMode(.additive)
        c.fill(Color(r: 0.30, g: 0.30, b: 0.60))
        c.rect(8, 8, 56, 56)

        c.blendMode(.multiply)
        c.fill(Color(r: 0.90, g: 0.90, b: 0.30))
        c.rect(64, 8, 56, 56)

        c.blendMode(.screen)
        c.fill(Color(r: 0.20, g: 0.60, b: 0.30))
        c.rect(8, 64, 56, 56)

        c.blendMode(.alpha)
        c.fill(Color(r: 1, g: 1, b: 1, alpha: 0.5))
        c.rect(64, 64, 56, 56)
    }

    /// `ambientLight` は 2D の `fill` と同じく **`colorMode` のレンジ基準**（既定 0〜255）。
    /// もとは `0.35`（= 0.35/255 ≒ 実質 0）で、環境光の退行をまったく検出できなかった
    /// （Issue #392）。レンジの 35% = `90` に直したことで、光が当たらない面の明るさが
    /// ゴールデンに写り、ambient が消える／変わる退行を捉えられる。
    ///
    /// `specular` も同じく colorMode 基準（#527 でグレー値が素通しだったのを直した）。
    /// もとは `0.9` と書かれていて、素通しだったため偶然ほぼ同じ値
    /// （`230/255 ≒ 0.902`）で描かれていた。そのため単位を直してもゴールデンは変わらない。
    /// なお **`shininess(48)` のハイライトはこのシーンの可視面にほとんど乗っていない**ため、
    /// 鏡面の強さを変えても絵が動かない（＝鏡面の退行はまだ捉えられていない）。#535。
    static let lightingBlinnPhong = GoldenScene(
        name: "lighting-blinn-phong", tolerance: .shaded
    ) { c in
        c.background(Color(r: 0.05, g: 0.05, b: 0.10))
        c.pbr(false)
        // カメラ（-z 方向を向く）側から当てて前面を照らす。真下からの光だと
        // 可視面がほぼ環境光だけになり、ゴールデンの識別力が落ちる。
        c.ambientLight(90)  // colorMode 基準（既定 0〜255）= レンジの約 35%
        c.directionalLight(-0.4, -0.5, -1)
        c.specular(230)  // colorMode 基準（既定 0〜255）= レンジの 90%
        c.shininess(48)
        c.fill(Color(r: 0.85, g: 0.55, b: 0.25))
        c.pushMatrix()
        c.translate(64, 64, 0)
        c.rotateY(0.6)
        c.rotateX(0.35)
        c.box(58)
        c.popMatrix()
    }

    /// ambient は `colorMode` のレンジ基準（既定 0〜255）。もとは `0.75`（実質 0）だった
    /// ため、環境光の寄与がまったく写っていなかった（Issue #392）。`120` は
    /// 「鏡面ハイライトが 255 に張り付かない上限」で選んだ値で、拡散・鏡面・環境光の
    /// 3 つが同時に識別できる（レンジをこれ以上上げるとハイライトが飽和して
    /// 鏡面側の検出力が落ちる）。
    static let lightingPBR = GoldenScene(name: "lighting-pbr", tolerance: .shaded) { c in
        c.background(Color(r: 0.03, g: 0.03, b: 0.05))
        c.pbr(true)
        // 環境マップを持たないため metallic を上げすぎると真っ黒になる。
        // 拡散と鏡面が両方見える範囲に収める（ゴールデンの識別力を確保）。
        c.metallic(0.25)
        c.roughness(0.45)
        c.ambientLight(120)  // colorMode 基準（既定 0〜255）
        c.directionalLight(-0.4, -0.5, -1)
        c.pointLight(30, 20, 140, color: Color(r: 1.0, g: 0.8, b: 0.6))
        c.fill(Color(r: 0.75, g: 0.75, b: 0.80))
        c.pushMatrix()
        c.translate(64, 64, 0)
        c.sphere(40, detail: 24)
        c.popMatrix()
    }

    /// 「床 + 上から差す光 + 影を落とす箱」という、影のもっとも自然な構図。
    ///
    /// `ambientLight` は 2D の `fill` と同じく **`colorMode` のレンジ基準**（既定 0〜255）
    /// なので、`0.35` のような 0〜1 のつもりの値を渡すと実質 0 になる。ここで
    /// 意味のある値（60）を使うのは、影の中の明るさ = ambient が保たれること
    /// （Issue #364 で修正した合成則）をゴールデンに写し込むため。
    ///
    /// ライト方向は「光が進む向き」で、y は画面下向き。したがって
    /// `directionalLight(_, +y, _)` が「上から差す光」になる。
    static let shadowCast = GoldenScene(
        name: "shadow-cast", goldenMode: .shadows, tolerance: .shaded
    ) { c in
        c.background(Color(r: 0.08, g: 0.08, b: 0.12))
        c.ambientLight(60)
        c.directionalLight(-0.35, 0.9, -0.5)
        c.noStroke()
        c.fill(Color(r: 0.85, g: 0.85, b: 0.88))
        c.pushMatrix()
        c.translate(64, 96, 0)
        c.box(120, 6, 120)                 // 影を受ける床
        c.popMatrix()
        c.fill(Color(r: 0.90, g: 0.40, b: 0.30))
        c.pushMatrix()
        c.translate(58, 56, 10)
        c.rotateY(0.5)
        c.box(34)                          // 影を落とす箱
        c.popMatrix()
    }

    static let postProcess = GoldenScene(
        name: "post-process",
        tolerance: .shaded,
        makeEffects: { [GrayscaleEffect(), VignetteEffect(intensity: 0.6, smoothness: 0.4)] }
    ) { c in
        c.background(Color(r: 0.10, g: 0.12, b: 0.20))
        c.noStroke()
        c.fill(Color(r: 0.95, g: 0.35, b: 0.20))
        c.circle(48, 48, 60)
        c.fill(Color(r: 0.20, g: 0.80, b: 0.95))
        c.rect(60, 60, 56, 44)
    }

    /// 2D 変換（`translate`/`rotate`/`scale` の 2D 側オーバーロード）が 3D 描画にも
    /// 効くこと（ADR-0005 Amendment 2026-08-02 の P3D 意味論統一）を画素で凍結する。
    ///
    /// 既存の 3D シーンはすべて 3 引数 `translate` を使っているため、統一前後で
    /// 1 画素も動かなかった。**このシーンだけが変換ファミリの適用先に検出力を持つ**
    /// （Issue #325 / #385）。統一を戻すと 3 つのボックスがすべてワールド原点
    /// （= 左上）へ集まり、画像が壊れる。
    ///
    /// ambient はもとは `0.45`（`colorMode` レンジ基準なので実質 0）だった（Issue #392）。
    /// `40` は「明るい面の R チャンネルが 255 に張り付かない上限」で選んだ値。
    /// これで光の当たらない面にも階調が残り、環境光の退行も検出できる。
    static let transform2DOn3D = GoldenScene(
        name: "transform-2d-on-3d", tolerance: .shaded
    ) { c in
        c.background(Color(r: 0.06, g: 0.07, b: 0.10))
        c.pbr(false)
        c.ambientLight(40)  // colorMode 基準（既定 0〜255）
        c.directionalLight(-0.4, -0.5, -1)
        c.noStroke()

        // 1) translate(x, y): 中央寄せしてから箱を置く（P3D 移植の最頻出イディオム）。
        c.pushMatrix()
        c.fill(Color(r: 0.90, g: 0.40, b: 0.30))
        c.translate(40, 44)
        c.box(30)
        c.popMatrix()

        // 2) translate + rotate(a): 2D の rotate が 3D では z 軸回転になる。
        c.pushMatrix()
        c.fill(Color(r: 0.30, g: 0.75, b: 0.90))
        c.translate(92, 40)
        c.rotate(0.6)
        c.box(34, 16, 16)
        c.popMatrix()

        // 3) translate + scale(sx, sy): 非均一スケールが z 等倍で効く。
        c.pushMatrix()
        c.fill(Color(r: 0.95, g: 0.82, b: 0.25))
        c.translate(64, 98)
        c.scale(1.6, 0.6)
        c.box(28)
        c.popMatrix()
    }

    // MARK: - パリティ専用シーン（ゴールデン PNG は持たない）

    /// 2D と 3D を**交互に**呼ぶシーン（#375。コマンド記録経路の本丸）。
    ///
    /// 記録経路は 2D/3D を別々のストリームへ溜め、再生時に
    /// `DrawStreamMerge.mergeOrder` で seq 昇順の 1 本へマージする。一方、即時経路の
    /// 2D はバッチをフレーム末尾までためてから吐くため、実効の重ね順は
    /// **「3D 全部 → 2D 全部」**になる（`Canvas3D.flushPending2D` は記録経路でしか
    /// 呼ばれない）。
    ///
    /// ## このシーンが守っている境界（重要・編集時の制約）
    ///
    /// 即時経路の重ね順は「呼び出し順」ではなく「**エンコードされた順**」で決まり、
    /// 2D と 3D でフラッシュのタイミングが違う:
    ///
    /// - 3D はインスタンスバッチに溜まり、`endFrame` の `canvas3D.end()` で吐かれる。
    /// - 2D もバッチに溜まるが、**パイプライン／ブレンドモードが切り替わった時点**で
    ///   その場で吐かれる（切り替えが無ければ `canvas.end()` = 3D の後）。
    ///
    /// つまり即時経路では「3D の前に吐かれてしまった 2D は 3D の**背後**に回る」。
    /// これは ADR-0002 の既知の制限として文書化された 1.0 の仕様であって退行ではない
    /// （`docs/design/deterministic-rendering.md`「2D を 3D の背後に描いた場合」）。
    /// 記録経路は `flushPending2D` で 3D 記録の直前に 2D を確定するため、呼び出し順を
    /// そのまま復元する。**この差はパリティの対象外にしなければならない。**
    ///
    /// そこでこのシーンは、支配的パターン `background → 3D → オーバーレイ` の枠内に
    /// 収まるよう次の 2 点を守っている。**編集するときは必ず維持すること**:
    ///
    /// 1. **3D と重なる 2D は、フレーム末尾まで吐かれない最後の 1 バッチだけ**にする
    ///    （= それを描いた後にパイプライン／ブレンドモードを切り替えない）。
    /// 2. それ以外の 2D（交互の合いの手）は、**どの 3D とも重ならない**領域に置く。
    ///
    /// 交互の呼び出し自体は 6 回あるので、`flushPending2D` による 2D バッチの分割・
    /// `mergeOrder` の run グルーピング・`Deferred2DSlot` のパイプラインキーは
    /// すべて実際に踏む。
    ///
    /// ## 何を検出できて、何を検出できないか
    ///
    /// - 検出できる: マージが**即時経路と食い違う方向**へ壊れること
    ///   （2D を 3D より前へ出す・2D どうしの順序を入れ替える・2D コマンドを
    ///   取りこぼす・パイプラインキーを取り違える等）。
    /// - 検出できない: マージが**ちょうど即時経路と同じ順序**（3D 全部 → 2D 全部）へ
    ///   退行すること。パリティは即時経路を正解として比べるので原理的に見えない。
    ///   そこは `CommandStreamTests` の `callOrder3DOverEarlier2D` /
    ///   `commandRecordOptInWithoutShadows`（後から描いた 3D が先の 2D の前面に来る）が
    ///   直接押さえている。2 つで挟んで初めて順序マージ全体が守られる。
    ///
    /// ゴールデン PNG は持たせていない。ここで固定したいのは「絵そのもの」ではなく
    /// 「記録 ON と OFF が同じ絵になること」で、ゴールデンを増やすと見た目の意図的な
    /// 変更のたびに更新コストが乗るため。見た目の凍結は上のゴールデン群が担う。
    ///
    /// ## 配置
    ///
    /// - 3D は上段（y ≒ 22〜58）に 3 つ、x 方向に離して置く（互いに重ならないので
    ///   同一深度での順序依存が入らない）。3D 箱の投影は透視で一辺より大きくなる
    ///   （近い面が拡大される）ため、下段との間隔は余裕を取ってある。
    /// - 合いの手の 2D は下段（y ≧ 92）。
    /// - 重ね順の検出力は最後の半透明帯（3 つの箱すべてに重なる）が担う。
    static let interleaved2D3D = GoldenScene(name: "interleaved-2d-3d") { c in
        c.background(Color(r: 0.06, g: 0.07, b: 0.10))
        c.pbr(false)
        c.ambientLight(70)  // colorMode 基準（既定 0〜255）
        c.directionalLight(-0.4, -0.5, -1)
        c.noStroke()

        // 1) 3D
        c.fill(Color(r: 0.95, g: 0.95, b: 0.95))
        c.pushMatrix()
        c.translate(24, 40, 0)
        c.rotateY(0.35)
        c.box(30)
        c.popMatrix()

        // 2) 2D（下段のマーク。3D とは重ねない）
        c.fill(Color(r: 0.85, g: 0.30, b: 0.25))
        c.rect(6, 96, 40, 24)

        // 3) 3D
        c.fill(Color(r: 0.90, g: 0.45, b: 0.30))
        c.pushMatrix()
        c.translate(64, 40, 0)
        c.rotateX(0.35)
        c.box(30)
        c.popMatrix()

        // 4) 2D: 2 に重なる半透明の円。2D どうしの順序（`Deferred2DSlot` の並び）が
        //    入れ替われば重なり部分の色が変わる。ここでのパイプライン切り替えは
        //    2 のバッチを 3D より前へ吐き出すが、下段には 3D が無いので影響しない。
        c.fill(Color(r: 0.20, g: 0.70, b: 0.90, alpha: 0.6))
        c.circle(40, 108, 44)

        // 5) 2D: ブレンドモードを変えたマーク（記録側が「バッチごとに記録時点の
        //    パイプラインキーを焼き込む」ことを踏む）。これも下段。
        c.blendMode(.additive)
        c.fill(Color(r: 0.25, g: 0.30, b: 0.55))
        c.rect(84, 96, 38, 24)
        c.blendMode(.alpha)

        // 6) 3D
        c.fill(Color(r: 0.95, g: 0.82, b: 0.25))
        c.pushMatrix()
        c.translate(104, 40, 0)
        c.rotateY(0.4)
        c.box(30)
        c.popMatrix()

        // 7) 2D オーバーレイ: 3 つの箱すべてに重なる半透明帯。**このあと 2D の
        //    パイプライン／ブレンドモードを切り替えないこと**（切り替えると即時経路で
        //    3D より先に吐かれ、背後へ回って両経路が食い違う）。順序マージが 2D を
        //    3D の手前から奥へ動かすと、ここが一気に食い違って赤くなる。
        c.fill(Color(r: 0.30, g: 1.0, b: 0.55, alpha: 0.5))
        c.rect(0, 24, 128, 32)
    }
}
