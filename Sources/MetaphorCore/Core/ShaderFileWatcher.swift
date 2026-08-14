import Foundation

/// MSL ソースファイルの変更を監視して、変化したパスをメインスレッドへ通知します（#648 / Epic #291 E3）。
///
/// ## なぜディレクトリとファイルの両方を見張るか
///
/// 保存の仕方はエディタによって 2 通りあり、**片方だけの監視ではどちらかを取りこぼします**。
///
/// - **一時ファイルへ書いて rename で置き換える**（Xcode / VS Code / vim の既定など）:
///   ファイル自体の fd はこの瞬間に元の inode ごと外れ、以降のイベントが届かなくなります。
///   ディレクトリ側のイベント（エントリの入れ替え）で拾い、fd を張り直します。
/// - **その場で書き換える**（`>` のリダイレクト・一部のエディタ）: ディレクトリのエントリは
///   変わらないのでディレクトリ側は無反応です。ファイル側の `.write` で拾います。
///
/// どちらの経路も、発火のたびに登録済みパスの `(mtime, size)` を突き合わせて変化を判定します。
///
/// 1 回の保存はしばしば複数イベント（write → rename → attrib）に割れるので、
/// ``debounce`` 秒だけまとめてから 1 回だけ通知します。
///
/// `@unchecked Sendable` の根拠: 可変状態（`sources` / `stamps` / `pending`）は
/// すべて private な直列キュー `queue` の上でのみ触り、外部へは渡しません。
/// 公開メソッドは入口で `queue` へホップします。
final class ShaderFileWatcher: @unchecked Sendable {
    /// 監視対象ファイルの指紋。どちらかが変われば「保存された」と見なします。
    private struct Stamp: Equatable {
        var modified: TimeInterval
        var size: Int
    }

    /// イベント処理と状態更新を行う直列キュー。
    private let queue = DispatchQueue(label: "org.metaphor.shader-hot-reload")

    /// 連続イベントをまとめる秒数。
    private let debounce: TimeInterval

    /// 変化したパスの通知先。`@MainActor` なので、監視キューからは main へホップして呼びます。
    private let onChange: @Sendable @MainActor ([String]) -> Void

    /// ディレクトリパス → 監視ソース。1 ディレクトリにつき 1 本。
    private var sources: [String: DispatchSourceFileSystemObject] = [:]

    /// ファイルパス → 監視ソース。その場書き換えを拾うために張ります。
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]

    /// 監視対象ファイルパス。
    private var watched: Set<String> = []

    /// 監視対象ファイルパス → 直近の指紋（読めなかったファイルは載りません）。
    private var stamps: [String: Stamp] = [:]

    /// デバウンス中の判定処理。次のイベントが来たら差し替えます。
    private var pending: DispatchWorkItem?

    /// - Parameters:
    ///   - debounce: 連続イベントをまとめる秒数（既定 0.12 秒）。
    ///   - onChange: 変化したファイルパスの通知先。メインスレッドで呼ばれます。
    init(debounce: TimeInterval = 0.12, onChange: @escaping @Sendable @MainActor ([String]) -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        // suspend 済みの DispatchSource は解放時にクラッシュするが、ここで扱うソースは
        // 常に resume 済み（start 時に resume し、止めるときは cancel する）。
        for source in sources.values { source.cancel() }
        for source in fileSources.values { source.cancel() }
    }

    // MARK: - 登録

    /// ファイルを監視対象に加えます。同じパスの二重登録は無視されます。
    /// - Parameter path: 監視する `.metal` ファイルのパス。
    func watch(path: String) {
        let target = (path as NSString).standardizingPath
        queue.async { [self] in
            guard watched.insert(target).inserted else { return }
            stamps[target] = Self.stamp(of: target)
            startWatchingDirectory(of: target)
            startWatchingFile(target)
        }
    }

    /// すべての監視を停止します。
    func stop() {
        queue.async { [self] in
            pending?.cancel()
            pending = nil
            for source in sources.values { source.cancel() }
            sources.removeAll()
            for source in fileSources.values { source.cancel() }
            fileSources.removeAll()
            watched.removeAll()
            stamps.removeAll()
        }
    }

    // MARK: - 内部

    /// 指定パスの親ディレクトリに監視を張ります（既にあれば何もしません）。
    private func startWatchingDirectory(of path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty, sources[directory] == nil else { return }

        let descriptor = open(directory, O_EVTONLY)
        guard descriptor >= 0 else {
            metaphorDiagnostic("shader hot reload: cannot watch directory \(directory)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            // ディレクトリ自体が消えた / 移動した場合は fd が指す先が古いので張り直す。
            if data.contains(.delete) || data.contains(.rename) {
                rearmDirectory(directory)
            }
            scheduleCheck()
        }
        source.setCancelHandler { close(descriptor) }
        sources[directory] = source
        source.resume()
    }

    /// ファイル自身に監視を張ります（その場書き換えの検出。既にあれば何もしません）。
    private func startWatchingFile(_ path: String) {
        guard fileSources[path] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            // まだ存在しないファイルはディレクトリ側のイベントで拾い、そこで張り直す。
            metaphorDiagnostic("shader hot reload: cannot watch file \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            // 置き換え保存だと fd は消えた inode を指したままになるので張り直す。
            if data.contains(.delete) || data.contains(.rename) {
                rearmFile(path)
            }
            scheduleCheck()
        }
        source.setCancelHandler { close(descriptor) }
        fileSources[path] = source
        source.resume()
    }

    /// ファイル監視を捨てて張り直します（置き換え保存後の追従）。
    private func rearmFile(_ path: String) {
        fileSources.removeValue(forKey: path)?.cancel()
        // 置き換えの途中は一瞬開けないことがあるので、落ち着いてから開き直す。
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            guard watched.contains(path) else { return }
            startWatchingFile(path)
        }
    }

    /// ディレクトリ監視を捨てて張り直します（rename / delete 後の追従）。
    private func rearmDirectory(_ directory: String) {
        sources.removeValue(forKey: directory)?.cancel()
        // 置き換え途中で一瞬消えることがあるので、デバウンス後に開き直す。
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            guard let path = watched.first(where: {
                ($0 as NSString).deletingLastPathComponent == directory
            }) else { return }
            startWatchingDirectory(of: path)
        }
    }

    /// デバウンスして変化判定を予約します。
    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkForChanges() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// 登録済みパスの指紋を突き合わせ、変化があればメインスレッドへ通知します。
    private func checkForChanges() {
        pending = nil
        var changed: [String] = []
        for path in watched {
            // ファイルが一時的に消えている（rename 途中）ときは指紋を更新しない。
            // 次のイベントで置き換え後のファイルを拾う。
            guard let current = Self.stamp(of: path) else { continue }
            if stamps[path] != current {
                stamps[path] = current
                changed.append(path)
                // 置き換え保存で fd が外れたまま、または監視開始時に存在しなかった
                // ファイルは、ここで初めて開ける。
                startWatchingFile(path)
            }
        }
        guard !changed.isEmpty else { return }
        let paths = changed.sorted()
        let notify = onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { notify(paths) } }
    }

    /// ファイルの指紋を採ります。読めない場合は `nil`。
    private static func stamp(of path: String) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return Stamp(modified: modified.timeIntervalSince1970, size: size)
    }
}
