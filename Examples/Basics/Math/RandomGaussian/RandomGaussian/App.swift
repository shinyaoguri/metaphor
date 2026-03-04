import metaphor

@main
final class RandomGaussian: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Random Gaussian") }
    func setup() { background(0) }
    func draw() {
        let val = randomGaussian()
        let sd: Float = 60
        let mean = width / 2
        let x = val * sd + mean
        noStroke()
        fill(255, 10)
        ellipse(x, height / 2, 32, 32)
    }
}
