import Testing
import Foundation
import os
@testable import MetaphorAudio

// MARK: - AudioAnalyzer

@Suite("AudioAnalyzer")
struct AudioAnalyzerTests {

    @Test("Default properties")
    @MainActor
    func defaultProperties() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.volume == 0)
        #expect(analyzer.spectrum.count == 512)  // fftSize/2 = 1024/2
        #expect(analyzer.waveform.count == 1024)
        #expect(analyzer.isBeat == false)
        #expect(analyzer.smoothing == 0.8)
        #expect(analyzer.beatThreshold == 1.5)
    }

    @Test("Custom FFT size")
    @MainActor
    func customFFTSize() {
        let analyzer = AudioAnalyzer(fftSize: 2048)
        #expect(analyzer.spectrum.count == 1024)
        #expect(analyzer.waveform.count == 2048)
    }

    @Test("Update without samples returns defaults")
    @MainActor
    func updateWithoutSamples() {
        let analyzer = AudioAnalyzer()
        analyzer.update()
        #expect(analyzer.volume == 0)
        #expect(analyzer.isBeat == false)
    }

    @Test("Injecting fewer samples than fftSize does not read out of bounds")
    @MainActor
    func injectShortSamples() {
        let analyzer = AudioAnalyzer()  // fftSize = 1024
        // fftSize より短い配列を注入しても配列外読み取りでクラッシュしない。
        analyzer.injectSamples([0.1, -0.2, 0.3, -0.4, 0.5])
        analyzer.update()
        // 正規化後も内部バッファ長は不変。
        #expect(analyzer.spectrum.count == 512)
        #expect(analyzer.waveform.count == 1024)
    }

    @Test("Injecting more samples than fftSize is truncated safely")
    @MainActor
    func injectLongSamples() {
        let analyzer = AudioAnalyzer()  // fftSize = 1024
        analyzer.injectSamples([Float](repeating: 0.25, count: 4096))
        analyzer.update()
        #expect(analyzer.spectrum.count == 512)
        #expect(analyzer.waveform.count == 1024)
    }

    @Test("Band returns 0 for empty spectrum")
    @MainActor
    func bandEmpty() {
        let analyzer = AudioAnalyzer()
        // spectrum is initialized with zeros
        #expect(analyzer.band(0) == 0)
        #expect(analyzer.band(1) == 0)
        #expect(analyzer.band(2) == 0)
    }

    @Test("Band returns 0 for out of range index")
    @MainActor
    func bandOutOfRange() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.band(-1) == 0)
        #expect(analyzer.band(3) == 0)
        #expect(analyzer.band(100) == 0)
    }

    @Test("bandEnergy returns 0 when not running")
    @MainActor
    func bandEnergyNotRunning() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.bandEnergy(lowFreq: 20, highFreq: 200) == 0)
    }

    @Test("Smoothing property is settable")
    @MainActor
    func smoothingSetting() {
        let analyzer = AudioAnalyzer()
        analyzer.smoothing = 0.95
        #expect(analyzer.smoothing == 0.95)
    }

    @Test("Smoothing is clamped to [0, 0.99]")
    @MainActor
    func smoothingClamped() {
        let analyzer = AudioAnalyzer()
        // 1 以上は spectrum が更新されなくなる（EMA が新値を無視する）
        analyzer.smoothing = 1.5
        #expect(analyzer.smoothing == 0.99)
        // 負値は発散・振動の原因になる
        analyzer.smoothing = -0.5
        #expect(analyzer.smoothing == 0)
    }

    @Test("AudioAnalyzerError has descriptions")
    @MainActor
    func errorDescriptions() {
        #expect(AudioAnalyzerError.noInputDevice.errorDescription?.isEmpty == false)
        #expect(AudioAnalyzerError.microphonePermissionDenied.errorDescription?.isEmpty == false)
    }

    @Test("Beat threshold is settable")
    @MainActor
    func beatThresholdSetting() {
        let analyzer = AudioAnalyzer()
        analyzer.beatThreshold = 2.0
        #expect(analyzer.beatThreshold == 2.0)
    }
}

// MARK: - SoundFile

@Suite("SoundFile")
@MainActor
struct SoundFileTests {

    @Test("SoundFileError for non-existent file")
    func fileNotFound() {
        #expect(throws: SoundFileError.self) {
            _ = try SoundFile(path: "/nonexistent/audio.mp3")
        }
    }

    @Test("SoundFileError has description")
    func errorDescription() {
        let error = SoundFileError.fileNotFound("/test/path.mp3")
        #expect(error.errorDescription?.contains("Audio file not found") == true)
    }
}

