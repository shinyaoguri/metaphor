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
}
