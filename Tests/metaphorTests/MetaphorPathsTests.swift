import Foundation
import Testing

@testable import MetaphorCore

/// `.metaphor/` の基準ディレクトリ解決（Issue #688・CONTRACT.md 契約点 2）。
///
/// Probe（契約点 4）・Parameter Store（契約点 7）・State（契約点 8）は cwd 相対で
/// 解決されていた。`.app` を LaunchServices から起動すると **cwd が `/`** になるため、
/// 常設運用に近い形では「リクエストを置いても応答が来ない」「パラメータが永続化されない」
/// という壊れ方をする。`METAPHOR_STATE_DIR` で基準を与えられるようにした。
///
/// **未設定なら従来どおり cwd 相対**であることが後方互換の要なので、そこを固定する。
@Suite("METAPHOR_STATE_DIR")
@MainActor
struct MetaphorPathsTests {

    private let cwd = "/Users/someone/sketches/strata"

    // MARK: - 基準ディレクトリ

    @Test("未設定なら cwd が基準（従来どおり）")
    func defaultsToCurrentDirectory() {
        #expect(
            MetaphorPaths.resolveBaseDirectory(environment: [:], currentDirectory: cwd) == cwd)
    }

    @Test("空文字・空白だけの指定は無視する")
    func ignoresEmptyValues() {
        for value in ["", "   "] {
            #expect(MetaphorPaths.resolveBaseDirectory(
                environment: ["METAPHOR_STATE_DIR": value], currentDirectory: cwd) == cwd)
        }
    }

    @Test("絶対パスの指定はそのまま基準になる")
    func absolutePathWins() {
        #expect(MetaphorPaths.resolveBaseDirectory(
            environment: ["METAPHOR_STATE_DIR": "/tmp/state-here"],
            currentDirectory: cwd) == "/tmp/state-here")
    }

    @Test("末尾スラッシュや冗長な要素は正規化される")
    func normalizesPaths() {
        #expect(MetaphorPaths.resolveBaseDirectory(
            environment: ["METAPHOR_STATE_DIR": "/tmp/a/../state-here/"],
            currentDirectory: cwd) == "/tmp/state-here")
    }

    @Test("相対指定は cwd 基準で絶対化する")
    func relativeResolvesAgainstCurrentDirectory() {
        #expect(MetaphorPaths.resolveBaseDirectory(
            environment: ["METAPHOR_STATE_DIR": "state"],
            currentDirectory: cwd) == "\(cwd)/state")
    }

    @Test("~ は展開される")
    func expandsTilde() {
        let base = MetaphorPaths.resolveBaseDirectory(
            environment: ["METAPHOR_STATE_DIR": "~/metaphor-state"], currentDirectory: cwd)
        #expect(base.hasPrefix("/"))
        #expect(base.hasSuffix("/metaphor-state"))
        #expect(!base.contains("~"))
    }

    // MARK: - 個々のパス解決

    @Test("相対パスは基準から解決される")
    func resolvesRelativePaths() {
        #expect(
            MetaphorPaths.resolve(".metaphor/probe/current", base: "/tmp/base")
                == "/tmp/base/.metaphor/probe/current")
    }

    @Test("絶対パスの設定は基準の影響を受けない")
    func leavesAbsolutePathsAlone() {
        #expect(
            MetaphorPaths.resolve("/var/tmp/custom/probe", base: "/tmp/base")
                == "/var/tmp/custom/probe")
    }

    // MARK: - 3 つの契約が同じ基準を見る

    @Test("Probe / Parameter Store / State が同じ基準で解決される")
    func allThreeProtocolsShareTheBase() {
        // 既定の設定は init で解決済みになる（未設定なので cwd 基準の絶対パス）。
        let probe = MetaphorProbeConfig()
        let params = ParameterStoreConfig()
        let state = SketchStateConfig()
        let base = MetaphorPaths.baseDirectory

        #expect(probe.outputDirectory == "\(base)/.metaphor/probe/current")
        #expect(probe.requestFilePath == "\(base)/.metaphor/probe/request.json")
        #expect(params.directory == "\(base)/.metaphor/params")
        #expect(params.setRequestFilePath == "\(base)/.metaphor/params/set-request.json")
        #expect(state.directory == "\(base)/.metaphor/state")
        #expect(state.saveRequestFilePath == "\(base)/.metaphor/state/save-request.json")
    }

    @Test("明示した絶対パスの設定はそのまま使われる")
    func explicitAbsoluteConfigIsUntouched() {
        let probe = MetaphorProbeConfig(
            outputDirectory: "/tmp/out", requestFilePath: "/tmp/req.json")
        #expect(probe.outputDirectory == "/tmp/out")
        #expect(probe.requestFilePath == "/tmp/req.json")
    }
}