// MARK: - AudioAnalyzer injectSamples

@Suite("AudioAnalyzer injectSamples")
@MainActor
struct AudioAnalyzerInjectTests {

    @Test("injectSamples feeds data to update")
    func injectSamples() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        // Generate a simple sine wave
        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        analyzer.update()

        // After update, volume should be non-zero
        #expect(analyzer.volume > 0)
        // Waveform should be populated
        #expect(analyzer.waveform.count == 256)
        // Spectrum should be populated
        #expect(analyzer.spectrum.count == 128)
    }

    @Test("injectSamples without update has no effect")
    func injectWithoutUpdate() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        // Don't call update
        #expect(analyzer.volume == 0)
    }

    @Test("bandEnergy works with injected samples when sampleRate is provided")
    func bandEnergyWithInjectedSampleRate() {
        let sampleRate = 44100.0
        let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: sampleRate)

        // 440 Hz のサイン波を注入
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi * 440.0 / Float(sampleRate)) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()

        // 修正前は engine 前提のため injectSamples 経由では常に 0 だった
        #expect(analyzer.bandEnergy(lowFreq: 300, highFreq: 600) > 0)
    }

    @Test("bandEnergy returns 0 with injected samples when sampleRate is unknown")
    func bandEnergyWithoutSampleRate() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 64.0) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()
        #expect(analyzer.bandEnergy(lowFreq: 300, highFreq: 600) == 0)
        // 0 を返すこと自体は変えていない。黙って返さないことが直したところ（Issue #783）
        #expect(analyzer.didWarnAboutMissingSampleRate)
    }

    /// Issue #783 の再現そのまま。「解析は成立しているのに bandEnergy だけ 0」を固定する。
    @Test("解析が成立していても sampleRate 未設定なら bandEnergy は 0 のまま警告する")
    func bandEnergyWarnsWhenAnalysisSucceedsButRateIsMissing() {
        let analyzer = AudioAnalyzer(fftSize: 1024)  // sampleRate を渡し忘れた
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi * 440.0 / 44_100.0) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()

        // spectrum の山は 440Hz のビンに立っている = 「その帯域に何も無い」わけではない。
        // spectrum は EMA 平滑（既定 0.8）なので 1 フレームでは値が小さい。大きさではなく
        // 山の位置で「解析が成立している」ことを見る
        let peak = analyzer.spectrum.max() ?? 0
        let peakBin = analyzer.spectrum.firstIndex(of: peak) ?? -1
        let peakFreq = Float(peakBin) * Float(44_100) / 1024
        #expect(peak > 0)
        #expect(peakFreq > 350 && peakFreq < 550)

        // それでも bandEnergy は 0。区別が付かないので警告が出る
        #expect(analyzer.bandEnergy(lowFreq: 350, highFreq: 550) == 0)
        #expect(analyzer.didWarnAboutMissingSampleRate)
    }

    @Test("sampleRate を後から入れれば警告せずに値が返る")
    func bandEnergyStaysQuietOnceSampleRateIsSet() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        analyzer.sampleRate = 44_100
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi * 440.0 / 44_100.0) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()

        #expect(analyzer.bandEnergy(lowFreq: 350, highFreq: 550) > 0)
        #expect(!analyzer.didWarnAboutMissingSampleRate)
    }
}

// MARK: - volume / band(_:) のスケール（Issue #782）

/// doc コメントが謳うスケールを機械で留めておく検査。
/// `volume` は素の RMS ではなく 4 倍して 1.0 で飽和させた表示用の値、
/// `band(_:)` の境界は Hz ではなくビン比（`bins/8` / `bins/2`）で決まる。
@Suite("volume と band のスケール")
@MainActor
struct VolumeAndBandScaleTests {

    /// 振幅一定の矩形波なら RMS = 振幅なので、4 倍のゲインが直接読める。
    @Test("volume は RMS の 4 倍")
    func volumeIsFourTimesRMS() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        analyzer.injectSamples([Float](repeating: 0.1, count: 1024))
        analyzer.update()

