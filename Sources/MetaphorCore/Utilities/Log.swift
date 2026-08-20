// 診断ログ（`metaphorWarning` / `metaphorAlert` / `metaphorDiagnostic`）の実体は
// 依存ゼロの `MetaphorLog` ターゲットにあります（Issue #805）。
//
// Core 非依存の Tier 1 モジュール（MetaphorPhysics / MetaphorML / MetaphorVideo /
// MetaphorNetwork / MetaphorAudio）からも同じ口を使えるようにするため、Core より下へ
// 切り出しました。ここで再輸出しているので、`import MetaphorCore` / `import metaphor`
// の利用者から見える名前は従来どおりです。
//
// 3 つの使い分け（どれをどの条件で使うか）は `Sources/MetaphorLog/Log.swift` を参照。
@_exported import MetaphorLog
