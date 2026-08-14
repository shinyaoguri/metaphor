import CoreText
import Foundation

// MARK: - MFont

/// ``SketchContext/loadFont(_:cache:)`` が読み込んだフォントファイルへのハンドル。
///
/// 実体は Core Text のオブジェクトではなく、**プロセスへ登録済みのフォントを指す名前**です。
/// `loadFont` がファイルを `CTFontManager` に登録するため、以降は PostScript 名だけで
/// フォントを解決できます。``Sketch/textFont(_:)-(MFont)`` へ渡すと、以降のテキスト描画・
/// 計測がそのフォントで行われます。
///
/// ```swift
/// let mono = try loadFont(path)
/// textFont(mono)
/// text("metaphor", 20, 100)
/// ```
///
/// 同じ書体をファミリー名で指定する ``Sketch/textFont(_:)-(String)`` も引き続き使えます
/// （システムにインストール済みのフォント向け）。
public struct MFont: Sendable, Hashable {

    /// フォントの PostScript 名。テキスト描画時のフォント解決に使われます。
    public let postScriptName: String

    /// フォントのファミリー名（例: `Space Mono`）。
    public let familyName: String

    /// 読み込み元のファイルパス。
    public let path: String

    init(postScriptName: String, familyName: String, path: String) {
        self.postScriptName = postScriptName
        self.familyName = familyName
        self.path = path
    }
}

// MARK: - FontRegistry

/// フォントファイルを現在のプロセスへ登録し、PostScript 名を解決します。
///
/// 登録は `CTFontManagerRegisterFontsForURL` の `.process` スコープで行うため、
/// システムのフォント設定を変更しません（プロセス終了で消えます）。
@MainActor
enum FontRegistry {

    /// 登録済みの PostScript 名 → 登録元パス。同名衝突の検出に使います。
    private static var registered: [String: String] = [:]

    /// フォントファイルを登録し、``MFont`` を返します。
    ///
    /// 同じファイルを複数回渡しても安全です（Core Text の「登録済み」エラーは成功として扱います）。
    ///
    /// - Parameter path: フォントファイル（`.ttf` / `.otf` / `.ttc` / `.otc` / `.dfont`）のパス。
    /// - Returns: 登録されたフォントを指す ``MFont``。
    /// - Throws: ``MetaphorError/font(_:)``。
    static func load(path: String) throws -> MFont {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetaphorError.font(.fileNotFound(path: path))
        }

        // 記述子は登録前でも読める。ここで名前が取れないファイルはフォントではない。
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor], !descriptors.isEmpty
        else {
            throw MetaphorError.font(.noFontsInFile(path: path))
        }
        if descriptors.count > 1 {
            // .ttc / .otc は複数書体を束ねている。metaphor は 1 ファイル = 1 フォントとして
            // 扱い、先頭だけを採用する（他を使いたい場合は個別のファイルを渡す）。
            metaphorWarning(
                "loadFont: '\(path)' contains \(descriptors.count) fonts; using the first one")
        }

        let descriptor = descriptors[0]
        guard let postScriptName = attribute(kCTFontNameAttribute, of: descriptor) else {
            throw MetaphorError.font(.noFontsInFile(path: path))
        }
        let familyName = attribute(kCTFontFamilyNameAttribute, of: descriptor) ?? postScriptName

        try register(url: url, path: path)

        if let previous = registered[postScriptName], previous != url.standardized.path {
            // 同じ PostScript 名の別ファイルを登録すると、どちらが引かれるかは Core Text
            // 任せになる。黙って別の書体で描かれるより気付けるようにする。
            metaphorWarning(
                "loadFont: PostScript name '\(postScriptName)' is already registered from "
                    + "'\(previous)'; text may render with either font")
        }
        registered[postScriptName] = url.standardized.path

        return MFont(postScriptName: postScriptName, familyName: familyName, path: path)
    }

    // MARK: - Private

    private static func register(url: URL, path: String) throws {
        var cfError: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError) {
            return
        }
        let error = cfError?.takeRetainedValue()
        // 同じファイルを 2 回読むのは（毎フレーム loadFont を呼ぶスケッチを含め）正常系。
        if let error, CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue {
            return
        }
        let detail = error.map { CFErrorCopyDescription($0) as String } ?? "unknown error"
        throw MetaphorError.font(.registrationFailed(path: path, detail: detail))
    }

    private static func attribute(_ key: CFString, of descriptor: CTFontDescriptor) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, key) as? String
    }
}