        // RMS = 0.1 → 0.4。素の RMS を返しているなら 0.1 になる
        #expect(abs(analyzer.volume - 0.4) < 1e-5)
    }

    @Test("volume は 1.0 で飽和する")
    func volumeSaturates() {
        let quarter = AudioAnalyzer(fftSize: 1024)
        quarter.injectSamples([Float](repeating: 0.25, count: 1024))
        quarter.update()
        #expect(abs(quarter.volume - 1.0) < 1e-5)

        // 4 倍でも 1.0、8 倍でも 1.0。飽和後は入力の大小が読めない
        let half = AudioAnalyzer(fftSize: 1024)
        half.injectSamples([Float](repeating: 0.5, count: 1024))
        half.update()
        #expect(half.volume == 1.0)
    }

    // 以下 4 本は #941 で足した rms を固定する。
    // volume は 4 倍 + 飽和なので、飽和後は割り戻しても入力が復元できない。
    // rms はその手前の素の値を返す。

    /// 振幅一定の矩形波なら RMS = 振幅。`volume` が 4 倍していた分がここには乗らない。
    @Test("rms は素の RMS を返す（4 倍しない）")
    func rmsIsUnscaled() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        analyzer.injectSamples([Float](repeating: 0.1, count: 1024))
        analyzer.update()

        #expect(abs(analyzer.rms - 0.1) < 1e-5)
        // 同じフレームの volume は 4 倍された 0.4。両者は別物
        #expect(abs(analyzer.volume - 0.4) < 1e-5)
    }

    /// この Issue の本題。`volume` が 1.0 に張り付く領域で `rms` は伸び続ける。
    @Test("volume が飽和する領域でも rms は入力の大小を保つ")
    func rmsKeepsResolutionWhereVolumeSaturates() {
        func measure(_ amplitude: Float) -> (volume: Float, rms: Float) {
            let analyzer = AudioAnalyzer(fftSize: 1024)
            analyzer.injectSamples([Float](repeating: amplitude, count: 1024))
            analyzer.update()
            return (analyzer.volume, analyzer.rms)
        }

        let quarter = measure(0.25)  // RMS 0.25 = 飽和のちょうど境目
        let half = measure(0.5)  // その 2 倍

        // volume はどちらも 1.0。ここから入力の大小は読めない
        #expect(abs(quarter.volume - 1.0) < 1e-5)
        #expect(half.volume == 1.0)

        // rms は 0.25 と 0.5 で区別できる
        #expect(abs(quarter.rms - 0.25) < 1e-5)
        #expect(abs(half.rms - 0.5) < 1e-5)
        #expect(half.rms > quarter.rms)
    }

    @Test("無音では rms は 0")
    func rmsIsZeroForSilence() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        analyzer.injectSamples([Float](repeating: 0, count: 1024))
        analyzer.update()

        #expect(analyzer.rms == 0)
        #expect(analyzer.volume == 0)
    }

    @Test("解析前の rms は 0")
    func rmsStartsAtZero() {
        // processSamples を呼ぶのは update()。injectSamples すらしていない状態で
        // 前フレームの残りや未初期化値が漏れないことを見る。
        let analyzer = AudioAnalyzer(fftSize: 1024)
        #expect(analyzer.rms == 0)

        // injectSamples だけでは計算されない（update() を待つ）
        analyzer.injectSamples([Float](repeating: 0.5, count: 1024))
        #expect(analyzer.rms == 0)
    }

    /// サイン波は RMS = 振幅/√2 なので、振幅 1/(4/√2) ≈ 0.354 で飽和する。
    @Test("サイン波は振幅 0.354 あたりで飽和する")
    func sineSaturatesAroundOneThird() {
        func volume(amplitude: Float) -> Float {
            let analyzer = AudioAnalyzer(fftSize: 1024)
            analyzer.injectSamples(Self.sine(frequency: 1_000, amplitude: amplitude))
            analyzer.update()
            return analyzer.volume
        }

        // 振幅 0.2 → 4 * 0.2 / √2 ≈ 0.566（doc の「RMS そのもの」なら 0.141）
        #expect(abs(volume(amplitude: 0.2) - 0.566) < 0.01)
        #expect(volume(amplitude: 0.3) < 1.0)
        #expect(volume(amplitude: 0.4) == 1.0)
    }

    /// doc に書いた 44.1 kHz の境界（0-2.8k / 2.8k-11k / 11k-22k）を実際の音で確かめる。
    /// 旧コメントの「〜0-250 Hz」「250-2 kHz」「2 kHz+」なら 2 kHz は band 1 に入るはず。
    @Test("44.1 kHz では 2 kHz でもまだ低域（band 0）")
    func bandEdgesFollowSampleRate() {
        func loudestBand(frequency: Float) -> Int {
            let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: 44_100)
            analyzer.smoothing = 0
            analyzer.injectSamples(Self.sine(frequency: frequency, amplitude: 0.5))
            analyzer.update()
            let energies = (0..<3).map { analyzer.band($0) }
            return energies.firstIndex(of: energies.max()!)!
        }

        #expect(loudestBand(frequency: 200) == 0)
        #expect(loudestBand(frequency: 2_000) == 0)  // 上端は 44100/16 ≈ 2756 Hz
        #expect(loudestBand(frequency: 5_000) == 1)  // 上端は 44100/4 = 11025 Hz
        #expect(loudestBand(frequency: 15_000) == 2)
    }

    /// 境界はビン番号で決まるので、Hz は sampleRate に比例して動く。
    /// 同じ 3 kHz でも 44.1 kHz なら中域、8 kHz なら（sampleRate/4 = 2 kHz を超えて）高域。
    @Test("同じ周波数でもサンプルレートが変われば帯域が変わる")
    func sameFrequencyMovesBandWithSampleRate() {
        func loudestBand(frequency: Float, sampleRate: Double) -> Int {
            let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: sampleRate)
            analyzer.smoothing = 0
            analyzer.injectSamples(
                Self.sine(frequency: frequency, amplitude: 0.5, sampleRate: sampleRate))
            analyzer.update()
            let energies = (0..<3).map { analyzer.band($0) }
            return energies.firstIndex(of: energies.max()!)!
        }

        #expect(loudestBand(frequency: 3_000, sampleRate: 44_100) == 1)
        #expect(loudestBand(frequency: 3_000, sampleRate: 8_000) == 2)  // 8000/4 = 2000 Hz
    }

    /// ビン比で決まるということは、fftSize を変えても帯域の割り当ては変わらない。
    @Test("fftSize を変えても帯域の割り当ては変わらない")
    func bandEdgesAreIndependentOfFFTSize() {
        func loudestBand(fftSize: Int) -> Int {
            let analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: 44_100)
            analyzer.smoothing = 0
            analyzer.injectSamples(
                Self.sine(frequency: 5_000, amplitude: 0.5, count: fftSize))
            analyzer.update()
            let energies = (0..<3).map { analyzer.band($0) }
            return energies.firstIndex(of: energies.max()!)!
        }

        #expect(loudestBand(fftSize: 512) == 1)
        #expect(loudestBand(fftSize: 1024) == 1)
        #expect(loudestBand(fftSize: 4096) == 1)
    }

    /// `spectrum` はフレームごとに最大ビンで正規化されるので、`band(_:)` は
    /// 絶対エネルギーではなく「そのフレームのどこに寄っているか」を返す。
    @Test("band はスペクトルの形を返すので入力を絞っても値が落ちない")
    func bandIsRelativeNotAbsolute() {
        func bands(amplitude: Float) -> [Float] {
            let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: 44_100)
            analyzer.smoothing = 0
            analyzer.injectSamples(Self.sine(frequency: 1_000, amplitude: amplitude))
            analyzer.update()
            return (0..<3).map { analyzer.band($0) }
        }

        // 振幅を 1/10 にしても値はほぼ同じ（volume なら 1/10 になる）
        let loud = bands(amplitude: 0.5)
        let quiet = bands(amplitude: 0.05)
        for (l, q) in zip(loud, quiet) {
            #expect(abs(l - q) < 1e-4)
        }
        #expect(loud[0] > 0)
    }

    // MARK: - ヘルパー

    static func sine(
        frequency: Float,
        amplitude: Float,
        sampleRate: Double = 44_100,
        count: Int = 1024
    ) -> [Float] {
        (0..<count).map { i in
            sin(Float(i) * 2 * Float.pi * frequency / Float(sampleRate)) * amplitude
        }
    }
}

