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

    /// ``createAudioInput(fftSize:)`` の検証付きバリアント。
    ///
    /// `fftSize` が 2 の累乗でない場合は ``MetaphorCore/MetaphorError/invalidParameter(_:)``
    /// をスローします。不正な値を黙って受け入れず早期に気付きたい場合に使います。
    ///
    /// - Parameter fftSize: FFT ウィンドウサイズ（2 の累乗）。
    /// - Returns: 新しい ``MetaphorAudio/AudioAnalyzer`` インスタンス。
    public func makeAudioInput(fftSize: Int = 1024) throws -> AudioAnalyzer {
        guard fftSize >= 2, (fftSize & (fftSize - 1)) == 0 else {
            throw MetaphorError.invalidParameter("fftSize は 2 の累乗である必要があります (指定: \(fftSize))")
        }
        return AudioAnalyzer(fftSize: fftSize)
    }

    /// 再生と解析用のオーディオファイルを読み込みます。
    ///
    /// - Parameter path: オーディオファイルのファイルパス。
    /// - Returns: 新しい ``MetaphorAudio/SoundFile`` インスタンス。
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }
}
