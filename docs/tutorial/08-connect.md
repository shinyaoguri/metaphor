---
title: 外とつなぐ
part: 8
slug: connect
description: OSC・MIDI・Syphon・パラメータで、スケッチを他のアプリや機材とつなぎます。
draft: false
---

# 第 8 部 外とつなぐ

第 7 部でスケッチは外の信号を**受け取れる**ようになりました。この部では、その口をさらに広げます。数値を他のアプリと**やりとりし**、描いた映像を他のアプリへ**流し**、調整したい値をスケッチの外へ**出します**。

ここまでのスケッチは、実行したら実行しっぱなしでした。値を変えたければコードを直して再ビルドし、映像を使いたければ画面を録画するしかありません。この部を終えると、スケッチは**動かしたまま外から操作でき、その映像は他のアプリの素材になります**。ライブや展示で metaphor を使うなら、ここが土台になります。

## この部の前提

第 2 部の図形・色と 2.7 の `text()`、第 3 部 3.2 の `map()` と 3.3 のイージング、第 4 部 4.1 のマウス、第 7 部で覚えた「`draw()` の先頭で `update()` を呼ぶ」型を使います。ネットワークやオーディオの前提知識は要りません。

## 8.1 OSC

![自分へ送った OSC の座標で描いた絵。十字が送った位置、水色の円が返ってきた位置で、下に送信と受信のログが並ぶ](https://i.gyazo.com/4c0d6e2b508ac72a98094d230f3bb975.png)

マウスを動かすと、細い十字がマウスの位置に、塗りつぶした円が**ネットワークを一周して返ってきた位置**に描かれます。動かしている間だけ円がわずかに遅れ、止めると重なります。下の帯には、いま送っているアドレスと、直前に受け取ったメッセージの中身が出ます。

### OSC は数値を送るための約束ごと

OSC（Open Sound Control）は、**アプリや機材のあいだで名前つきの数値をやりとりするための規約**です。`/pointer` のようなスラッシュ区切りのアドレスと、その値の並びを送るだけの単純なもので、TouchDesigner・Max・Ableton Live・TouchOSC・VJ ソフトなど、多くのツールが最初から話せます。

この節のスケッチは、**自分の送ったメッセージを自分で受け取ります**。送信先が `127.0.0.1`（自分自身）だからです。外部アプリを用意しなくても往復が成立するので、送信と受信の両方をひとつのスケッチで確かめられます。

### 送る

送信は `createOSCSender(host:port:)` で作ります。

```swift
sender = createOSCSender(host: "127.0.0.1", port: 9000)
sender?.send("/pointer", .float(mouseX), .float(mouseY), .float(size))
```

返り値が `OSCSender?` なのは、作れないことがあるからです（ポート 0 など）。失敗しても例外は飛ばず、`nil` が返って警告がコンソールへ出ます。

`send()` は投げっぱなしです。OSC が乗っている UDP には接続という概念が無いので、**相手がいなくても、届かなくてもエラーになりません**。呼んで何も起きないのは「送り出した」という意味でしかありません。

### 受ける

受信は 3 手です。ポートを指定して作り、アドレスごとにハンドラを登録し、`start()` します。

```swift
let receiver = createOSCReceiver(port: 9000)
receiver.on("/pointer") { values in ... }
try receiver.start()
```

`start()` は `throws` です。**そのポートを他のアプリがすでに使っていると失敗します**。OSC でつなぐ相手は同じマシンにいることが多く、ポートの取り合いは実際によく起きます。理由を握りつぶさず画面に出しておくと、あとで自分が助かります。

### poll() を呼ぶまでハンドラは呼ばれない

登録したハンドラは、メッセージが届いた瞬間には呼ばれません。届いたものはいったんキューに溜まり、`poll()` を呼んだときにまとめて配られます。

```swift
for message in receiver?.poll() ?? [] {
    log = ...   // 返り値には、いま配ったメッセージがそのまま入っている
}
```

受信はネットワークのスレッドで起きるので、届いた瞬間にハンドラを呼ぶと描画の途中で状態が書き換わります。`poll()` の一点に集めることで、**値が変わるのは常に `draw()` の中の決まった場所**になります。第 7 部の `update()` と同じ考え方です。

呼び忘れるとハンドラは一度も呼ばれず、エラーも出ません。絵が動かないだけです。

### 値には型がある

OSC の値は `OSCValue` という列挙で、`.float` / `.int` / `.string` / `.blob` の 4 つです。送り手と受け手で型が食い違っても、**エラーにはならず、ただ噛み合いません**。

```swift
guard values.count >= 3,
    case .float(let x) = values[0],
    case .float(let y) = values[1],
    case .float(let size) = values[2]
else { return }
```

外部ツールから受け取るときは特にこの `guard` が効きます。整数で送ってくるツールもあれば、値をひとつしか送らないツールもあります。**期待どおりでないものは捨てる**と書いておけば、相手の都合でスケッチが壊れることはありません。

### 他のアプリ・他のマシンへ送る

`host` を相手のアドレスに変えるだけです。同じマシンの別アプリなら `127.0.0.1` のまま、別のマシンなら `192.168.1.42` のような LAN のアドレスを書きます。ポート番号は**受け側が待っている番号**に合わせます。

思ったとおりに届かないときは、次の順に見ていきます。

| 見るところ | よくある原因 |
|---|---|
| 送信先のホストとポート | 受け側が待っている番号と違う |
| `start()` の結果 | ポートを他のアプリが使っていて、そもそも聞けていない |
| `draw()` の中の `poll()` | 呼び忘れ |
| ハンドラの `guard` | 相手が送ってくる値の型や個数が想定と違う |
| macOS のファイアウォール | 別のマシンからの受信がブロックされている |

<!-- tutorial-snippet: 08-Connect/01-OSC -->
```swift
import metaphor

@main
final class OSCSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "OSC")
    }

    // 送信先は自分自身。外部アプリへ送るなら host を相手のアドレスに変える
    let host = "127.0.0.1"
    let port: UInt16 = 9000

    var sender: OSCSender?
    var receiver: OSCReceiver?

    // 受信して初めて入る値。送った値をそのまま描かないのがこのスケッチの要点
    var received: Vec2?
    var receivedSize: Float = 0
    var log = "まだ 1 通も届いていません"

    func setup() {
        let receiver = createOSCReceiver(port: port)

        // アドレスごとにハンドラを登録する。呼ばれるのは poll() の中だけ
        receiver.on("/pointer") { [weak self] values in
            guard values.count >= 3,
                case .float(let x) = values[0],
                case .float(let y) = values[1],
                case .float(let size) = values[2]
            else { return }  // 型や個数が違う相手からのメッセージは黙って捨てる
            self?.received = Vec2(x, y)
            self?.receivedSize = size
        }

        do {
            // ポートが他のアプリに使われていると投げる
            try receiver.start()
            self.receiver = receiver
        } catch {
            log = "ポート \(port) を開けませんでした: \(error.localizedDescription)"
        }

        // 作れなかったときは nil が返る（理由はコンソールへ）
        sender = createOSCSender(host: host, port: port)
    }

    func draw() {
        background(16)

        // 送る — マウスの位置と、そこから決めた大きさを 3 つの float で
        let size = map(mouseY, 0, height, 30, 110)
        sender?.send("/pointer", .float(mouseX), .float(mouseY), .float(size))

        // 受ける — poll() が届いた順にハンドラを呼び、同じものを返す
        for message in receiver?.poll() ?? [] {
            log = ([message.address] + message.values.map(describe)).joined(separator: "  ")
        }

        drawSent()
        drawReceived()
        drawPanel()
    }

    /// 送った位置。細い十字で置く
    private func drawSent() {
        stroke(Color(gray: 0.55))
        strokeWeight(1)
        line(mouseX - 14, mouseY, mouseX + 14, mouseY)
        line(mouseX, mouseY - 14, mouseX, mouseY + 14)
    }

    /// 返ってきた位置。塗りの円で置く。往復が成立していれば十字に重なる
    private func drawReceived() {
        guard let received else { return }
        noStroke()
        fill(Color(r: 0.3, g: 0.75, b: 1, alpha: 0.85))
        circle(received.x, received.y, receivedSize)
    }

    private func drawPanel() {
        noStroke()
        fill(Color(gray: 0, alpha: 0.55))
        rect(0, height - 76, width, 76)

        fill(Color(gray: 0.95))
        textSize(13)
        textAlign(.left, .top)
        text("送信 → \(host):\(port)   /pointer x y size", 16, height - 66)
        text("受信 ← \(log)", 16, height - 46)

        fill(Color(gray: 0.65))
        textSize(11)
        text("十字が送った位置、円が返ってきた位置", 16, height - 24)
    }

    /// OSC の値は型ごとに case が分かれている。表示のために文字列へ均す
    private func describe(_ value: OSCValue) -> String {
        switch value {
        case .float(let v): return String(format: "%.1f", v)
        case .int(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .blob(let data): return "<\(data.count) バイト>"
        }
    }
}
```

実行: `cd Examples/Tutorial/08-Connect/01-OSC && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `receiver.on("/pointer")` を `receiver.onAny { address, values in ... }` に変えると、どんなアドレスでも受け取れます。アドレスを打ち間違えたときの挙動の違いを見てください
- 送信するアドレスだけを `/pointer` 以外に変えると、円はどうなりますか
- ハンドラの `guard` を外し、`.float(mouseX)` を `.int(Int32(mouseX))` に変えると何が起きますか
- 送信先のポートを受信と別の番号にして、どこにも届かないことを確かめてください

### ふりかえり

- [ ] OSC がアドレスと値の並びを投げるだけの規約だと分かった
- [ ] `poll()` を呼ぶまでハンドラが呼ばれないと分かった
- [ ] 投げっぱなしなので、届かなくてもエラーにならないと分かった
- [ ] 受け取った値は型と個数を確かめてから使う、と分かった

### もっと詳しく

- [`createOSCReceiver(port:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/metaphorcore/sketch/createoscreceiver%28port:%29), [`createOSCSender(host:port:)`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/metaphorcore/sketch/createoscsender%28host:port:%29) — `import metaphor` で生えるブリッジ API です
- [`OSCReceiver`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphornetwork/oscreceiver) — `on` / `onAny` / `poll` / `start`
- [`OSCSender`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphornetwork/oscsender) — 複数のメッセージをまとめて送る `sendBundle(_:)` もあります
- [`OSCValue`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphornetwork/oscvalue)
- 別の書き方の例: [`Examples/Samples/OSCLoopback`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Samples/OSCLoopback)

## 8.2 MIDI

この節だけ、実行結果の画像がありません。**MIDI コントローラが繋がっていないと、すべてのつまみが 0 のままの絵にしかならない**からです。撮ったところで読者の画面とは一致しないので、代わりに何が起きるかを文章で書きます。

つまみの付いた MIDI コントローラを繋いで実行すると、上段に 8 つの円弧が並びます。ノブを回すと対応する円弧が伸び、その下に生の値（0〜127）が出ます。鍵盤やパッドを押すと下段の四角が明るく光り、離すと少しずつ暗くなって消えます。画面の下には直前に届いたメッセージが 1 行で出ます。

コントローラを繋がずに実行すると、円弧は 0 のまま、四角は暗いままです。それでも左上には「MIDI 入力: 動作中」と出ます — CoreMIDI は開けていて、ただ話しかけてくる機材が無い状態です。

### start() は失敗しても投げない

```swift
let midi = createMIDI()
midi.start()
```

第 7 部の `createAudioInput()` は「作る」と「始める」が分かれていて、`start()` が `throws` でした。MIDI も作ってから始める点は同じですが、**`start()` は例外を投げません**。失敗したかどうかは 2 つのプロパティで確かめます。

```swift
if midi.isRunning == false {
    print(midi.lastError?.localizedDescription ?? "")
}
```

投げないぶん、確かめる側が書き忘れると失敗に気付けません。このスケッチが左上に状態を出しているのはそのためです。

機材の抜き差しは自動で拾われます。実行したあとにコントローラを繋いでも、そのまま使えます。

### 値の取り方は 2 通り

MIDI には「いまの値」と「起きたこと」があり、どちらも取れます。

| 知りたいこと | 書き方 |
|---|---|
| ノブがいまどこにあるか | `midi.controllerValue(1)`（0.0〜1.0）/ `midi.controllerRawValue(1)`（0〜127） |
| 鍵盤がいま押されているか | `midi.isNoteActive(60)` |
| 押された瞬間 | `midi.onNoteOn { channel, note, velocity in ... }` |
| 届いたメッセージそのもの | `for message in midi.poll()` |

前のふたつは metaphor が持ち続けているキャッシュで、`draw()` のどこで読んでも同じ値です。図形の大きさや色に直結させるならこちらです。

あとのふたつは**その瞬間にしか無い情報**です。押された強さ（ベロシティ）は押された瞬間にしか届かないので、あとで使いたければ自分で覚えておきます。このスケッチが `glow` という辞書に強さを保存し、`deltaTime` で減らしているのがそれです。第 7 部 7.2 のビート検出で「残光は自分で作る」と書いたのと同じ形になります。

### poll() は MIDI でも要る

```swift
for message in midi.poll() {
    log = describe(message)
}
```

OSC と同じく、`poll()` を呼んだときにコールバックが呼ばれ、同じメッセージが返り値でも受け取れます。呼び忘れると `onNoteOn` は一度も呼ばれません。

### CC は 128 段しかない

コントロールチェンジ（CC）の値は 0〜127 の整数です。7 ビットしかないので、ノブをゆっくり回すと**値が飛び飛びに動きます**。細かい調整をしたいところへ直結させると、階段状の動きがそのまま目に見えます。

対策は第 3 部 3.3 のイージングです。生の値をそのまま使わず、追従させた値を描画に使えば滑らかになります。

チャンネルは 0〜15 です。機材の画面には「1〜16」と出るのが普通なので、表示するときは 1 を足します（このスケッチの `message.channel + 1` がそれです）。

### 送ることもできる

`sendNoteOn` / `sendControlChange` で MIDI を送り出せます。ただし**受け取る相手が要ります**。同じマシンの音楽ソフトへ送るなら、macOS の「Audio MIDI 設定」で IAC ドライバを有効にして仮想的な接続先を作ります。既定では無効なので、有効にせずに送っても何も起きません。

<!-- tutorial-snippet: 08-Connect/02-MIDI -->
```swift
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
```

実行: `cd Examples/Tutorial/08-Connect/02-MIDI && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- 手元のコントローラのノブが CC いくつを送っているか、画面下のログで確かめてください。`knobCCs` をその番号に書き換えると円弧が動きます
- `controllerValue()` の値を直接使うのをやめ、`lerp` で追従させると、階段状の動きはどう変わりますか
- `padNotes` を `Array(36...47)` に変えてください。ドラムパッドの並びに合うことがあります

### ふりかえり

- [ ] `MIDIManager` の `start()` は投げず、`isRunning` と `lastError` で確かめると分かった
- [ ] いまの値（`controllerValue`）と、起きたこと（`onNoteOn`）の使い分けが分かった
- [ ] `poll()` を呼ばないとコールバックが呼ばれないと分かった
- [ ] CC が 0〜127 の 128 段で、細かい調整には粗いと分かった

### もっと詳しく

- [`createMIDI()`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/metaphorcore/sketch/createmidi%28%29) — `import metaphor` で生えるブリッジ API です
- [`MIDIManager`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphornetwork/midimanager) — 入出力の全メソッド
- [`MIDIMessage`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphornetwork/midimessage) — ピッチベンドやプログラムチェンジの読み方

## 8.3 Syphon

![Syphon で配信している同心円の絵。下に配信名 metaphor-tutorial と 1280x720 の表示](https://i.gyazo.com/181125a27366540735a7c533574881f4.png)

実行すると円弧が回り続けます。画面だけを見ていると、ここまでのスケッチと何も変わりません。違うのは、**同じ絵が Syphon サーバー `metaphor-tutorial` としても出ている**ことです。MadMapper・Resolume・VDMX や Syphon Simple Client のような受け側のアプリを開くと、サーバーの一覧にこの名前が現れ、選べば映像が届きます。

### Syphon は映像の出口

Syphon は、**macOS のアプリ同士が GPU 上のテクスチャをそのまま共有する仕組み**です。画面を録画したりキャプチャ機材を挟んだりせず、描いた絵が別のアプリの素材になります。metaphor でジェネラティブな映像を作り、投影やマッピングは専用ソフトに任せる、といった分担ができます。

### 有効化は名前を付けるだけ

```swift
SketchConfig(
    width: 1280, height: 720,
    title: "Syphon Share",
    syphonName: "metaphor-tutorial",
    windowScale: 0.5
)
```

`syphonName` を書いた時点で出力が始まります。名前にこだわらないなら `syphon: true` でよく、その場合は `title` がサーバー名になります。名前は受け側のアプリの一覧に出るものなので、複数のスケッチを同時に動かすなら区別できる名前を付けます。

`import metaphor` していれば、これだけで動きます。Syphon の実装は `MetaphorSyphon` という別のモジュールにありますが、アンブレラの `import metaphor` が出力の実装を自動で登録するためです（個別のモジュールだけを import している場合は `MetaphorSyphon.enable()` を明示的に呼びます）。

名前をコードに固定したくないときは、環境変数で上書きできます。

```bash
METAPHOR_SYPHON_NAME=live swift run
```

### 送るのは「最終的な絵」

第 1 部 1.4 で、metaphor はレンダリング解像度とウィンドウサイズを分けている、と書きました。オフスクリーンのテクスチャに描いてから、画面へ転送するときにアスペクト比を保って収める、という 2 段構えです。

**Syphon が publish するのは、その転送より前の最終テクスチャ**です。ポストプロセス（6.3）を掛けたあと、画面へ収める前の絵になります。

ここから 2 つのことが決まります。

- **窓の大きさを変えても、送り出す解像度は変わりません**。上のコードの `windowScale: 0.5` は手元の窓を 640×360 にするだけで、受け側には 1280×720 で届きます。出す解像度を固定したまま、手元では小さい窓で作業できます
- **レターボックスの黒帯は送られません**。窓の縦横比が合わないときに画面へ出る余白は転送のときに足されるもので、テクスチャには入っていません

### 隠れても止まらない

Syphon を有効にすると、レンダーループが自動でタイマー駆動へ切り替わります。macOS はウィンドウが隠れると画面の更新を間引くので、そのままでは**他のアプリの後ろに回した瞬間に送り出す映像が止まってしまう**からです。本番では metaphor の窓は隠れているのが普通なので、この切り替えが要ります。

同じ理由で、metaphor はスケッチが背面にあるときの省電力（App Nap）も既定で抑止しています。

### 出ているかどうかは受け側でしか分からない

Syphon を有効にしても、**スケッチの画面には何の変化もありません**。うまくいっているかを確かめるには受け側のアプリが要ります。手軽なのは Syphon の配布物に付いてくる Simple Client で、サーバーの一覧を出して選ぶだけのアプリです。

一覧に名前が出てこないときは、次を疑います。

| 見るところ | よくある原因 |
|---|---|
| サーバー名 | 環境変数 `METAPHOR_SYPHON_NAME` が残っていて、別の名前で出ている |
| 受け側アプリの起動順 | 先に開いていた一覧が更新されていない（開き直すと出る） |
| import | 個別モジュール構成で `MetaphorSyphon.enable()` を呼んでいない |

<!-- tutorial-snippet: 08-Connect/03-Syphon -->
```swift
import metaphor

@main
final class SyphonShare: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,  // 送り出す解像度。受け側にはこの大きさで届く
            height: 720,
            title: "Syphon Share",
            // 名前を決めた時点で Syphon 出力が有効になる。受け側にはこの名前で見える
            syphonName: "metaphor-tutorial",
            windowScale: 0.5  // 手元の窓だけ半分。送る絵は 1280x720 のまま
        )
    }

    let ringCount = 5

    func draw() {
        background(10, 12, 18)

        let t = Float(frameCount) * 0.01
        push()
        translate(width / 2, height / 2)

        // 送り出す素材そのもの。描き方は 2D の章までと何も変わらない
        noFill()
        for ring in 0..<ringCount {
            let ringF = Float(ring)
            let radius = 90 + ringF * 55
            stroke(Color(r: 0.3 + ringF * 0.12, g: 0.7, b: 1, alpha: 0.9 - ringF * 0.12))
            strokeWeight(4)
            let sweep = PI + sin(t + ringF * 0.7) * PI * 0.6
            arc(0, 0, radius * 2, radius * 2, t * (ringF + 1) * 0.3, t * (ringF + 1) * 0.3 + sweep)
        }

        noStroke()
        fill(Color(r: 1, g: 0.9, b: 0.5))
        circle(0, 0, 60)
        pop()

        drawOverlay()
    }

    /// 受け側で名前と解像度を確かめられるよう、絵に焼き込んでおく
    private func drawOverlay() {
        noStroke()
        fill(Color(gray: 0, alpha: 0.55))
        rect(0, height - 92, width, 92)

        fill(Color(gray: 0.95))
        textSize(22)
        textAlign(.left, .top)
        text("Syphon サーバー名: \(config.syphonName ?? "（無効）")", 32, height - 78)

        fill(Color(gray: 0.7))
        textSize(17)
        text("\(Int(width)) x \(Int(height))  /  手元の窓はその \(config.windowScale) 倍", 32, height - 44)

        // 受け側で切れていないかを確かめるための隅の目印
        stroke(Color(gray: 0.5))
        strokeWeight(3)
        noFill()
        rect(8, 8, width - 16, height - 16)
    }
}
```

実行: `cd Examples/Tutorial/08-Connect/03-Syphon && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `windowScale` を `0.25` に変えても、受け側に届く映像の大きさが変わらないことを確かめてください
- `syphonName` を消して `syphon: true` にすると、受け側の一覧に出る名前はどうなりますか
- スケッチの窓を他のアプリで完全に隠しても、受け側の映像が止まらないことを確かめてください

