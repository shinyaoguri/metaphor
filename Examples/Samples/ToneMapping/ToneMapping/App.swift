// ToneMapping
//
// 強い光を当てた球の列を、3 通りのトーンマッピングで見比べるサンプルです。
//
// 3D のライティング結果は物理量なので 1.0 を超えますが、書き出し先は 8bit なので
// そのままではクランプされ、明るい部分がまとめて真っ白（255）に潰れます。
// toneMapping() は高輝度側を滑らかに 0…1 へ写像して、飛んだ部分の階調を戻します。
//
//   1 = none        トーンマップなし（既定）。ハイライトが白い塊になる
//   2 = reinhard    x / (1 + x)。飛ばないが中間調は眠い
//   3 = acesFilmic  暗部を締めてハイライトを丸める。金属や強い光源に向く
//
//   - / +           exposure()（トーンマップ前に掛かる露出倍率）
//
// none のままだと右側の粗い球まで一様に白く、球の丸みも roughness の差も見えません。
// acesFilmic に切り替えると、同じライティングのまま形と質感が戻ってきます。
//
// なお現時点では環境マップ（IBL）が無いため、metallic を 1.0 近くまで上げると
// 反射する環境が無く暗く沈みます（Epic #293 の G3b で対応予定）。ここでは
// metallic は控えめにして、トーンマッピング単体の効き方を見ています。

import metaphor

@main
final class ToneMapping: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 900, height: 520, title: "ToneMapping")
    }

    /// 現在のトーンマッピング。1 / 2 / 3 キーで切り替えます。
    private var mode: ToneMapMode = .acesFilmic
    /// トーンマップ前に掛かる露出倍率。- / + キーで増減します。
    private var exposureValue: Float = 1.0

    private let sphereCount = 5

    func setup() {
        noStroke()
    }

    func draw() {
        background(8, 10, 14)

        // どちらも「画面全体の性質」で、pushStyle / popStyle では巻き戻りません。
        toneMapping(mode)
        exposure(exposureValue)

        // 意図的に飽和させる強さの光。none だとこの時点でハイライトが飛びます。
        //
        // PBR の拡散項は π で割られるので、単灯では intensity を 1.0 より大きく
        // する必要があります（`directionalLight` の doc コメント参照）。ここでは
        // 飽和を起こすためにさらに強くしています。
        ambientLight(40)
        directionalLight(-0.35, 0.8, -0.5, intensity: 9)
        pointLight(width * 0.5, height * 0.2, 300, intensity: 7)

        // 左から右へ roughness だけを変えた球の列。
        // トーンマップが効いていれば、この差が階調として見えます。
        for i in 0..<sphereCount {
            let t = Float(i) / Float(sphereCount - 1)
            pushMatrix()
            translate(width * (0.17 + 0.165 * Float(i)), height * 0.52, 0)
            fill(Color(r: 0.95, g: 0.78, b: 0.52))
            metallic(0.25)
            roughness(0.06 + t * 0.5)
            sphere(58)
            popMatrix()
        }

        drawHUD()
    }

    /// 現在の設定を左上に出す（2D の描画なのでトーンマッピングは掛かりません）。
    private func drawHUD() {
        fill(235)
        textSize(15)
        text("toneMapping(.\(modeLabel))   exposure(\(String(format: "%.1f", exposureValue)))", 24, 36)
        fill(140)
        textSize(12)
        text("1 = none   2 = reinhard   3 = acesFilmic       - / + : exposure", 24, 58)
    }

    private var modeLabel: String {
        switch mode {
        case .none: return "none"
        case .reinhard: return "reinhard"
        case .acesFilmic: return "acesFilmic"
        }
    }

    func keyPressed() {
        switch key {
        case "1": mode = .none
        case "2": mode = .reinhard
        case "3": mode = .acesFilmic
        case "-", "_": exposureValue = max(0.1, exposureValue - 0.1)
        case "+", "=": exposureValue = min(4.0, exposureValue + 0.1)
        default: break
        }
    }
}
