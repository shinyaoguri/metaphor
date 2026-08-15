// 3D カスタムマテリアル（Issue #613）。原典と同じく GPU のトゥーンシェーダーで描く。
//
// createMaterialFromFile() で MSL のフラグメント関数を読み、material() で以降の 3D
// 描画に適用し、noMaterial() で組み込みシェーダーへ戻す。頂点シェーダーは組み込みのまま。
//
// 読み込んだ .metal は自動で監視される。走らせたまま
// ToonShading/Resources/Toon.metal のしきい値を編集して保存すると、再ビルド無しで
// 段の切れ目が動く。

import Foundation
import metaphor

@main
final class ToonShading: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ToonShading")
    }

    var toon: CustomMaterial?
    var shaderEnabled = true

    /// 読み込む Toon.metal のパス。
    ///
    /// `swift run` はパッケージディレクトリで動くので、**ソース側のファイル**を先に探す。
    /// バンドル内のコピー（`.build` 配下）を読んでしまうと、編集しても再ビルドするまで
    /// 変わらず、ホットリロードを試せない。別の場所から起動されたときのためにバンドルへ
    /// フォールバックする。
    private func shaderPath() -> String? {
        let source = "ToonShading/Resources/Toon.metal"
        if FileManager.default.fileExists(atPath: source) { return source }
        return Bundle.module.path(
            forResource: "Toon", ofType: "metal", inDirectory: "Resources")
    }

    func setup() {
        noStroke()
        guard let path = shaderPath() else {
            print("Toon.metal が見つかりません")
            return
        }
        do {
            toon = try createMaterialFromFile(path: path, fragmentFunction: "toonFragment")
        } catch {
            print("createMaterialFromFile に失敗しました: \(error)")
        }
    }

    func draw() {
        background(0)

        // マウスで光の向きを回す。カスタムマテリアルは組み込みのライト配列をそのまま
        // 読むので、directionalLight() がシェーダーへ届く。
        let dirY = (mouseY / height - 0.5) * 2
        let dirX = (mouseX / width - 0.5) * 2
        directionalLight(-dirX, -dirY, -1, color: Color(gray: 204.0 / 255))

        push()
        translate(width / 2, height / 2)
        if let toon = toon, shaderEnabled {
            material(toon)
            sphere(120)
            noMaterial()
        } else {
            // クリックで解除したとき（と読み込みに失敗したとき）は組み込みの
            // ライティングで描く。原典の resetShader() にあたる。
            fill(204)
            sphere(120)
        }
        pop()

        if toon == nil {
            fill(255, 80, 80)
            text("Toon.metal を読み込めませんでした", 20, 40)
        }
    }

    func mousePressed() {
        shaderEnabled.toggle()
    }
}
