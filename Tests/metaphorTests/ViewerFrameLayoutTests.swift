import Testing
@testable import MetaphorCore

// viewer frame IPC の共有メモリレイアウト（CONTRACT.md 契約点 5 の補足「共有メモリのレイアウト」）を固定する。

@Suite("ViewerFrameLayout")
struct ViewerFrameLayoutTests {

    @Test("alignUp は倍数へ切り上げ、既に倍数ならそのまま")
    func alignUp() {
        #expect(ViewerFrameLayout.alignUp(0, to: 256) == 0)
        #expect(ViewerFrameLayout.alignUp(1, to: 256) == 256)
        #expect(ViewerFrameLayout.alignUp(256, to: 256) == 256)
        #expect(ViewerFrameLayout.alignUp(257, to: 256) == 512)
        #expect(ViewerFrameLayout.alignUp(7680, to: 256) == 7680)
    }

    @Test("1080p: bytesPerRow は width*4、slotBytes は page 境界、3 slot で 24,920,064 byte（spike の実測値）")
    func fullHD() {
        let layout = ViewerFrameLayout(width: 1920, height: 1080, linearAlignment: 256, pageSize: 16384)
        #expect(layout.bytesPerRow == 7680)
        #expect(layout.slotBytes == 8_306_688)
        #expect(layout.slots == 3)
        #expect(layout.totalBytes == 24_920_064)
        #expect(layout.offset(slot: 0) == 0)
        #expect(layout.offset(slot: 2) == 2 * 8_306_688)
    }

    @Test("幅が alignment の倍数でなければ行を pad する（64px × 4 = 256 はちょうど、65px は 512）")
    func rowPadding() {
        #expect(ViewerFrameLayout(width: 64, height: 1, linearAlignment: 256, pageSize: 4096).bytesPerRow == 256)
        #expect(ViewerFrameLayout(width: 65, height: 1, linearAlignment: 256, pageSize: 4096).bytesPerRow == 512)
        // slot は page の倍数（= makeBuffer(bytesNoCopy:) と makeTexture(offset:) の要件）
        let tiny = ViewerFrameLayout(width: 1, height: 1, linearAlignment: 256, pageSize: 4096)
        #expect(tiny.slotBytes == 4096)
        #expect(tiny.totalBytes % 4096 == 0)
    }

    @Test("slots を変えると全長だけが変わる")
    func customSlots() {
        let two = ViewerFrameLayout(width: 8, height: 8, linearAlignment: 64, pageSize: 4096, slots: 2)
        #expect(two.slots == 2)
        #expect(two.totalBytes == 2 * two.slotBytes)
    }
}
