/// 非 `Sendable` な値を `@Sendable` クロージャや `async` 境界へ持ち込むための箱。
///
/// 使いどころは限定的で、次の 2 条件を**両方**満たすときだけ使う（Issue #328）:
///
/// 1. 渡す値の扱いが設計上安全だと説明できる（スレッドセーフな型、シリアルキューで
///    直列化済み、インデックス分割で書き込み範囲が重ならない、など）。
/// 2. `@preconcurrency import` や設計変更では抑止できない。特に、最小サポートの
///    Swift 5.10（Xcode 15.4）のコンパイラは **ローカル変数の `nonisolated(unsafe)` を
///    `@Sendable` クロージャのキャプチャ診断で考慮しない**（実測: Issue #328）ため、
///    そこは型レベルの `Sendable` 準拠でしか黙らせられない。
///
/// `@unchecked Sendable` の根拠: 箱自体は `let` 1 つの不変な値型で、可変状態を持たない。
/// 安全性は**利用側の呼び出し規約**に依存するので、使用箇所には必ず根拠コメントを書くこと。
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
