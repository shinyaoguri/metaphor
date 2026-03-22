# ``MetaphorAudio``

クリエイティブコーディングのためのオーディオ入力解析とサウンドファイル再生。

## Overview

MetaphorAudio はマイク入力からのリアルタイム FFT スペクトラム解析と、
解析機能統合済みのオーディオファイル再生を提供します。
``AudioAnalyzer`` でライブオーディオをキャプチャし、音量、スペクトラム、ビート情報を取得できます。
``SoundFile`` で MP3、WAV、AAC ファイルを再生し、オプションでスペクトラム解析も利用できます。

このモジュールは MetaphorCore に依存せず、単独で使用できます。
アンブレラモジュール（`import metaphor`）使用時は、`createAudioInput()` などの
便利なメソッドからアクセスできます。

### クイックスタート

```swift
// ライブマイク解析
let audio = AudioAnalyzer(fftSize: 1024)
try audio.start()

// 描画ループ内:
audio.update()
let bass = audio.band(0)      // 低域エネルギー
let mid = audio.band(1)       // 中域エネルギー
let treble = audio.band(2)    // 高域エネルギー
```

## Topics

### オーディオ解析

- ``AudioAnalyzer``

### サウンドファイル再生

- ``SoundFile``

### エラー

- ``SoundFileError``