### ふりかえり

- [ ] `syphonName` を書くだけで映像の共有が始まると分かった
- [ ] 送り出す解像度が `config` の `width` / `height` で決まり、窓の大きさとは無関係だと分かった
- [ ] publish されるのがポストプロセス後・画面へ収める前のテクスチャだと分かった
- [ ] 出ているかどうかは受け側のアプリでしか確かめられないと分かった

### もっと詳しく

- [`SketchConfig`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/sketchconfig) — `syphonName` / `syphon` / `windowScale`
- [`SyphonOutput`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorsyphon/syphonoutput) — 自分でテクスチャを publish したいとき
- 複数の窓からそれぞれ別の名前で出す例: [`Examples/Samples/Syphon`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Samples/Syphon)

## 8.4 パラメータを外に出す

![左に count / radius / dotSize / showRing / palette のパラメータパネル、右にその値どおり輪に並んだ 9 個の水色の点](https://i.gyazo.com/3f18be7419ba082be09d9414546e2f00.png)

左のパネルにスライダー・トグル・選択肢が並び、ドラッグすると右の図形がその場で変わります。このパネルは自分でレイアウトしたものではなく、**プロパティの宣言から自動で作られたもの**です。

### 宣言する

調整したい値のプロパティに `@Param` を付けます。

```swift
@Param(min: 3, max: 24) var count: Int = 9
@Param(min: 20, max: 140) var radius: Float = 90
@Param var showRing: Bool = true
@Param(choices: ["cool", "warm", "mono"]) var palette: String = "cool"
```

読み書きはふつうのプロパティと変わりません。`count` と書けば値が読め、代入もできます。変わるのは、**この値がスケッチの外から見えるようになる**ことです。

`min` / `max` / `choices` は単なる制限ではありません。「この値は 3 から 24 の整数」「この値は 3 つのうちどれか」という**宣言そのものが外へ公開されます**。外からの書き込みは範囲に丸められ、選択肢に無い文字列は拒否されます。パネルにスライダーが出るのも、範囲が分かっているからです。

扱える型は `Float` / `Int` / `Bool` / `String` / `Color` / `Vec2` / `Vec3` です。

### パネルは 1 行

```swift
let panel = gui.params()
```

宣言した順に、型に応じたウィジェットが並びます。数値はスライダー、`Bool` はトグル、`choices` 付きの文字列は押すたびに切り替わるボタンです。

返り値はパネルの矩形 `(x, y, width, height)` です。パラメータを足すとパネルは縦に伸びるので、**絵の置き場所をこの矩形から決めておくと、あとでパラメータを増やしても重なりません**。この節のスケッチが図形の中心を計算しているのがそれです。

パネルを出したくないときは `gui.params()` を呼ばなければよく、宣言と永続化だけが残ります。

### 値はファイルに残る

`@Param` を 1 つでも宣言すると、値が `.metaphor/params/params.json` へ書き出されます。次に起動すると、そこから復元された値で `setup()` と `draw()` が動きます。

つまり**パネルで調整した結果は、再ビルドしても残ります**。コードに書いた初期値は「まだ一度も触っていないときの値」という意味になります。調整をやり直したければ、このファイルを消します。

```bash
cat .metaphor/params/params.json     # いまの値と、宣言（型・範囲・選択肢）
rm -r .metaphor/params               # 初期値に戻す
```

永続化が邪魔なときは、環境変数 `METAPHOR_PARAMS=0` で切れます。

### 外から書き込む

同じディレクトリにもうひとつファイルを置くと、外から値を変えられます。

```bash
echo '{"id":"set-1","values":{"count":18,"palette":"warm"}}' \
  > .metaphor/params/set-request.json
```

次のフレームで反映されます。再ビルドも再起動も要りません。

ここが `@Param` の眼目です。**GUI のスライダーも、このファイルも、コード内の代入も、同じひとつのストアを叩いています**。誰が書いても同じように反映され、同じように永続化されます。人がパネルを触りながら、同時に外部のツールが別のパラメータを動かす、といったことがそのまま成立します。

8.1 の OSC と組み合わせるなら、受け取った値を `@Param` のプロパティへ代入するだけです。パネルの表示もその場で追随します。

そして「外部のツール」には AI エージェントも含まれます。第 10 部で、AI がスケッチの絵を見ながらこの口を使って値を変える話が出てきます。

<!-- tutorial-snippet: 08-Connect/04-Parameters -->
```swift
import metaphor

@main
final class ParametersSketch: Sketch {
    // 宣言するだけでストアに載り、GUI にも外部からの書き込みにも同時に開かれる
    @Param(min: 3, max: 24) var count: Int = 9
    @Param(min: 20, max: 140) var radius: Float = 90
    @Param(min: 4, max: 40) var dotSize: Float = 20
    @Param var showRing: Bool = true
    @Param(choices: ["cool", "warm", "mono"]) var palette: String = "cool"

    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Parameters")
    }

    func draw() {
        background(18)

        // 宣言した全パラメータのパネルを 1 行で。返り値はパネルの矩形 (x, y, w, h)
        let panel = gui.params()

        // パネルを避けた残りの空間の真ん中に置く
        let left = panel.0 + panel.2 + 80
        push()
        translate((left + width) / 2, height / 2)

        if showRing {
            noFill()
            stroke(Color(gray: 0.45))
            strokeWeight(1)
            circle(0, 0, radius * 2)
        }

        noStroke()
        for i in 0..<count {
            let angle = Float(i) / Float(count) * TWO_PI
            fill(color(at: i))
            circle(cos(angle) * radius, sin(angle) * radius, dotSize)
        }
        pop()
    }

    /// palette は choices を持つ文字列パラメータ。宣言に無い値は書き込みが拒否される
    private func color(at index: Int) -> Color {
        let phase = Float(index) / Float(count)
        switch palette {
        case "warm":
            return Color(r: 1, g: 0.4 + phase * 0.4, b: 0.25)
        case "mono":
            let v = 0.35 + phase * 0.6
            return Color(r: v, g: v, b: v)
        default:
            return Color(r: 0.3, g: 0.6 + phase * 0.35, b: 1)
        }
    }
}
```

実行: `cd Examples/Tutorial/08-Connect/04-Parameters && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- パネルのスライダーを動かしてから終了し、もう一度実行してください。値が残っていることを確かめます
- `@Param var tint: Color = Color(r: 0.4, g: 0.8, b: 1)` を足すと、パネルに何が出ますか
- スケッチを動かしたまま `set-request.json` を書いて、`palette` を `"mono"` に変えてみてください
- `choices` に無い文字列を書き込むと、どうなりますか

### ふりかえり

- [ ] `@Param` を付けるだけで、値がスケッチの外から見えるようになると分かった
- [ ] `min` / `max` / `choices` が制限であると同時に、外への宣言でもあると分かった
- [ ] `gui.params()` の 1 行でパネルが出て、その矩形が返ってくると分かった
- [ ] GUI・ファイル・コードが同じストアの対等な書き手だと分かった

### もっと詳しく

- [`Param`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/param) — 宣言のしかたと永続化の仕組み
- [`ParameterStore`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/parameterstore) — 値と宣言を束ねる本体
- [`ParameterGUI`](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphorcore/parametergui) — 自動パネル以外のウィジェット
- ファイル契約（`params.json` / `set-request.json`）の詳細: [CONTRACT.md](https://github.com/shinyaoguri/metaphor/blob/main/CONTRACT.md)
- 全ての型を使った例: [`Examples/Samples/ParameterPanel`](https://github.com/shinyaoguri/metaphor/tree/main/Examples/Samples/ParameterPanel)

## この部のまとめ

スケッチに 3 種類の外向きの口ができました。

1. **数値の出入り口** — OSC と MIDI。どちらも `draw()` の中で `poll()` を呼んで受け取ります
2. **映像の出口** — Syphon。`syphonName` を書くだけで、描いた絵が他のアプリの素材になります
3. **調整値の口** — `@Param`。GUI からも、ファイルからも、同じ値を動かせます

共通しているのは、**metaphor が用意するのは口だけ**だということです。何を送り、何を受け、どう反応するかは作品しだいで、そこはここまでの部で作ってきた描画そのものです。

次の第 9 部では、外へ出すものをもうひとつ増やします。画面に流れて消えていた絵を、画像・動画・SVG として**残す**方法です。
