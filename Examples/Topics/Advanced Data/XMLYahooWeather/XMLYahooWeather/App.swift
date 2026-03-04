import metaphor

// NOTE: This example requires loadXML and network access which is not available in metaphor.

@main
final class XMLYahooWeather: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "XMLYahooWeather (Stub)", width: 640, height: 360)
    }
    func setup() { noLoop() }
    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires loadXML/network access\nnot available in metaphor", width / 2, height / 2)
    }
}
