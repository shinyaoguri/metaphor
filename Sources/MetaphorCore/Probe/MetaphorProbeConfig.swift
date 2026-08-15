import Foundation

/// ``MetaphorProbePlugin`` の設定。
///
/// 出力先ディレクトリやリクエストファイルのパスをカスタマイズできます。
/// デフォルトはプロジェクトのカレントディレクトリ配下の `.metaphor/probe/`。
///
/// 相対パスは環境変数 `METAPHOR_STATE_DIR`（未設定なら cwd）を基準に解決されます
/// （`.app` 起動では cwd が `/` になるため。Issue #688・CONTRACT.md 契約点 2）。
public struct MetaphorProbeConfig: Sendable {
    /// PNG と JSON を書き出すディレクトリ。
    public var outputDirectory: String

    /// AI エージェントが書き込むリクエストファイルのパス。
    public var requestFilePath: String

    /// 出力画像のスケール（1.0 = フルサイズ）。
    public var defaultScale: Float

    /// ソース世代の刻印（provenance）。`frame.json` の `sourceStamp` に書き出される。
    /// `nil` の場合はプラグインが環境変数 `METAPHOR_SOURCE_STAMP` をフォールバックに使う。
    /// 編集ごとに変わる識別子（cli が子プロセス起動時に注入する想定）。
    public var sourceStamp: String?

    public init(
        outputDirectory: String = ".metaphor/probe/current",
        requestFilePath: String = ".metaphor/probe/request.json",
        defaultScale: Float = 1.0,
        sourceStamp: String? = nil
    ) {
        self.outputDirectory = MetaphorPaths.resolve(outputDirectory)
        self.requestFilePath = MetaphorPaths.resolve(requestFilePath)
        self.defaultScale = defaultScale
        self.sourceStamp = sourceStamp
    }
}
