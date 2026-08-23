import Foundation

/// Atomically renames a temporary file onto its final path.
///
/// `rename(2)` replaces an existing destination **atomically** within the same volume
/// (a two-step `removeItem` → `moveItem` opens a brief window in which the output
/// file does not exist, which breaks the "atomic rename" contract).
///
/// The file contracts under `.metaphor/` (Probe / Parameter Store) make it the
/// producer's obligation that "a reader never observes a partial write", so every
/// write goes through this function (CONTRACT.md contract points 4 / 7).
///
/// - Parameters:
///   - tmp: The temporary file that has already been written.
///   - final: The final path to replace.
///   - label: The origin reported in failure logs (`"Probe"`, `"Params"`, and so on).
func metaphorAtomicReplace(tmp: URL, final: URL, label: String) {
    let result = tmp.withUnsafeFileSystemRepresentation { tmpPath -> Int32 in
        final.withUnsafeFileSystemRepresentation { finalPath -> Int32 in
            guard let tmpPath, let finalPath else { return -1 }
            return rename(tmpPath, finalPath)
        }
    }
    if result != 0 {
        metaphorAlert(
            "\(label): failed to rename \(tmp.lastPathComponent) -> "
                + "\(final.lastPathComponent) (errno \(errno))")
    }
}
