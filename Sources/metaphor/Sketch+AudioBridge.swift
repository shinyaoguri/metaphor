import MetaphorCore
import MetaphorAudio

// MARK: - オーディオブリッジ

extension Sketch {
    /// リアルタイム FFT およびビート検出用のオーディオ入力アナライザーを作成します。
    ///
    /// 解析の開始には `start()` の呼び出しが必要です（自動では開始されません）。
    ///
    /// - Parameter fftSize: FFT ウィンドウサイズ（2 の累乗）。2 の累乗でない場合は
    ///   warning を出してデフォルト（1024）にフォールバックします。
    /// - Returns: 新しい ``MetaphorAudio/AudioAnalyzer`` インスタンス。
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        guard fftSize >= 2, (fftSize & (fftSize - 1)) == 0 else {
            metaphorWarning("createAudioInput: fftSize must be a power of two (got \(fftSize)); using 1024")
            return AudioAnalyzer(fftSize: 1024)
        }
        return AudioAnalyzer(fftSize: fftSize)
    }

    /// 再生と解析用のオーディオファイルを読み込みます。
    ///
    /// - Parameter path: オーディオファイルのファイルパス。
    /// - Returns: 新しい ``MetaphorAudio/SoundFile`` インスタンス。
    /// - Throws: ファイルが存在しない場合は ``MetaphorAudio/SoundFileError/fileNotFound(_:)``、
    ///   デコード・読み込みに失敗した場合は
    ///   ``MetaphorAudio/SoundFileError/loadFailed(path:detail:)``。
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }
}
