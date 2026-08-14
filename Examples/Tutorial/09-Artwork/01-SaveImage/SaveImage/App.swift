import metaphor

@main
final class SaveImageSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SaveImage")
    }

    // 相対パスはスケッチを起動したディレクトリから解決される。
    // swift run ならパッケージ直下なので、output/ がその隣にできる
    let stillPath = "output/artwork.png"
    let sequenceDirectory = "output/frames"

    var isRecordingSequence = false
    var recordedFrames = 0
    var status = "S: 1 枚保存    R: 連番の開始と停止"

    func setup() {
        // 同じ模様が毎回出るように種を固定する（再現性の話は 9.4 で）
        noiseSeed(9)
    }

    func draw() {
        background(16)
        drawGrid()

        if isRecordingSequence {
            // 記録中は 1 フレームにつき 1 枚が書き出される
            recordedFrames += 1
            status = "録画中 \(recordedFrames) 枚 → \(sequenceDirectory)    R: 停止"
        }

        drawStatusBar()
    }

    func keyPressed() {
        if key == "s" || key == "S" {
            // 予約するだけ。ファイルが書かれるのはこのフレームを描き終えたあと
            save(stillPath)
            status = "\(stillPath) に保存しました"
        } else if key == "r" || key == "R" {
            toggleSequence()
        }
    }

    private func toggleSequence() {
        if isRecordingSequence {
            endFrameRecord()
            isRecordingSequence = false
            status = "\(sequenceDirectory) に \(recordedFrames) 枚 書き出しました"
        } else {
            recordedFrames = 0
            // ディレクトリは無ければ作られる。パターンの %04d が連番になる
            beginFrameRecord(directory: sequenceDirectory, pattern: "frame_%04d.png")
            isRecordingSequence = true
        }
    }

    /// 保存したくなる絵。時刻ではなくフレーム番号で動かしているので、
    /// 何回目の実行でも 100 フレーム目は同じ絵になる
    private func drawGrid() {
        noStroke()
        let columns = 16
        let rows = 9
        let cellWidth = width / Float(columns)
        let cellHeight = height / Float(rows)
        let phase = Float(frameCount) * 0.006

        for column in 0..<columns {
            for row in 0..<rows {
                let n = noise(Float(column) * 0.28, Float(row) * 0.28, phase)
                fill(50 + n * 140, 110 + n * 100, 230 - n * 80)
                circle(
                    cellWidth * (Float(column) + 0.5),
                    cellHeight * (Float(row) + 0.5),
                    map(n, 0, 1, 4, cellWidth * 1.15)
                )
            }
        }
    }

    /// いま何が起きているかを画面に出す。書き出しは静かに終わるので、
    /// これが無いと成功したのか分からない
    private func drawStatusBar() {
        noStroke()
        fill(0, 0, 0, 170)
        rect(0, height - 36, width, 36)

        if isRecordingSequence {
            fill(230, 70, 70)
        } else {
            fill(70)
        }
        circle(24, height - 18, 12)

        fill(235)
        textSize(13)
        textAlign(.left, .center)
        text(status, 42, height - 18)
    }
}
