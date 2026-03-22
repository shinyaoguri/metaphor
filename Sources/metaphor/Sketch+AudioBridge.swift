import MetaphorCore
import MetaphorAudio

// MARK: - オーディオブリッジ

extension Sketch {
    /// リアルタイム FFT およびビート検出用のオーディオ入力アナライザーを作成します。
    ///
    /// - Parameter fftSize: FFT ウィンドウサイズ（2の累乗である必要があります）。
    /// - Returns: 新しい ``MetaphorAudio/AudioAnalyzer`` インスタンス。
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        AudioAnalyzer(fftSize: fftSize)
    }

    /// 再生と解析用のオーディオファイルを読み込みます。
    ///
    /// - Parameter path: オーディオファイルのファイルパス。
    /// - Returns: 新しい ``MetaphorAudio/SoundFile`` インスタンス。
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }
}
