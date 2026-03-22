# ``MetaphorNetwork``

インタラクティブ・ライブパフォーマンス向けの OSC / MIDI 通信。

## Overview

MetaphorNetwork はクリエイティブコーディングやライブパフォーマンスで広く使われる
リアルタイム通信プロトコルを提供します。``OSCReceiver`` は UDP ベースの
Open Sound Control メッセージを受信し、``MIDIManager`` はコントローラー、
シンセサイザーなどの MIDI デバイスとの CoreMIDI 入出力を処理します。

このモジュールは MetaphorCore に依存せず、単独で使用できます。
アンブレラモジュール（`import metaphor`）使用時は、`createOSCReceiver(port:)` や
`createMIDI()` などの便利なメソッドからアクセスできます。

### クイックスタート

```swift
// OSC メッセージの受信
let osc = OSCReceiver(port: 9000)
osc.on("/sensor/value") { args in
    if case .float(let value) = args.first {
        print(value)
    }
}
try osc.start()

// MIDI コントローラー入力
let midi = MIDIManager()
midi.start()
let messages = midi.poll()
let knobValue = midi.controllerValue(1)  // CC#1 を 0.0〜1.0 に正規化
```

## Topics

### OSC

- ``OSCReceiver``
- ``OSCValue``
- ``OSCReceiverError``

### MIDI

- ``MIDIManager``
- ``MIDIMessage``
- ``MIDIMessageType``
