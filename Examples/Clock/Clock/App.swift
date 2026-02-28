import metaphor
import Foundation

@main
final class ClockExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Clock")
    }

    func draw() {
        background(Color(gray: 0.95))

        let cx = width / 2
        let cy = height / 2
        let r: Float = min(cx, cy) * 0.7

        let date = Date()
        let cal = Calendar.current
        let hour = Float(cal.component(.hour, from: date))
        let minute = Float(cal.component(.minute, from: date))
        let second = Float(cal.component(.second, from: date))

        push()
        translate(cx, cy)

        // 文字盤
        fill(.white)
        stroke(Color(gray: 0.2))
        strokeWeight(4)
        circle(0, 0, r * 2)

        // 分目盛り（60本）
        for i in 0..<60 {
            let a = Float(i) / 60.0 * Float.pi * 2 - Float.pi / 2
            stroke(Color(gray: 0.7))
            strokeWeight(1)
            line(cos(a) * (r - 20), sin(a) * (r - 20),
                 cos(a) * (r - 10), sin(a) * (r - 10))
        }

        // 時間目盛り（12本）
        for i in 0..<12 {
            let a = Float(i) / 12.0 * Float.pi * 2 - Float.pi / 2
            let major = i % 3 == 0
            let inner = major ? r - 45 : r - 35
            stroke(Color(gray: 0.15))
            strokeWeight(major ? 4 : 2)
            line(cos(a) * inner, sin(a) * inner,
                 cos(a) * (r - 10), sin(a) * (r - 10))
            if major {
                fill(Color(gray: 0.15))
                noStroke()
                circle(cos(a) * (r - 55), sin(a) * (r - 55), 10)
            }
        }

        // 時針
        let ha = (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12 * Float.pi * 2 - Float.pi / 2
        stroke(Color(gray: 0.15))
        strokeWeight(6)
        line(0, 0, cos(ha) * r * 0.5, sin(ha) * r * 0.5)

        // 分針
        let ma = (minute + second / 60) / 60 * Float.pi * 2 - Float.pi / 2
        stroke(Color(gray: 0.25))
        strokeWeight(4)
        line(0, 0, cos(ma) * r * 0.7, sin(ma) * r * 0.7)

        // 秒針（赤）
        let sa = second / 60 * Float.pi * 2 - Float.pi / 2
        stroke(Color(r: 0.85, g: 0.1, b: 0.1))
        strokeWeight(2)
        line(-cos(sa) * r * 0.15, -sin(sa) * r * 0.15,
             cos(sa) * r * 0.8, sin(sa) * r * 0.8)

        // 中心点
        fill(Color(gray: 0.15))
        noStroke()
        circle(0, 0, 16)
        fill(Color(r: 0.85, g: 0.1, b: 0.1))
        circle(0, 0, 8)

        pop()
    }
}
