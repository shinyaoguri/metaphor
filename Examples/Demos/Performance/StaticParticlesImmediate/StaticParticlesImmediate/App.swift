import metaphor

@main
final class StaticParticlesImmediate: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "StaticParticlesImmediate")
    }

    // 粒子数は原典と同じ 50,000。ここを減らすと即時描画でも frameRate(60) に届いてしまい、
    // 対の StaticParticlesRetained と同じ数字が並んで比較にならない（#680）。
    // partSize だけ原典の 20 から落としてある: 原典は半透明スプライトを重ねるが、
    // metaphor 版は不透明の sphere なので 20 のままだと画面が白い塊で埋まる。
    let npartTotal = 50000
    let partSize: Float = 3
    var posX: [Float] = []
    var posY: [Float] = []
    var posZ: [Float] = []

    var fcount = 0
    var lastm = 0
    var frate: Float = 0
    let fint = 3

    func setup() {
        frameRate(60)
        for _ in 0..<npartTotal {
            posX.append(Float.random(in: -500...500))
            posY.append(Float.random(in: -500...500))
            posZ.append(Float.random(in: -500...500))
        }
    }

    func draw() {
        background(0)
        noStroke()

        // HUD が回転・平行移動を引きずらないよう、パーティクルの変換は push/pop で閉じる。
        pushMatrix()
        translate(width / 2, height / 2)
        rotateY(Float(frameCount) * 0.01)

        fill(255, 200)
        for n in 0..<npartTotal {
            pushMatrix()
            translate(posX[n], posY[n], posZ[n])
            // 3 引数 translate は 3D 描画にしか効かないため、原典の ellipse() ではなく
            // sphere() で描く（2D プリミティブだと全粒子が中央 1 点に潰れる / ADR-0005）。
            // 50,000 個を毎フレーム描くので分割数は既定の 24 から落とす。
            sphere(partSize / 2, detail: 6)
            popMatrix()
        }
        popMatrix()

        fcount += 1
        let m = millis()
        if m - lastm > 1000 * fint {
            frate = Float(fcount) / Float(fint)
            fcount = 0
            lastm = m
        }
        fill(255)
        textSize(14)
        text("fps: \(Int(frate))", 10, 20)
    }
}
