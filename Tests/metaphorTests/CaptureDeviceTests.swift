import Metal
import Testing
@testable import MetaphorCore

// MARK: - CaptureDevice Tests

@Suite("CaptureDevice")
struct CaptureDeviceTests {

    private let devices = [
        CaptureDeviceInfo(id: "builtin-1", name: "FaceTime HD カメラ", kind: .builtIn),
        CaptureDeviceInfo(id: "usb-1", name: "Logitech BRIO", kind: .external),
        CaptureDeviceInfo(id: "iphone-1", name: "iPhone のカメラ", kind: .continuityCamera),
    ]

    @Test("名前の完全一致（大文字小文字無視）でデバイスを選択する")
    func matchExactName() {
        let matched = CaptureDevice.match(deviceName: "logitech brio", in: devices)
        #expect(matched?.id == "usb-1")
    }

    @Test("完全一致がなければ部分一致で選択する")
    func matchPartialName() {
        let matched = CaptureDevice.match(deviceName: "FaceTime", in: devices)
        #expect(matched?.id == "builtin-1")
    }

    @Test("部分一致より完全一致を優先する")
    func exactMatchWins() {
        // "BRIO" を名前に含むデバイスと、名前がちょうど "BRIO" のデバイスが並存する場合
        let ambiguous = devices + [CaptureDeviceInfo(id: "usb-2", name: "BRIO", kind: .external)]
        let matched = CaptureDevice.match(deviceName: "brio", in: ambiguous)
        #expect(matched?.id == "usb-2")
    }

    @Test("一致するデバイスがなければ nil を返す")
    func matchNotFound() {
        let matched = CaptureDevice.match(deviceName: "存在しないカメラ", in: devices)
        #expect(matched == nil)
    }

    @Test("空文字列のクエリは nil を返す")
    func matchEmptyQuery() {
        let matched = CaptureDevice.match(deviceName: "", in: devices)
        #expect(matched == nil)
    }

    @Test("空のデバイス一覧では nil を返す")
    func matchEmptyList() {
        let matched = CaptureDevice.match(deviceName: "FaceTime", in: [])
        #expect(matched == nil)
    }

    @Test("list() はカメラ非接続環境でもクラッシュしない")
    @MainActor
    func listSmoke() {
        // CI にはカメラがないため件数は検証しない（空配列でも成功）。
        // 列挙がクラッシュせず、重複 ID を返さないことだけ確認する。
        let listed = CaptureDevice.list()
        let ids = listed.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Format Selection

    /// FaceTime HD カメラを模した候補解像度
    private let formats: [(width: Int, height: Int)] = [
        (640, 480), (1280, 720), (1920, 1080), (640, 360), (1760, 1328),
    ]

    @Test("要求解像度と完全一致するフォーマットを選ぶ")
    func formatExactMatch() {
        let index = CaptureDevice.closestFormatIndex(toWidth: 1280, height: 720, in: formats)
        #expect(index == 1)
    }

    @Test("完全一致がなければ幅・高さの差が最小のフォーマットを選ぶ")
    func formatClosestMatch() {
        // 1000x600 → 1280x720 が距離 400 で最小（640x480 は 480、640x360 は 600）
        let index = CaptureDevice.closestFormatIndex(toWidth: 1000, height: 600, in: formats)
        #expect(index == 1)
    }

    @Test("要求が全候補より大きければ最大解像度を選ぶ")
    func formatOversizedRequest() {
        let index = CaptureDevice.closestFormatIndex(toWidth: 9999, height: 9999, in: formats)
        #expect(index == 4)  // 1760x1328
    }

    @Test("距離が同じなら解像度が大きい方を優先する")
    func formatTieBreakPrefersLarger() {
        // 800x600 からはどちらも距離 280
        let tied: [(width: Int, height: Int)] = [(640, 480), (960, 720)]
        let index = CaptureDevice.closestFormatIndex(toWidth: 800, height: 600, in: tied)
        #expect(index == 1)
    }

    @Test("距離も解像度も同じなら先に現れたものを選ぶ")
    func formatTieBreakStable() {
        // 同一解像度がピクセルフォーマット違いで並ぶ実機の formats を模す
        let duplicated: [(width: Int, height: Int)] = [(1280, 720), (1280, 720)]
        let index = CaptureDevice.closestFormatIndex(toWidth: 1280, height: 720, in: duplicated)
        #expect(index == 0)
    }

    @Test("空の候補一覧では nil を返す")
    func formatEmptyList() {
        let index = CaptureDevice.closestFormatIndex(toWidth: 1280, height: 720, in: [])
        #expect(index == nil)
    }
}

// MARK: - Unavailability

@Suite("CaptureDevice 利用不能パス", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CaptureDeviceUnavailabilityTests {

    @Test("存在しないデバイス名では isAvailable=false・実解像度は nil")
    func unavailableWhenDeviceNotFound() {
        let cam = CaptureDevice(
            device: MTLCreateSystemDefaultDevice()!,
            deviceName: "存在しないカメラ XYZ"
        )
        #expect(cam.isAvailable == false)
        #expect(cam.actualWidth == nil)
        #expect(cam.actualHeight == nil)
        #expect(cam.deviceInfo == nil)
    }

    @Test("セッションが無いデバイスでも start/stop/read がクラッシュしない")
    func startStopWithoutSession() {
        let cam = CaptureDevice(
            device: MTLCreateSystemDefaultDevice()!,
            deviceName: "存在しないカメラ XYZ"
        )
        cam.start()
        cam.read()
        cam.stop()
        #expect(cam.isAvailable == false)
        #expect(cam.texture == nil)
    }

    @Test("切断処理で isAvailable が false になり onDisconnect は一度だけ呼ばれる")
    func markUnavailableTransition() {
        let cam = CaptureDevice(device: MTLCreateSystemDefaultDevice()!)
        // カメラ非接続・権限拒否環境（CI 含む）ではセットアップに至らないため、
        // 遷移の前提となる isAvailable == true が作れた場合のみ検証する。
        guard cam.isAvailable else { return }
        var callCount = 0
        cam.onDisconnect = { callCount += 1 }

        cam.markUnavailable(reason: "test")
        #expect(cam.isAvailable == false)
        #expect(callCount == 1)

        // 切断とランタイムエラーが連続しても二重発火しない
        cam.markUnavailable(reason: "test again")
        #expect(callCount == 1)
    }
}
