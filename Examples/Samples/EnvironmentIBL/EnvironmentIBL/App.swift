// EnvironmentIBL
//
// environment() で環境（IBL + skybox）を与え、metallic / roughness を格子状に
// 振った球を見比べるサンプルです。
//
// PBR では metallic を上げるほど拡散反射が消えます（物理的に正しい挙動）。
// 消えた分を埋めるのは周囲の環境からの反射なので、環境が無いまま metallic を
// 上げると、金属ではなく「特徴のない灰色の塊」になります。
// 0 キーで環境を切ると、その状態を実際に見比べられます。
//
//   1 / 2 / 3       プリセット（studio / sunset / overcast）
//   0               環境オフ（noEnvironment）
//   B               背景の skybox 表示を切り替え（IBL だけ残す）
//   - / +           環境の強度
//
// 縦が metallic、横が roughness です。環境があると、左上（滑らかな金属）は
// 周囲を映し込み、右下（粗い誘電体）は柔らかく拡散する、という差が出ます。

import metaphor

@main
final class EnvironmentIBL: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 900, height: 600, title: "EnvironmentIBL")
    }

    private var preset: EnvironmentPreset? = .studio
    private var showBackground = true
    private var intensity: Float = 1.0

    private let columns = 5
    private let rows = 3

    func setup() {
        noStroke()
    }

    func draw() {
        background(8, 10, 14)

        if let preset {
            environment(preset, intensity: intensity, background: showBackground)
        } else {
            noEnvironment()
            // 環境が無いときも比較条件を揃える（トーンマップは自動昇格しないので明示）
            toneMapping(.acesFilmic)
        }

        // 環境は「埋める光」なので、形を出す直接光は別に要ります。
        // PBR の拡散項は π で割られるため、単灯では intensity を 1 より大きく取ります。
        directionalLight(-0.4, 0.55, -0.75, intensity: 2.0)

        for row in 0..<rows {
            for column in 0..<columns {
                let m = Float(row) / Float(rows - 1)
                let r = 0.05 + Float(column) / Float(columns - 1) * 0.75

                pushMatrix()
                translate(
                    width * (0.16 + 0.17 * Float(column)),
                    height * (0.30 + 0.22 * Float(row)),
                    0
                )
                fill(Color(r: 0.78, g: 0.74, b: 0.70))
                metallic(m)
                roughness(r)
                sphere(46)
                popMatrix()
            }
        }

        drawHUD()
    }

    /// 現在の設定を左上に出す（2D なので skybox より後に描かれ、前景として残ります）。
    private func drawHUD() {
        fill(235)
        textSize(15)
        text(headline, 24, 36)
        fill(140)
        textSize(12)
        text("1 = studio   2 = sunset   3 = overcast   0 = off   B = background   - / + : intensity", 24, 58)
        text("↓ metallic 0 → 1     → roughness 0.05 → 0.8", 24, 78)
    }

    private var headline: String {
        guard let preset else { return "noEnvironment()" }
        let name: String
        switch preset {
        case .studio: name = "studio"
        case .sunset: name = "sunset"
        case .overcast: name = "overcast"
        }
        return "environment(.\(name), intensity: \(String(format: "%.1f", intensity)), background: \(showBackground))"
    }

    func keyPressed() {
        switch key {
        case "1": preset = .studio
        case "2": preset = .sunset
        case "3": preset = .overcast
        case "0": preset = nil
        case "b", "B": showBackground.toggle()
        case "-", "_": intensity = max(0, intensity - 0.1)
        case "+", "=": intensity = min(3.0, intensity + 0.1)
        default: break
        }
    }
}
