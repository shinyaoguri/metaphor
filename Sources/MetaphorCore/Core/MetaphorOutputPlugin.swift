import Metal

// MARK: - MetaphorOutputPlugin プロトコル

/// 最終フレームを外部へ出力（publish / stream / record）するプラグインのマーカープロトコル。
///
/// `MetaphorOutputPlugin` に準拠したプラグインの ``MetaphorPlugin/post(texture:commandBuffer:)``
/// は、通常プラグインすべての `post()` が呼ばれた**後**に「出力フェーズ」として実行されます。
/// これにより Syphon / NDI などの出力先は、常に他プラグインの処理を反映した最終テクスチャを
/// 最後に受け取れます。
///
/// `post()` 以外のライフサイクルフック（`pre` / `onStart` / `onStop` / `onResize` /
/// `mouseEvent` / `keyEvent` / `onDetach`）は通常プラグインと同一に扱われます
/// （同じプラグイン配列に格納されるため）。出力プラグインに必要なのは「post を最後に」
/// だけなので、追加の要件はありません。
@MainActor
public protocol MetaphorOutputPlugin: MetaphorPlugin {}
