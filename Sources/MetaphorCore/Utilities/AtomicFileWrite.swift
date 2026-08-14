import Foundation

/// 一時ファイルから本番パスへの原子的なリネーム。
///
/// `rename(2)` は同一ボリューム内で既存の宛先を **原子的に** 置き換える
/// （`removeItem` → `moveItem` の 2 段階だと、間に出力ファイルが存在しない
/// 瞬間窓ができて「原子的リネーム」の契約が破れる）。
///
/// `.metaphor/` 配下のファイル契約（Probe / Parameter Store）は「読み手が
/// 部分書き込みを見ない」ことを producer 側の義務としているため、書き出しは
/// 必ずこの関数を通します（CONTRACT.md 契約点 4 / 7）。
///
/// - Parameters:
///   - tmp: 書き込み済みの一時ファイル。
///   - final: 置き換え先の本番パス。
///   - label: 失敗ログに出す発生源（`"Probe"` / `"Params"` など）。
func metaphorAtomicReplace(tmp: URL, final: URL, label: String) {
    let result = tmp.withUnsafeFileSystemRepresentation { tmpPath -> Int32 in
        final.withUnsafeFileSystemRepresentation { finalPath -> Int32 in
            guard let tmpPath, let finalPath else { return -1 }
            return rename(tmpPath, finalPath)
        }
    }
    if result != 0 {
        print("[metaphor] \(label): failed to rename \(tmp.lastPathComponent) -> "
            + "\(final.lastPathComponent) (errno \(errno))")
    }
}
