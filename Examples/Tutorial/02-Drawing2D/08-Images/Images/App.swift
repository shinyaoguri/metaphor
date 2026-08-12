import Foundation
import metaphor

@main
final class Images: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Images")
    }

    // 読み込んだ画像は保持しておく。draw() のたびに読み直さない
    var picture: MImage?

    func setup() {
        noLoop()

        // 画像はパッケージのリソースとして同梱している。パスを解決してから読む
        guard
            let path = Bundle.module.path(forResource: "sample", ofType: "png", inDirectory: "Resources")
        else { return }
        picture = try? loadImage(path)
    }

    func draw() {
        background(24)

        guard let picture else {
            // 読み込みに失敗しても落とさず、画面に理由を出す
            fill(240)
            textSize(18)
            text("画像を読み込めませんでした", 40, 40)
            return
        }

        // 既定では x, y は左上。3 番目・4 番目の引数で表示サイズを変えられる
        image(picture, 20, 20, 200, 150)

        // imageMode(.center) にすると x, y が画像の中心になる
        imageMode(.center)
        image(picture, 350, 95, 200, 150)
        imageMode(.corner)

        // tint は画像に色を掛ける。白 255 が「そのまま」
        tint(120, 200, 255)
        image(picture, 20, 195, 200, 150)

        // 2 引数の tint はグレースケールとアルファ。重ねると下が透ける
        tint(255, 110)
        image(picture, 260, 195, 200, 150)
        image(picture, 340, 195, 200, 150)

        // 使い終わったら戻す。tint は以降のすべての image() に効く
        noTint()
        image(picture, 480, 20, 140, 105)
    }
}
