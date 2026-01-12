import SwiftUI
import metaphor

@main
struct BasicShapesApp: App {
    var body: some Scene {
        WindowGroup {
            sketch(width: 800, height: 600) { g in
                // 背景をグレーに
                g.background(51)

                // マウス位置に円を描画
                g.noStroke()
                if g.mousePressed {
                    g.fill(255, 100, 100)  // 押してる時は赤
                } else {
                    g.fill(100, 255, 100)  // 通常は緑
                }
                g.ellipse(g.mouseX, g.mouseY, 80, 80)

                // マウスの軌跡を線で描画
                g.stroke(255, 150)
                g.strokeWeight(2)
                g.line(g.pmouseX, g.pmouseY, g.mouseX, g.mouseY)

                // 中央に移動して回転する四角形
                g.pushMatrix()
                g.translate(g.width / 2, g.height / 2)
                g.rotate(Float(g.frameCount) * 0.02)

                g.fill(100, 100, 255, 200)  // 半透明の青
                g.stroke(255)
                g.strokeWeight(2)
                g.rect(-75, -75, 150, 150)
                g.popMatrix()

                // 情報表示用の四角形
                g.fill(0, 180)
                g.noStroke()
                g.rect(10, 10, 200, 80)

                // マウス座標を表示（四角形で代用）
                // 実際のテキスト描画はPhase 3で実装予定
                g.fill(255)
                let barWidth = g.mouseX / g.width * 180
                g.rect(15, 30, barWidth, 10)
                let barHeight = g.mouseY / g.height * 180
                g.rect(15, 50, barHeight, 10)

                // キー入力インジケーター
                if g.keyPressed {
                    g.fill(255, 255, 0)
                    g.ellipse(g.width - 30, 30, 20, 20)
                }
            }
        }
        .windowResizability(.contentSize)
    }
}