// MARK: - サンプルレート未設定の警告（Issue #783）

/// `injectSamples` 経路で `sampleRate` を渡し忘れると `bandEnergy` が 0 になる。
/// 「その帯域にエネルギーが無い」ケースと区別が付かないので 1 度だけ警告する。
@Suite("Missing sample rate warning")
@MainActor
struct MissingSampleRateWarningTests {

    @Test("解決できなければ警告する")
    func warnsWhenRateCannotBeResolved() {
        #expect(AudioAnalyzer.shouldWarnAboutMissingSampleRate(
            resolvedRate: nil, alreadyWarned: false))
    }

    @Test("解決できていれば警告しない")
    func staysQuietWhenRateIsKnown() {
        #expect(!AudioAnalyzer.shouldWarnAboutMissingSampleRate(
            resolvedRate: 44_100, alreadyWarned: false))
    }

    @Test("同じ警告は 1 度だけ")
    func warnsOnlyOnce() {
        #expect(!AudioAnalyzer.shouldWarnAboutMissingSampleRate(
            resolvedRate: nil, alreadyWarned: true))
    }

    @Test("bandEnergy を何度呼んでもフラグは 1 度しか立たない")
    func flagIsSetOnce() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        analyzer.injectSamples([Float](repeating: 0.5, count: 1024))
        analyzer.update()

        #expect(!analyzer.didWarnAboutMissingSampleRate)
        _ = analyzer.bandEnergy(lowFreq: 300, highFreq: 600)
        #expect(analyzer.didWarnAboutMissingSampleRate)
        _ = analyzer.bandEnergy(lowFreq: 300, highFreq: 600)
        #expect(analyzer.didWarnAboutMissingSampleRate)
    }

    @Test("sampleRate が 0 以下でも解決できない扱いにする")
    func nonPositiveRateIsNotResolved() {
        let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: 0)
        #expect(analyzer.resolvedSampleRate() == nil)
        _ = analyzer.bandEnergy(lowFreq: 300, highFreq: 600)
        #expect(analyzer.didWarnAboutMissingSampleRate)
    }
}

