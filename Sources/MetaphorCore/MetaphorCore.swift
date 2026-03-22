/// Processing、p5.js、openFrameworks にインスパイアされた Swift + Metal クリエイティブコーディングライブラリ。
///
/// metaphor は Metal を活用した即時モードのクリエイティブコーディング環境を提供します。
/// ``Sketch`` プロトコルを実装して開始してください。ウィンドウの作成、
/// Metal デバイスのセットアップ、レンダーループはライブラリが自動的に処理します。
///
/// ```swift
/// import metaphor
///
/// @main
/// final class MySketch: Sketch {
///     func setup() {
///         size(1280, 720)
///     }
///
///     func draw() {
///         background(0.1)
///         fill(Color.white)
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```

@_exported import Metal
@_exported import MetalKit
@_exported import simd
@_exported import Syphon
