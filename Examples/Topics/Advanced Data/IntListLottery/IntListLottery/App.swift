import metaphor

@main
final class IntListLottery: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "IntListLottery", width: 640, height: 360)
    }

    var lottery: [Int] = []
    var results: [Int] = []
    var ticket: [Int] = []

    func setup() {
        frameRate(30)

        for i in 0..<20 {
            lottery.append(i)
        }

        for _ in 0..<5 {
            let index = Int(random(Float(lottery.count)))
            ticket.append(lottery[index])
        }
    }

    func draw() {
        background(51)

        lottery.shuffle()

        showList(lottery, 16, 48)
        showList(results, 16, 100)
        showList(ticket, 16, 140)

        // Check matches
        for i in 0..<results.count {
            if i < ticket.count && results[i] == ticket[i] {
                fill(0, 255, 0, 100)
            } else {
                fill(255, 0, 0, 100)
            }
            ellipse(16 + Float(i) * 32, 140, 24, 24)
        }

        if frameCount % 30 == 0 {
            if results.count < 5 {
                if !lottery.isEmpty {
                    let val = lottery.removeFirst()
                    results.append(val)
                }
            } else {
                for val in results {
                    lottery.append(val)
                }
                results.removeAll()
            }
        }
    }

    func showList(_ list: [Int], _ x: Float, _ y: Float) {
        for i in 0..<list.count {
            let val = list[i]
            stroke(255)
            noFill()
            ellipse(x + Float(i) * 32, y, 24, 24)
            textAlign(.center)
            fill(255)
            text("\(val)", x + Float(i) * 32, y + 6)
        }
    }
}
