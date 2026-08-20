// 2D カスタムフラグメントシェーダ（Issue #647 / Epic #291 E2）。
//
// loadShader() で MSL を読み、shader() で適用し、図形を描き、resetShader() で解除する。
// 図形（rect / circle）が「シェーダを通す面」になる。
//
// 読み込んだ .metal は自動で監視される（#648）。走らせたまま
// CustomShader2D/Resources/wave.metal を編集して保存すると、再ビルド無しで絵が変わる。

import Foundation
import metaphor

/// wave.metal の WaveParams と同じレイアウト（fragment の buffer(4) に届く）。
struct WaveParams {
    var amount: Float
    var bands: Float
}

@main
final class CustomShader2D: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Custom Shader 2D")
    }

    var wave: Shader2D?

    /// 読み込む wave.metal のパス。
    ///
    /// `swift run` はパッケージディレクトリで動くので、**ソース側のファイル**を先に探す。
    /// バンドル内のコピー（`.build` 配下）を読んでしまうと、編集しても再ビルドするまで
    /// 変わらず、ホットリロード（#648）を試せない。別の場所から起動されたときのために
    /// バンドルへフォールバックする。
    private func shaderPath() -> String? {
        let source = "CustomShader2D/Resources/wave.metal"
        if FileManager.default.fileExists(atPath: source) { return source }
        return Bundle.module.path(
            forResource: "wave", ofType: "metal", inDirectory: "Resources")
    }

    func setup() {
        noStroke()
        guard let path = shaderPath() else {
            print("wave.metal が見つかりません")
            return
        }
        do {
            wave = try loadShader(path, fragment: "waveFragment")
        } catch {
            print("loadShader に失敗しました: \(error)")
        }
    }

    func draw() {
        background(12)
        guard let wave = wave else {
            fill(255, 80, 80)
            text("wave.metal を読み込めませんでした", 20, 40)
            return
        }

        // 全面: 弱い歪み・細かい縞
        wave.setParameters(WaveParams(amount: 0.3, bands: 18))
        shader(wave)
        rect(0, 0, width, height)

        // 同じシェーダを別のパラメータで円に掛ける。
        // shader() を呼び直すとバッチが切れ、その時点のパラメータが焼き込まれる。
        wave.setParameters(WaveParams(amount: 1.2, bands: 40))
        shader(wave)
        circle(width / 2, height / 2, 220)

        resetShader()

        // 解除後は組み込みシェーダに戻る
        fill(255, 220)
        text("shader() / resetShader()  —  mouse: \(Int(mouseX)), \(Int(mouseY))", 16, height - 20)
    }
}
