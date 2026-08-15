import Foundation
import Testing

@testable import MetaphorCore

/// カメラ権限が `.notDetermined` のまま無言で死ぬのを止める（Issue #685）。
///
/// macOS は `Info.plist` に `NSCameraUsageDescription` を持つバンドル済みアプリにしか
/// 許可ダイアログを出さない。`swift run` で作る素の実行ファイルでは `.notDetermined` の
/// まま**フレームが 1 枚も来ないのに `isAvailable` は true**、警告もエラーも無し、という
/// 状態になっていた（リファレンス作品 #414 の実測: 15 秒待ってサンプル 0）。
///
/// 警告を出すかどうかの判定は純関数に切り出してあるので、TCC の状態に依存せずに固定できる。
@Suite("Capture permission watchdog")
@MainActor
struct CapturePermissionTests {

    private let delay = CaptureDevice.pendingPermissionWarningDelay

    @Test("notDetermined のままフレーム 0 で猶予を過ぎたら警告する")
    func warnsWhenPermissionNeverResolves() {
        #expect(CaptureDevice.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredFrame: false,
            elapsed: delay, alreadyWarned: false
        ))
    }

    @Test("猶予の前には警告しない（.app なら この間にダイアログが出て解決する）")
    func staysQuietBeforeTheGracePeriod() {
        #expect(!CaptureDevice.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredFrame: false,
            elapsed: delay - 0.1, alreadyWarned: false
        ))
    }

    @Test("フレームが来ていれば警告しない")
    func staysQuietOnceFramesArrive() {
        #expect(!CaptureDevice.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredFrame: true,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("start() していなければ警告しない（フレームが来ないのは当然）")
    func staysQuietWhenNotRunning() {
        #expect(!CaptureDevice.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: false, hasDeliveredFrame: false,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("denied / restricted はセットアップ時に別の警告が出るのでここでは出さない",
          arguments: [CaptureAuthorizationStatus.denied, .restricted, .authorized])
    func staysQuietForResolvedStatuses(status: CaptureAuthorizationStatus) {
        #expect(!CaptureDevice.shouldWarnAboutPendingPermission(
            status: status, isRunning: true, hasDeliveredFrame: false,
            elapsed: delay * 10, alreadyWarned: false
        ))
    }

    @Test("同じ警告は 1 度だけ（毎フレーム出さない）")
    func warnsOnlyOnce() {
        #expect(!CaptureDevice.shouldWarnAboutPendingPermission(
            status: .notDetermined, isRunning: true, hasDeliveredFrame: false,
            elapsed: delay * 10, alreadyWarned: true
        ))
    }
}
