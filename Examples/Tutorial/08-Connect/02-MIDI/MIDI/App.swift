import metaphor

@main
final class MIDISketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "MIDI")
    }

    var midi: MIDIManager?

    // 見張るコントロールチェンジ番号。1 はモジュレーションホイールに割り当てられていることが多い
    let knobCCs: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    // 中央のオクターブ（C3 から B3）
    let padNotes: [UInt8] = Array(60...71)

    // 押された瞬間の強さを覚えておき、離れたあともしばらく残す残光
    var glow: [UInt8: Float] = [:]
    var log = "ノブを回すか鍵盤を押すと、届いたメッセージがここに出ます"

    func setup() {
        let midi = createMIDI()

        // 届いた瞬間に呼ばれるのではなく、poll() の中で呼ばれる
        midi.onNoteOn { [weak self] _, note, velocity in
            self?.glow[note] = Float(velocity) / 127
        }

        // start() は throws しない。失敗は isRunning と lastError で分かる
        midi.start()
        self.midi = midi
    }

    func draw() {
        background(14)
        guard let midi else { return }

        // 届いたぶんを取り出す。登録したコールバックもこの中で呼ばれる
        for message in midi.poll() {
            log = describe(message)
        }

        fadeGlow()
        drawKnobs(midi)
        drawPads(midi)
        drawStatus(midi)
    }

    /// 残光を実時間で減らす。フレームレートが揺れても同じ速さで消える
    private func fadeGlow() {
        for (note, value) in glow {
            let next = value - deltaTime * 1.2
            glow[note] = next > 0 ? next : nil
        }
    }

    /// CC の値（0.0〜1.0）を円弧の長さで見せる
    private func drawKnobs(_ midi: MIDIManager) {
        let spacing = width / Float(knobCCs.count)
        for (index, cc) in knobCCs.enumerated() {
            let value = midi.controllerValue(cc)  // 0.0〜1.0 に正規化済み
            let x = spacing * (Float(index) + 0.5)
            let y: Float = 108

            noFill()
            stroke(Color(gray: 0.25))
            strokeWeight(6)
            arc(x, y, 54, 54, -PI * 1.25, PI * 0.25)

            stroke(Color(r: 0.4, g: 0.85, b: 1))
            arc(x, y, 54, 54, -PI * 1.25, -PI * 1.25 + PI * 1.5 * value)

            noStroke()
            fill(Color(gray: 0.75))
            textSize(11)
            textAlign(.center, .top)
            text("CC \(cc)", x, y + 34)
            fill(Color(gray: 0.5))
            // 生の値（0〜127）も見せる。仕様上の刻みが分かる
            text("\(midi.controllerRawValue(cc))", x, y + 48)
        }
    }

    /// ノートを 12 個のパッドで見せる。押している間と、離れたあとの残光を描き分ける
    private func drawPads(_ midi: MIDIManager) {
        let padWidth = (width - 40) / Float(padNotes.count)
        for (index, note) in padNotes.enumerated() {
            let x = 20 + padWidth * Float(index)
            let held = midi.isNoteActive(note)  // いま押されているか
            let after = glow[note] ?? 0

            noStroke()
            if held {
                fill(Color(r: 1, g: 0.85, b: 0.4))
            } else if after > 0 {
                fill(Color(r: 1, g: 0.85, b: 0.4, alpha: after * 0.6))
            } else {
                fill(Color(gray: 0.22))
            }
            rect(x + 2, 200, padWidth - 4, 70)
        }

        fill(Color(gray: 0.5))
        textSize(11)
        textAlign(.left, .top)
        text("ノート \(padNotes.first ?? 0)〜\(padNotes.last ?? 0)", 20, 278)
    }

    private func drawStatus(_ midi: MIDIManager) {
        noStroke()
        textAlign(.left, .top)

        textSize(13)
        if midi.isRunning {
            fill(Color(r: 0.5, g: 1, b: 0.6))
            text("MIDI 入力: 動作中", 20, 24)
        } else {
            fill(Color(r: 1, g: 0.5, b: 0.4))
            let reason = midi.lastError?.localizedDescription ?? "理由の申告なし"
            text("MIDI を開けませんでした: \(reason)", 20, 24)
        }

        fill(Color(gray: 0.8))
        textSize(12)
        text(log, 20, height - 32)
    }

    /// 届いたメッセージを 1 行に均す。種類ごとに意味の違うバイトが入っている
    private func describe(_ message: MIDIMessage) -> String {
        let channel = "ch\(message.channel + 1)"
        if message.isControlChange {
            return "\(channel)  CC \(message.controlNumber) = \(message.controlValue)"
        }
        if message.isNoteOn {
            return "\(channel)  Note On \(message.note) vel \(message.velocity)"
        }
        if message.isNoteOff {
            return "\(channel)  Note Off \(message.note)"
        }
        if message.isPitchBend {
            return "\(channel)  Pitch Bend \(message.pitchBendValue)"
        }
        return "\(channel)  status \(message.status)"
    }
}
