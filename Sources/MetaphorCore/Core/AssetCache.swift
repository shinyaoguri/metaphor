import Foundation

/// パスキーのアセットキャッシュ（LRU）。
///
/// `loadImage` / `loadModel` が返したインスタンスをパスをキーに保持し、同じパスの
/// 再読込で**同一インスタンス**を返します（Unity の `Resources.Load` と同じ意味論）。
/// `draw()` 内で `loadImage` を呼んでも毎フレームの再デコードが起きません。
///
/// 独立したコピーが必要な場合は `loadImage(path, cache: false)` でバイパスできます。
/// パスは絶対パスに正規化されるため、相対・絶対の表記違いは同じエントリになります。
@MainActor
public final class AssetCache {

    private struct Entry<Value> {
        let value: Value
        var tick: UInt64
    }

    private var images: [String: Entry<MImage>] = [:]
    private var meshes: [String: Entry<Mesh>] = [:]
    private var fonts: [String: Entry<MFont>] = [:]

    /// アクセス順を記録する単調カウンタ（LRU の evict 判定に使用）
    private var tick: UInt64 = 0

    /// 種別ごとの最大エントリ数。超過時は最も古くアクセスされたエントリを退去
    let capacity: Int

    /// アセットキャッシュを作成します。
    /// - Parameter capacity: 種別（画像/メッシュ）ごとの最大エントリ数。
    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    /// パスをキャッシュキーに正規化します（相対パス → 絶対パス、`..` 等を解決）。
    nonisolated static func normalizeKey(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    // MARK: - 画像

    /// パスに対応するキャッシュ済み画像を返します（なければ nil）。
    func image(forPath path: String) -> MImage? {
        access(&images, key: Self.normalizeKey(path))
    }

    /// 画像をキャッシュへ格納します。
    func store(_ image: MImage, forPath path: String) {
        insert(&images, key: Self.normalizeKey(path), value: image)
    }

    // MARK: - メッシュ

    private nonisolated static func meshKey(_ path: String, normalize: Bool) -> String {
        normalizeKey(path) + (normalize ? "|normalized" : "|raw")
    }

    /// パスと正規化フラグに対応するキャッシュ済みメッシュを返します（なければ nil）。
    func mesh(forPath path: String, normalize: Bool) -> Mesh? {
        access(&meshes, key: Self.meshKey(path, normalize: normalize))
    }

    /// メッシュをキャッシュへ格納します。
    func store(_ mesh: Mesh, forPath path: String, normalize: Bool) {
        insert(&meshes, key: Self.meshKey(path, normalize: normalize), value: mesh)
    }

    // MARK: - フォント

    /// パスに対応するキャッシュ済みフォントを返します（なければ nil）。
    func font(forPath path: String) -> MFont? {
        access(&fonts, key: Self.normalizeKey(path))
    }

    /// フォントをキャッシュへ格納します。
    func store(_ font: MFont, forPath path: String) {
        insert(&fonts, key: Self.normalizeKey(path), value: font)
    }

    // MARK: - 管理

    /// すべてのエントリを破棄します（``SketchContext/clearCaches()`` から呼ばれます）。
    ///
    /// フォントの登録自体（`CTFontManager` への `.process` スコープ登録）は取り消されません。
    /// 破棄されるのはパス → ``MFont`` の対応表だけで、既に `textFont` で選んだフォントは
    /// 引き続き描画に使えます。
    public func clear() {
        images.removeAll()
        meshes.removeAll()
        fonts.removeAll()
    }

    /// キャッシュ中の画像エントリ数。
    public var imageCount: Int { images.count }

    /// キャッシュ中のメッシュエントリ数。
    public var meshCount: Int { meshes.count }

    /// キャッシュ中のフォントエントリ数。
    public var fontCount: Int { fonts.count }

    // MARK: - LRU 実装

    private func access<Value>(_ storage: inout [String: Entry<Value>], key: String) -> Value? {
        guard var entry = storage[key] else { return nil }
        tick += 1
        entry.tick = tick
        storage[key] = entry
        return entry.value
    }

    private func insert<Value>(_ storage: inout [String: Entry<Value>], key: String, value: Value) {
        tick += 1
        storage[key] = Entry(value: value, tick: tick)
        // 容量超過時は最も古くアクセスされたエントリを退去
        // （capacity は小さいので線形スキャンで十分）
        if storage.count > capacity,
           let oldest = storage.min(by: { $0.value.tick < $1.value.tick })?.key
        {
            storage.removeValue(forKey: oldest)
        }
    }
}
