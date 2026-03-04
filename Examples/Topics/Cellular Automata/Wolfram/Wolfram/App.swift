import metaphor

@main
final class Wolfram: Sketch {
    var config: SketchConfig { SketchConfig(title: "Wolfram CA", width: 640, height: 360) }

    var cells: [Int] = []
    var rules: [Int] = [0, 1, 0, 1, 1, 0, 1, 0]
    var generation = 0

    func setup() {
        background(0)
        cells = Array(repeating: 0, count: Int(width))
        restart()
    }

    func draw() {
        render()
        generate()
        if generation > Int(height) {
            background(0)
            randomizeRules()
            restart()
        }
    }

    func restart() {
        for i in 0..<cells.count { cells[i] = 0 }
        cells[cells.count / 2] = 1
        generation = 0
    }

    func randomizeRules() {
        for i in 0..<8 { rules[i] = Int(random(2)) }
    }

    func generate() {
        var nextgen = Array(repeating: 0, count: cells.count)
        for i in 1..<cells.count - 1 {
            nextgen[i] = executeRules(cells[i - 1], cells[i], cells[i + 1])
        }
        for i in 1..<cells.count - 1 { cells[i] = nextgen[i] }
        generation += 1
    }

    func render() {
        for i in 0..<cells.count {
            fill(cells[i] == 1 ? 255 : 0)
            noStroke()
            rect(Float(i), Float(generation), 1, 1)
        }
    }

    func executeRules(_ a: Int, _ b: Int, _ c: Int) -> Int {
        if a == 1 && b == 1 && c == 1 { return rules[0] }
        if a == 1 && b == 1 && c == 0 { return rules[1] }
        if a == 1 && b == 0 && c == 1 { return rules[2] }
        if a == 1 && b == 0 && c == 0 { return rules[3] }
        if a == 0 && b == 1 && c == 1 { return rules[4] }
        if a == 0 && b == 1 && c == 0 { return rules[5] }
        if a == 0 && b == 0 && c == 1 { return rules[6] }
        if a == 0 && b == 0 && c == 0 { return rules[7] }
        return 0
    }

    func mousePressed() {
        background(0)
        randomizeRules()
        restart()
    }
}
