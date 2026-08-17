import Testing
@testable import MetaphorCore

/// `keyReleased()` / `mouseReleased()` の中で読む `key` / `keyCode` / `mouseButton` が
/// 「**いま離したもの**」ではなく「最後に**押された**もの」を指すことを固定する（#523）。
///
/// これは意図した挙動ではなく、Processing との既知の差異をそのまま書き留めたもの。
/// 単一キー / 単一ボタンの操作では両者が一致するため差異が見えず、**複数を同時に
/// 押したときだけ**ずれる。移行ガイドと doc コメントにその条件を書いたので、
/// 記述と実装がずれないようにここで押さえる。
///
/// 離したキー / ボタンを読む API の追加は #958。値そのものはコールバックの引数として
/// 境界まで届いていることも一緒に固定しておく（#958 の実装がそこから取るため）。
@Suite("Input release semantics (#523)")
@MainActor
struct InputReleaseSemanticsTests {

    // MARK: - キー

    @Test("単一キーなら keyReleased() の key / keyCode は離したキーと一致する")
    func singleKeyMatchesReleasedKey() {
        let input = InputManager()
        var codeInKeyUp: UInt16??
        var charInKeyUp: Character??
        input.onKeyUp = { _ in
            codeInKeyUp = input.lastKeyCode
            charInKeyUp = input.lastKey
        }

        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: false)
        input.handleKeyUp(keyCode: 0)

        #expect(codeInKeyUp == 0)
        #expect(charInKeyUp == "a")
    }

    @Test("複数キー同時押しでは keyReleased() の key / keyCode は最後に押したキーを指す")
    func multiKeyReportsLastPressedNotReleased() {
        let input = InputManager()
        var codeInKeyUp: UInt16??
        var charInKeyUp: Character??
        var upArgument: UInt16?
        input.onKeyUp = { code in
            upArgument = code
            codeInKeyUp = input.lastKeyCode
            charInKeyUp = input.lastKey
        }

        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: false)   // A
        input.handleKeyDown(keyCode: 11, characters: "b", isRepeat: false)  // B（A は押したまま）
        input.handleKeyUp(keyCode: 0)                                       // A を離す

        // Processing なら離した A を指すが、metaphor は最後に押した B のまま
        #expect(codeInKeyUp == 11, "keyCode が最後に押されたキー（B）でなくなっている")
        #expect(charInKeyUp == "b", "key が最後に押されたキー（B）でなくなっている")
        // 離されたキー自体はコールバックの引数として届いている（#958 の足がかり）
        #expect(upArgument == 0, "onKeyUp の引数が離されたキー（A）を運んでいない")
    }

    // MARK: - マウスボタン

    @Test("単一ボタンなら mouseReleased() の mouseButton は離したボタンと一致する")
    func singleButtonMatchesReleasedButton() {
        let input = InputManager()
        var observed: MouseButton??
        input.onMouseReleased = { _, _, _ in observed = input.mouseButton }

        input.handleMouseDown(x: 0, y: 0, button: .left)
        input.handleMouseUp(x: 0, y: 0, button: .left)

        #expect(observed == .left)
    }

    @Test("複数ボタン同時押しでは mouseReleased() の mouseButton は最後に押したボタンを指す")
    func multiButtonReportsLastPressedNotReleased() {
        let input = InputManager()
        var observed: MouseButton??
        var releasedArgument: MouseButton?
        input.onMouseReleased = { _, _, button in
            releasedArgument = button
            observed = input.mouseButton
        }

        input.handleMouseDown(x: 0, y: 0, button: .left)
        input.handleMouseDown(x: 0, y: 0, button: .right)   // 左は押したまま
        input.handleMouseUp(x: 0, y: 0, button: .left)      // 左を離す

        // Processing なら離した .left を指すが、metaphor は最後に押した .right のまま
        #expect(observed == .right, "mouseButton が最後に押されたボタン（.right）でなくなっている")
        // 離されたボタン自体はコールバックの引数として届いている（#958 の足がかり）
        #expect(releasedArgument == .left, "onMouseReleased の引数が離されたボタン（.left）を運んでいない")
    }
}
