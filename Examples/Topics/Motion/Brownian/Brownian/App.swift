import metaphor

@main
final class Brownian: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Brownian")
    }

    let num = 2000
    let range: Float = 6
    var ax: [Float] = []
    var ay: [Float] = []

    func setup() {
        ax = [Float](repeating: width / 2, count: num)
        ay = [Float](repeating: height / 2, count: num)
    }

    func draw() {
        background(51)
        for i in 1..<num {
            ax[i - 1] = ax[i]
            ay[i - 1] = ay[i]
        }
        ax[num - 1] += random(-range, range)
        ay[num - 1] += random(-range, range)
        ax[num - 1] = constrain(ax[num - 1], 0, width)
        ay[num - 1] = constrain(ay[num - 1], 0, height)
        for i in 1..<num {
            let val = Float(i) / Float(num) * 204.0 + 51
            stroke(val)
            line(ax[i - 1], ay[i - 1], ax[i], ay[i])
        }
    }
}
