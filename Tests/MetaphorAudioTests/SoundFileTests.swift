import Testing
import Foundation
import AVFoundation
@testable import MetaphorAudio

// MARK: - SoundFile

@Suite("SoundFile playback")
@MainActor
struct SoundFilePlaybackTests {

    /// テスト用の短い無音 WAV ファイルを生成します。
    private func makeTestWAV(seconds: Double = 0.1) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-soundfile-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test("duration reflects the file length")
    func durationMatches() throws {
        let url = try makeTestWAV(seconds: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        #expect(abs(sound.duration - 0.1) < 0.01)
    }

    @Test("seeking past the end does not crash and acts as a stop")
    func seekPastEndDoesNotCrash() throws {
        let url = try makeTestWAV(seconds: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        // 以前は AVAudioFrameCount(負の Int64) の初期化でトラップしていた
        sound.position = sound.duration + 5.0
        #expect(sound.isPlaying == false)
        #expect(sound.position == 0)
    }

    @Test("seeking to a negative position clamps to the start")
    func seekNegativeClamps() throws {
        let url = try makeTestWAV(seconds: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.position = -3.0
        #expect(sound.isPlaying == false)
        // 再生前（lastRenderTime なし）はシーク基準値が返る
        #expect(sound.position == 0)
    }

    @Test("seeking within the file reports the sought position before playback")
    func seekReportsBasePosition() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.position = 0.25
        // 以前はスケジュールし直しで sampleTime が 0 に戻り、~0 を返していた
        #expect(abs(sound.position - 0.25) < 0.01)
    }

    @Test("stop resets the reported position")
    func stopResetsPosition() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.position = 0.25
        sound.stop()
        #expect(sound.position == 0)
    }

    @Test("stale completion after stop does not restart looping playback")
    func staleCompletionAfterStop() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.isLooping = true
        // シークでセグメントをスケジュールし、その completion が
        // stop() の後に遅れて届くケースを模擬する
        sound.position = 0.25
        let staleGeneration = sound.scheduleGeneration
        sound.stop()
        // 修正前はここでループ再スケジュール + play() が走り、
        // isPlaying == false のまま音が鳴り続けていた
        sound.handlePlaybackCompletion(generation: staleGeneration)
        #expect(sound.isPlaying == false)
        #expect(sound.position == 0)
    }

    @Test("stale completion does not rewind a seek during looping")
    func staleCompletionDoesNotRewindSeek() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.isLooping = true
        let generationBeforeSeek = sound.scheduleGeneration
        sound.position = 0.25
        // シーク前のスケジュールの completion が遅れて届いても、
        // シーク位置が先頭へ巻き戻されない
        sound.handlePlaybackCompletion(generation: generationBeforeSeek)
        #expect(abs(sound.position - 0.25) < 0.01)
    }

    @Test("current completion still ends non-looping playback")
    func currentCompletionEndsPlayback() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.isLooping = false
        sound.position = 0.25
        // 現世代の completion（正常再生完了）は従来どおり処理される
        sound.handlePlaybackCompletion(generation: sound.scheduleGeneration)
        #expect(sound.isPlaying == false)
    }

    @Test("position is cached while paused")
    func positionCachedWhilePaused() throws {
        let url = try makeTestWAV(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let sound = try SoundFile(path: url.path)
        sound.position = 0.25
        sound.pause()
        // 修正前は pause 中に playerTime(forNodeTime:) が nil になり
        // 巻き戻って見えることがあった
        #expect(abs(sound.position - 0.25) < 0.01)
        sound.stop()
        #expect(sound.position == 0)
    }
}
