import metaphor

@main
final class SoftBody: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Soft Body") }

    var centerX: Float = 0, centerY: Float = 0
    let radius: Float = 45
    var rotAngle: Float = -90
    var accelX: Float = 0, accelY: Float = 0
    let springing: Float = 0.0009
    let damping: Float = 0.98
    let nodes = 5
    var nodeStartX: [Float] = []
    var nodeStartY: [Float] = []
    var nodeX: [Float] = []
    var nodeY: [Float] = []
    var angle: [Float] = []
    var frequency: [Float] = []
    var organicConstant: Float = 1

    func setup() {
        centerX = width / 2; centerY = height / 2
        nodeStartX = [Float](repeating: 0, count: nodes)
        nodeStartY = [Float](repeating: 0, count: nodes)
        nodeX = [Float](repeating: 0, count: nodes)
        nodeY = [Float](repeating: 0, count: nodes)
        angle = [Float](repeating: 0, count: nodes)
        frequency = (0..<nodes).map { _ in random(5, 12) }
        noStroke()
    }

    func draw() {
        fill(0, 100)
        rect(0, 0, width, height)
        drawShape()
        moveShape()
    }

    func drawShape() {
        for i in 0..<nodes {
            nodeStartX[i] = centerX + cos(radians(rotAngle)) * radius
            nodeStartY[i] = centerY + sin(radians(rotAngle)) * radius
            rotAngle += 360.0 / Float(nodes)
        }
        fill(255)
        beginShape()
        for i in 0..<nodes { vertex(nodeX[i], nodeY[i]) }
        for i in 0..<nodes - 1 { vertex(nodeX[i], nodeY[i]) }
        endShape(.close)
    }

    func moveShape() {
        let deltaX = (mouseX - centerX) * springing
        let deltaY = (mouseY - centerY) * springing
        accelX += deltaX; accelY += deltaY
        centerX += accelX; centerY += accelY
        accelX *= damping; accelY *= damping
        organicConstant = 1 - ((abs(accelX) + abs(accelY)) * 0.1)
        for i in 0..<nodes {
            nodeX[i] = nodeStartX[i] + sin(radians(angle[i])) * (accelX * 2)
            nodeY[i] = nodeStartY[i] + sin(radians(angle[i])) * (accelY * 2)
            angle[i] += frequency[i]
        }
    }
}
