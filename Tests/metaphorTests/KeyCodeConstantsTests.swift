import Foundation
import Testing
import metaphor

// このファイルはスケッチ側と同じ import の形（`import metaphor` だけ・`@testable` なし）を
// 意図的に使っています。アンブレラ経由で ``KeyCode`` が見えることまで含めた検査にするためです。
//
// `import Foundation` を **意図的に先頭へ置いています**（Issue #794）。
// Darwin の `sys/tty.h` は `RETURN` / `TAB` / `BACKSPACE` / `CONTROL` を #define しており、
// グローバル定数を裸で書くと `ambiguous use of 'RETURN'` になります。
// `KeyCode.*` 経由なら衝突しないことが、このファイルがコンパイルできること自体で保証されます。

@Suite("KeyCode namespace")
struct KeyCodeConstantsTests {

    // MARK: - Foundation 併用下でも書けること（コンパイルが検査本体）

    @Test("Darwin のマクロと同名の 4 つが KeyCode 経由なら曖昧にならない")
    func ambiguousFourAreWritableViaNamespace() {
        // 型注釈を一切付けずに書けることが要件。裸の RETURN / TAB / BACKSPACE / CONTROL は
        // この文脈ではコンパイルが通らない。
        #expect(KeyCode.return == 36)
        #expect(KeyCode.tab == 48)
        #expect(KeyCode.backspace == 51)
        #expect(KeyCode.control == 59)
    }

    @Test("keyCode との比較と同じ形（UInt16? との Optional 比較）で書ける")
    func comparableAgainstOptionalKeyCode() {
        let pressed: UInt16? = 49
        #expect(pressed == KeyCode.space)

        let none: UInt16? = nil
        #expect(none != KeyCode.space)
    }

    // MARK: - Processing 互換なグローバル定数と値が一致すること

    // グローバル定数は現在 `KeyCode` の値を参照しているので、この一致は実装上は自明に成り立つ。
    // 値をリテラルで二重に書き戻す変更（= 片方だけ直して食い違う典型的な事故）が入ったときの番人として置く。
    // 実値そのものの保証は `rawVirtualKeyCodeValues` が持つ。
    @Test("KeyCode の 16 個がグローバル定数と同じ値を指す")
    func namespaceMatchesGlobalConstants() {
        // 曖昧になる 4 つはここでも型注釈で受けてから比較する（裸では書けないため）。
        let globalReturn: UInt16 = RETURN
        let globalTab: UInt16 = TAB
        let globalBackspace: UInt16 = BACKSPACE
        let globalControl: UInt16 = CONTROL

        let pairs: [(String, UInt16, UInt16)] = [
            ("LEFT", LEFT, KeyCode.left),
            ("RIGHT", RIGHT, KeyCode.right),
            ("DOWN", DOWN, KeyCode.down),
            ("UP", UP, KeyCode.up),
            ("RETURN", globalReturn, KeyCode.return),
            ("ENTER", ENTER, KeyCode.enter),
            ("TAB", globalTab, KeyCode.tab),
            ("SPACE", SPACE, KeyCode.space),
            ("BACKSPACE", globalBackspace, KeyCode.backspace),
            ("DELETE", DELETE, KeyCode.delete),
            ("ESCAPE", ESCAPE, KeyCode.escape),
            ("SHIFT", SHIFT, KeyCode.shift),
            ("CONTROL", globalControl, KeyCode.control),
            ("OPTION", OPTION, KeyCode.option),
            ("ALT", ALT, KeyCode.alt),
            ("COMMAND", COMMAND, KeyCode.command),
        ]

        #expect(pairs.count == 16, "キーコード定数は 16 個。増減したら両方を更新する")
        for (name, global, namespaced) in pairs {
            #expect(global == namespaced, "\(name) の値が名前空間とグローバル定数で食い違っている")
        }
    }

    @Test("macOS の仮想キーコードの実値が動いていない")
    func rawVirtualKeyCodeValues() {
        // Processing 互換の見た目でも、値は macOS の仮想キーコードそのもの。
        // 取り違えるとスケッチが黙って別のキーに反応するので、実値で固定する。
        #expect(KeyCode.left == 123)
        #expect(KeyCode.right == 124)
        #expect(KeyCode.down == 125)
        #expect(KeyCode.up == 126)
        #expect(KeyCode.enter == 76)
        #expect(KeyCode.space == 49)
        #expect(KeyCode.escape == 53)
        #expect(KeyCode.shift == 56)
        #expect(KeyCode.option == 58)
        #expect(KeyCode.command == 55)
    }

    // MARK: - 取り違えやすい組み合わせ

    @Test("ALT は OPTION のエイリアスで同じ値")
    func altIsAliasOfOption() {
        #expect(KeyCode.alt == KeyCode.option)
        #expect(KeyCode.alt == 58)
    }

    @Test("backspace (手前を消す) と delete (後ろを消す) は別のキー")
    func backspaceAndDeleteAreDistinct() {
        #expect(KeyCode.backspace == 51)
        #expect(KeyCode.delete == 117)
        #expect(KeyCode.backspace != KeyCode.delete)
    }

    @Test("return (メイン) と enter (テンキー) は別のキー")
    func returnAndEnterAreDistinct() {
        #expect(KeyCode.return == 36)
        #expect(KeyCode.enter == 76)
        #expect(KeyCode.return != KeyCode.enter)
    }

    @Test("エイリアス以外に重複した値が無い")
    func noUnintendedDuplicates() {
        // alt == option は意図したエイリアスなので、alt を除いた 15 個で重複を見る。
        let codes: [UInt16] = [
            KeyCode.left, KeyCode.right, KeyCode.down, KeyCode.up,
            KeyCode.return, KeyCode.enter, KeyCode.tab, KeyCode.space,
            KeyCode.backspace, KeyCode.delete, KeyCode.escape,
            KeyCode.shift, KeyCode.control, KeyCode.option, KeyCode.command,
        ]
        #expect(Set(codes).count == codes.count, "エイリアスでない定数が同じキーコードを指している")
    }
}
