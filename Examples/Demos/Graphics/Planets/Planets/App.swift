import Foundation
import metaphor

/// Planets
///
/// テクスチャを貼ったリテインドシェイプ（球）を 3 つ組んで、毎フレームは
/// 変換と `shape()` だけを呼ぶ。ジオメトリとテクスチャの割り当ては `setup()` で確定する。
///
/// 太陽・水星のテクスチャは http://planetpixelemporium.com、
/// 星空は http://www.galacticimages.com/（原典 Planets.pde, by Andres Colubri より）。
@main
final class Planets: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1024, height: 768, title: "Planets")
    }

    /// 星空を貼った遠景の板。
    ///
    /// 原典は `image()` で 2D として敷いてから `hint(DISABLE_DEPTH_MASK)` で
    /// 深度書き込みを切るが、metaphor は 2D バッチを 3D の**後**にフラッシュするので
    /// `image()` で敷くと惑星を覆い隠してしまう。代わりに 3D の板を奥に置く。
    var starfield: MShape!

    var sun: MShape!
    var planet1: MShape!
    var planet2: MShape!

    /// 遠景板を置く奥行き。
    let starfieldZ: Float = -1200

    func setup() {
        starfield = makeStarfield()

        // createShape(.sphere) の生成メッシュは UV を持つので、setTexture() だけで貼れる。
        sun = createShape(.sphere(radius: 150, detail: 40))
        if let tex = loadBundled("sun", "jpg") { sun.setTexture(tex) }

        planet1 = createShape(.sphere(radius: 150, detail: 40))
        if let tex = loadBundled("planet", "jpg") { planet1.setTexture(tex) }

        planet2 = createShape(.sphere(radius: 50, detail: 40))
        if let tex = loadBundled("mercury", "jpg") { planet2.setTexture(tex) }

        // リテインドシェイプは「作った時点のスタイル」を持ち歩くので、draw() 側の
        // noStroke() では消えない。ワイヤーフレームが出ないようシェイプ自身に指定する。
        for s in [starfield, sun, planet1, planet2] {
            s?.setStroke(false)
        }
    }

    func draw() {
        background(0)

        // 星空はライトの影響を受けないよう、ライトを消した状態で先に敷く。
        noLights()
        pushMatrix()
        translate(width / 2, height / 2, starfieldZ)
        shape(starfield)
        popMatrix()

        noStroke()
        fill(.white)

        pushMatrix()
        translate(width / 2, height / 2, -300)

        pushMatrix()
        rotateY(PI * Float(frameCount) / 500)
        shape(sun)
        popMatrix()

        // falloff: 0 で距離減衰を切る（Processing の pointLight は既定で減衰しない。
        // metaphor の既定 0.1 は 2 次項まで効くので、数百単位の座標系では真っ暗になる）。
        pointLight(width / 2, height / 2, 0, falloff: 0)
        rotateY(PI * Float(frameCount) / 300)
        translate(0, 0, 300)
        shape(planet2)
        popMatrix()

        noLights()
        // 半径 150 の球に対して光源が近すぎると見えている面のほとんどが陰になるので、
        // 原典より手前（カメラ側）に離して置く。
        pointLight(0.75 * width, 0.6 * height, 800, falloff: 0)

        pushMatrix()
        translate(0.75 * width, 0.6 * height, 50)
        shape(planet1)
        popMatrix()
    }

    /// 画面いっぱいに見える大きさの板を作り、星空テクスチャを貼る。
    ///
    /// 既定カメラは `(width/2, height/2, (height/2)/tan(fov/2))` に居て fov は
    /// `PI/3`（`Canvas3D` の既定）。そこから `starfieldZ` までの距離で視錐台が
    /// どれだけ開くかを逆算すると、ちょうど画面を覆う板の寸法が出る。
    private func makeStarfield() -> MShape {
        let cameraZ = (height / 2) / tan(PI / 6)
        let distance = cameraZ - starfieldZ
        let planeHeight = 2 * distance * tan(PI / 6)
        let planeWidth = planeHeight * width / height

        let s = createShape(.plane(width: planeWidth, height: planeHeight))
        if let tex = loadBundled("starfield", "jpg") { s.setTexture(tex) }
        return s
    }

    /// `Resources/` に同梱した画像を読む。
    ///
    /// SwiftPM は `Package.swift` の `resources:` で宣言したものしか `Bundle.module`
    /// に入れないので、原典の `data/` ではなくターゲット配下の `Resources/` に置いている。
    private func loadBundled(_ name: String, _ ext: String) -> MImage? {
        guard let path = Bundle.module.path(forResource: name, ofType: ext, inDirectory: "Resources")
        else { return nil }
        return try? loadImage(path)
    }
}
