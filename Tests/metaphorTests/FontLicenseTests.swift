import CryptoKit
import Foundation
import Testing

/// 同梱フォントの帰属表記が実ファイルと一致していることを機械的に守る（Issue #653）。
///
/// `Examples/` と `Tests/` に checked in された `.ttf` は SIL Open Font License 1.1 で、
/// OFL 第 2 条が「再頒布する各コピーに著作権表示とライセンスを添えること」を求める。
/// ところがフォントを 1 本足す操作はビルドにもテストにも現れないため、
/// `THIRD_PARTY_LICENSES.md` への追記漏れは誰にも気付かれずに出荷されてしまう
/// （実際 11 ファイルが未記載のまま出荷されていた）。
///
/// そこで git の管理対象を走査し、見つかったフォントが帰属表記と突き合わせられる
/// ことを確認する（`LogConventionTests` / `GoldenImageTests` と同じ方針）。
@Suite("Bundled font licenses")
struct FontLicenseTests {

    /// リポジトリルート。`Tests/metaphorTests/` から 3 つ上。
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/metaphorTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // リポジトリルート

    private static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "woff", "woff2"]

    /// `git ls-files` の起動・実行に失敗したことを表す。
    ///
    /// 走査できなかったときに「フォント 0 件 = 全部記載済み」と読めてしまうのが最悪なので、
    /// 黙って空配列を返さずテストを失敗させる。
    private struct GitListingFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// リポジトリに checked in された全フォントを、ルートからの相対パスで返す。
    ///
    /// ワーキングツリーを `FileManager.enumerator` で舐めるのではなく `git ls-files` を使う。
    /// テスト名どおり「checked in された」ものだけを見たいからで、こうしておけば
    /// gitignore 済みのビルド生成物（`website/dist/` の `.woff2` など）が
    /// 将来どこに増えても除外リストを育て続けずに済む（Issue #957）。
    private static func checkedInFonts() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // `-z` は NUL 区切り。`Examples/Topics/Advanced Data/` のように空白を含むパスがある。
        process.arguments = ["git", "ls-files", "-z"]
        process.currentDirectoryURL = repositoryRoot.standardizedFileURL

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw GitListingFailure(description: "git ls-files を起動できなかった: \(error)")
        }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitListingFailure(
                description: """
                    git ls-files が失敗した（終了コード \(process.terminationStatus)）: \(message)
                    このテストは git の管理対象を正本にするので、走査できないときは緑にしない。
                    """)
        }

        return
            String(decoding: stdout, as: UTF8.self)
            .split(separator: "\0")
            .map(String.init)
            .filter { fontExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
    }

    private static func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func read(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 帰属表記

    @Test("checked in された全フォントが THIRD_PARTY_LICENSES.md に載っている")
    func everyFontIsAttributed() throws {
        let notices = try Self.read("THIRD_PARTY_LICENSES.md")
        let fonts = try Self.checkedInFonts()
        // 走査そのものが壊れて 0 件になったら（= 常に緑）気付けないので下限を置く。
        #expect(fonts.count >= 11, "フォントの走査が効いていない: \(fonts)")

        let missing = fonts.filter { !notices.contains($0) }
        #expect(
            missing.isEmpty,
            """
            THIRD_PARTY_LICENSES.md の「Bundled fonts」節に未記載のフォント: \(missing)
            フォントを足したら帰属（name テーブルの nameID 0 / 8 / 9 / 13）と SHA-256 を追記する。
            """)
    }

    @Test("記載された SHA-256 が実ファイルと一致する")
    func recordedHashesMatch() throws {
        let notices = try Self.read("THIRD_PARTY_LICENSES.md")
        var stale: [String] = []
        for relative in try Self.checkedInFonts() {
            let digest = try Self.sha256(of: Self.repositoryRoot.appendingPathComponent(relative))
            if !notices.contains(digest) {
                stale.append("\(relative) → \(digest)")
            }
        }
        #expect(
            stale.isEmpty,
            "THIRD_PARTY_LICENSES.md の SHA-256 が実ファイルと合っていない: \(stale)")
    }

    // MARK: - ライセンス全文

    @Test("OFL.txt が SIL 正典の本文を持っている")
    func licenseTextIsPresent() throws {
        let license = try Self.read("OFL.txt")
        #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007"))
        #expect(license.contains("THE FONT SOFTWARE IS PROVIDED \"AS IS\""))
        // OFL 第 2 条が求める著作権表示（3 フォント分）が本文の前に載っていること。
        #expect(license.contains("Adobe Systems Incorporated"))
        #expect(license.contains("Google Inc."))
        #expect(license.contains("Sorkin Type Co"))
    }

    @Test("バンドルへ同梱する OFL.txt がルートと同一")
    func bundledLicenseCopiesMatchRoot() throws {
        let root = try Self.read("OFL.txt")
        // `resources: [.copy("Resources")]` を宣言し、実際に `.ttf` を読む 3 パッケージ。
        // ディレクトリ丸ごとコピーなので、ここに置けば `.ttf` と一緒にバンドルへ入る。
        let copies = [
            "Examples/Basics/Typography/Letters/Letters/Resources/OFL.txt",
            "Examples/Basics/Typography/TextRotation/TextRotation/Resources/OFL.txt",
            "Examples/Basics/Typography/Words/Words/Resources/OFL.txt",
        ]
        for copy in copies {
            #expect(try Self.read(copy) == root, "\(copy) がルートの OFL.txt と一致しない")
        }
    }

    @Test("バンドルに .ttf を積む example には OFL.txt が同居している")
    func bundledFontsShipWithLicense() throws {
        let bundledFonts = try Self.checkedInFonts().filter {
            $0.contains("/Resources/") && $0.hasSuffix(".ttf")
        }
        #expect(bundledFonts.count == 3, "バンドル同梱のフォントが 3 本から変わった: \(bundledFonts)")

        for font in bundledFonts {
            let license = Self.repositoryRoot
                .appendingPathComponent(font)
                .deletingLastPathComponent()
                .appendingPathComponent("OFL.txt")
            #expect(
                FileManager.default.fileExists(atPath: license.path),
                "\(font) と同じ Resources/ に OFL.txt が無い（OFL 第 2 条）")
        }
    }
}