// MARK: - AudioSampleTransferBuffer

@Suite("AudioSampleTransferBuffer")
struct AudioSampleTransferBufferTests {

    @Test("write and take round-trip")
    func roundTrip() {
        let buffer = AudioSampleTransferBuffer(capacity: 4)
        var out = [Float](repeating: -1, count: 4)

        let input: [Float] = [0.1, 0.2, 0.3, 0.4]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == input)
        // 2 回目は未読データなし
        #expect(!buffer.take(into: &out))
    }

    @Test("short write zero-fills the remainder")
    func shortWriteZeroFills() {
        let buffer = AudioSampleTransferBuffer(capacity: 4)
        var out = [Float](repeating: -1, count: 4)

        let input: [Float] = [0.5, 0.6]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == [0.5, 0.6, 0, 0])
    }

    @Test("oversized write is truncated to capacity")
    func oversizedWriteTruncated() {
        let buffer = AudioSampleTransferBuffer(capacity: 2)
        var out = [Float](repeating: -1, count: 2)

        let input: [Float] = [1, 2, 3, 4]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == [1, 2])
    }
}

// MARK: - NotificationObserverToken

/// `AudioAnalyzer` relies on releasing the token (rather than a `deinit` that
/// touches `@MainActor` state) to unregister its configuration-change observer.
/// If that ever regresses, a stopped analyzer keeps receiving notifications.
@Suite("NotificationObserverToken")
struct NotificationObserverTokenTests {

    @Test("releasing the token stops delivery")
    func releasingTokenUnregisters() {
        let name = Notification.Name("metaphor.test.\(UUID().uuidString)")
        let hits = Counter()
        let center = NotificationCenter()

        var token: NotificationObserverToken? = NotificationObserverToken(
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                hits.increment()
            },
            center: center
        )
        #expect(token != nil)

        center.post(name: name, object: nil)
        #expect(hits.value == 1)

        // 解放 = 解除。ここで removeObserver されないと次の post も届いてしまう。
        token = nil
        center.post(name: name, object: nil)
        #expect(hits.value == 1)
    }

    @Test("the token keeps delivery alive while it is retained")
    func retainedTokenKeepsDelivering() {
        let name = Notification.Name("metaphor.test.\(UUID().uuidString)")
        let hits = Counter()
        let center = NotificationCenter()

        let token = NotificationObserverToken(
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                hits.increment()
            },
            center: center
        )

        center.post(name: name, object: nil)
        center.post(name: name, object: nil)
        #expect(hits.value == 2)
        withExtendedLifetime(token) {}
    }
}

/// Counts synchronous notification deliveries. The observer block is `@Sendable`,
/// so the counter has to be safe to capture.
private final class Counter: Sendable {
    private let box = OSAllocatedUnfairLock(initialState: 0)
    func increment() { box.withLock { $0 += 1 } }
    var value: Int { box.withLock { $0 } }
}
