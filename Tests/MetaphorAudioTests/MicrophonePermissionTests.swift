import Foundation
import Testing

@testable import MetaphorAudio

/// マイク権限が `.notDetermined` のまま無言で無音になるのを止める（Issue #685）。
///
/// カメラと同じ穴。macOS は `NSMicrophoneUsageDescription` を持つバンドル済みアプリに
/// しか許可ダイアログを出さないので、素の実行ファイルでは `.notDetermined` のまま
/// **タップにサンプルが 1 つも来ない**（無音のサンプルすら来ない）。
@Suite("Microphone permission watchdog")
@MainActor
struct MicrophonePermissionTests {

    private let delay = AudioAnalyzer.pendingPermissionWarningDelay

    @Test("notDetermined のままサンプル 0 で猶予を過ぎたら警告する")
    func warnsWhenPermissionNeverResolves() {
        #expect(AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredSamples: false,
            elapsed: delay, alreadyWarned: false
        ))
    }

    @Test("猶予の前には警告しない")
    func staysQuietBeforeTheGracePeriod() {
        #expect(!AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredSamples: false,
            elapsed: delay - 0.1, alreadyWarned: false
        ))
    }

    @Test("サンプルが来ていれば警告しない（無音でも受け取りは起きる）")
    func staysQuietOnceSamplesArrive() {
        #expect(!AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredSamples: true,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("start() していなければ警告しない")
    func staysQuietWhenNotRunning() {
        #expect(!AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: false, hasDeliveredSamples: false,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("解決済みの状態では警告しない",
          arguments: [MicrophoneAuthorizationStatus.denied, .restricted, .authorized])
    func staysQuietForResolvedStatuses(status: MicrophoneAuthorizationStatus) {
        #expect(!AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: status, isRunning: true, hasDeliveredSamples: false,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("同じ警告は 1 度だけ")
    func warnsOnlyOnce() {
        #expect(!AudioAnalyzer.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredSamples: false,
            elapsed: delay * 10, alreadyWarned: true
        ))
    }
}
