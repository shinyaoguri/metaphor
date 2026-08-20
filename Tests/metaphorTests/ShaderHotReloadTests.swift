import Foundation
import Metal
import Testing

@testable import MetaphorCore

/// シェーダファイルの自動ホットリロード（#648 / Epic #291 E3）のテスト。
///
/// 「保存したら絵が変わる」の価値は、**壊れたシェーダを保存しても画面が落ちない**ことと
/// セットでしか成立しない（書きかけの MSL は必ずコンパイルに失敗する）。ここでは
/// リロードの成功系だけでなく、失敗系で直前の動くシェーダが残ることを固定する。
@Suite("Shader/FileHotReload", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShaderFileHotReloadTests {

    // MARK: - フィクスチャ

    /// `in.color` をそのまま返す 2D フラグメント。
    private static let passthroughSource = """
    fragment float4 hotFragment(Canvas2DVertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// 上と同じ関数名で中身だけ違うソース（リロードで差し替わったことを見る）。
    private static let invertedSource = """
    fragment float4 hotFragment(Canvas2DVertexOut in [[stage_in]]) {
        return float4(1.0 - in.color.rgb, in.color.a);
    }
    """

    /// コンパイルに落ちるソース（書きかけの MSL の代役）。
    private static let brokenSource = """
    fragment float4 hotFragment(Canvas2DVertexOut in [[stage_in]]) {
        return this_symbol_does_not_exist;
    }
    """

    private func makeLibrary() throws -> ShaderLibrary {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try ShaderLibrary(device: device)
    }

    // MARK: - ShaderLibrary: 失敗しても直前のライブラリを保つ

    @Test("reload: コンパイルに失敗しても登録済みライブラリは残る")
    func reloadKeepsLastGoodLibraryOnFailure() throws {
        let library = try makeLibrary()
        let key = "user.shader2D.hotFragment"
        try library.register(
            source: Shader2DSource.complete(Self.passthroughSource), as: key)
        #expect(library.function(named: "hotFragment", from: key) != nil)

        #expect(throws: MetaphorError.self) {
            try library.reload(
                key: key, source: Shader2DSource.complete(Self.brokenSource))
        }

        // 失敗したリロードでライブラリごと消えると、以降の描画は関数を引けずに落ちる。
        #expect(library.hasLibrary(for: key))
        #expect(library.function(named: "hotFragment", from: key) != nil)
    }

    @Test("reload: 成功すると関数キャッシュが差し替わる")
    func reloadReplacesFunctionCacheOnSuccess() throws {
        let library = try makeLibrary()
        let key = "user.shader2D.hotFragment"
        try library.register(
            source: Shader2DSource.complete(Self.passthroughSource), as: key)
        let before = try #require(library.function(named: "hotFragment", from: key))

        try library.reload(key: key, source: Shader2DSource.complete(Self.invertedSource))
        let after = try #require(library.function(named: "hotFragment", from: key))

        // 同じ名前で引いても、キャッシュ済みの古い MTLFunction ではないこと。
        #expect(before !== after)
    }

    // MARK: - ShaderHotReloader: 保存 → 差し替え

    /// 一時ディレクトリに `.metal` を 1 枚置き、そのパスを返します。
    private func writeShaderFile(_ source: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-hotreload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("hot.metal")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        // 通常は SketchRunner が config / env から解決して設定する。
        context.shaderHotReloadEnabled = true
        return context
    }

    @Test("loadShader で読んだファイルは監視対象になり、保存で差し替わる")
    func loadShaderRegistersAndReloads() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        let before = shader.revision

        try Self.invertedSource.write(
            toFile: path, atomically: true, encoding: .utf8)
        let reloader = try #require(context.shaderHotReloader)
        #expect(reloader.reload(paths: [path]))

        // revision が進む = 以降の描画は新しいパイプラインキーで解決される（E2 の土台）。
        #expect(shader.revision == before + 1)
    }

    @Test("壊れた MSL を保存しても落ちず、直前のシェーダで描き続ける")
    func brokenSourceKeepsLastGoodShader() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        let before = shader.revision
        let reloader = try #require(context.shaderHotReloader)

        try Self.brokenSource.write(toFile: path, atomically: true, encoding: .utf8)
        // 例外は投げない（描画ループの中から呼ばれるため）。差し替えも起きない。
        #expect(reloader.reload(paths: [path]) == false)
        #expect(shader.revision == before)
        #expect(
            context.renderer.shaderLibrary.function(
                named: "hotFragment", from: shader.libraryKey) != nil)

        // 直して保存し直せばそのまま復帰する。
        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))
        #expect(shader.revision == before + 1)
    }

    @Test("noLoop 中のリロードは再描画を 1 回起こす")
    func reloadTriggersRedrawWhileStopped() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        // 台帳はシェーダを弱参照で持つ（捨てられたシェーダを永久にリロードしない）ので、
        // ここで束縛しておかないと登録ごと落ちる。
        let shader = try context.loadShader(path, fragment: "hotFragment")
        let reloader = try #require(context.shaderHotReloader)

        var redraws = 0
        context.onRedraw = { redraws += 1 }
        context.noLoop()

        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))
        // 止まっているとフレームが進まないので、リロード自体を再描画の合図にする。
        #expect(redraws == 1)
        #expect(shader.revision == 1)
    }

    @Test("3D マテリアルと postFX も同じ台帳に載る")
    func materialAndPostEffectAreRegistered() throws {
        let context = try makeContext()

        let materialSource = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        fragment float4 hotMaterialFragment(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return in.color;
        }
        """
        let materialPath = try writeShaderFile(materialSource)
        let material = try context.createMaterialFromFile(
            path: materialPath, fragmentFunction: "hotMaterialFragment")

        // 前文（`PPVertexOut` / `PostProcessParams`）は読み込み時もリロード時も
        // 自動で足される（#718）。書くのはフラグメント関数だけ。
        let postSource = """
        fragment float4 hotPostFragment(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]]
        ) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """
        let postPath = try writeShaderFile(postSource)
        let effect = try context.createPostEffectFromFile(
            name: "hot", path: postPath, fragmentFunction: "hotPostFragment")

        let reloader = try #require(context.shaderHotReloader)
        // 中身を変えずに読み直しても、ライブラリの差し替え自体は起きる。
        try materialSource.write(toFile: materialPath, atomically: true, encoding: .utf8)
        try postSource.write(toFile: postPath, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [materialPath, postPath]))

        // postFX は関数を自前で持たず、パイプライン構築時にライブラリから引き直される。
        #expect(
            context.renderer.shaderLibrary.function(
                named: effect.fragmentFunctionName, from: effect.libraryKey) != nil)
        #expect(material.fragmentFunctionName == "hotMaterialFragment")
    }

    @Test("捨てられたシェーダは台帳から落ちる")
    func droppedShaderIsPruned() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        // 保持しない = 直後に解放される。台帳は弱参照なので、以降のリロードは
        // 「対象なし」で空振りする（消えたシェーダを永久にコンパイルし続けない）。
        _ = try context.loadShader(path, fragment: "hotFragment")
        let reloader = try #require(context.shaderHotReloader)

        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]) == false)
    }

    @Test("ホットリロードが無効なら監視登録もされない")
    func disabledContextDoesNotRegister() throws {
        let context = try makeContext()
        context.shaderHotReloadEnabled = false
        let path = try writeShaderFile(Self.passthroughSource)
        _ = try context.loadShader(path, fragment: "hotFragment")

        #expect(context.shaderHotReloader == nil)
    }

    // MARK: - 世代の観測（#671）

    @Test("登録した時点で digest が立ち、generation は 0 のまま")
    func stampStartsAtRegistration() throws {
        let context = try makeContext()
        #expect(context.activeShaderHotReloader == nil)

        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        _ = shader  // 台帳は弱参照。束縛が切れると登録ごと落ちる。

        let reloader = try #require(context.activeShaderHotReloader)
        #expect(reloader.contentDigest != nil)
        #expect(reloader.generation == 0)
        #expect(reloader.lastError == nil)
    }

    @Test("着地したリロードで digest が変わり generation が進む")
    func landedReloadAdvancesStamp() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        _ = shader
        let reloader = try #require(context.activeShaderHotReloader)
        let before = try #require(reloader.contentDigest)

        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))

        #expect(reloader.contentDigest != before)
        #expect(reloader.generation == 1)
        #expect(reloader.lastError == nil)
    }

    @Test("コンパイルに失敗したリロードは刻印を動かさず lastError を残す")
    func failedReloadKeepsStampAndReportsError() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        _ = shader
        let reloader = try #require(context.activeShaderHotReloader)
        let before = try #require(reloader.contentDigest)

        try Self.brokenSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]) == false)

        // 描いているのは直前の動くシェーダなので、刻印も据え置き = 正しく「未反映」。
        #expect(reloader.contentDigest == before)
        #expect(reloader.generation == 0)
        // これが無いと consumer は「まだ来ない」と「壊れていて来ない」を区別できず、
        // タイムアウトまで待つことになる（#671）。
        let error = try #require(reloader.lastError)
        #expect(error.contains("hotFragment"))

        // 直して保存し直せばエラーは消え、刻印が進む。
        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))
        #expect(reloader.lastError == nil)
        #expect(reloader.generation == 1)
        #expect(reloader.contentDigest != before)
    }

    @Test("内容を元に戻すと digest も戻るが generation は進み続ける")
    func revertKeepsGenerationMonotonic() throws {
        let context = try makeContext()
        let path = try writeShaderFile(Self.passthroughSource)
        let shader = try context.loadShader(path, fragment: "hotFragment")
        _ = shader
        let reloader = try #require(context.activeShaderHotReloader)
        let original = try #require(reloader.contentDigest)

        try Self.invertedSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))
        try Self.passthroughSource.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(reloader.reload(paths: [path]))

        // digest だけを見ていると「元に戻す」編集の着地を取りこぼす。generation が拾う。
        #expect(reloader.contentDigest == original)
        #expect(reloader.generation == 2)
    }

    // MARK: - 有効化の解決

    @Test("環境変数が config より優先される")
    func hotReloadResolution() {
        let on = SketchConfig(shaderHotReload: true)
        let off = SketchConfig(shaderHotReload: false)

        #expect(SketchRunner.resolveShaderHotReload(config: on, env: [:]))
        #expect(SketchRunner.resolveShaderHotReload(config: off, env: [:]) == false)
        #expect(
            SketchRunner.resolveShaderHotReload(
                config: off, env: ["METAPHOR_SHADER_HOT_RELOAD": "1"]))
        #expect(
            SketchRunner.resolveShaderHotReload(
                config: on, env: ["METAPHOR_SHADER_HOT_RELOAD": "0"]) == false)
        // 想定外の値は config へフォールバック（起動しないより素直に動く方を選ぶ）。
        #expect(
            SketchRunner.resolveShaderHotReload(
                config: on, env: ["METAPHOR_SHADER_HOT_RELOAD": "yes"]))
    }
}

/// ``ShaderFileWatcher`` 単体のテスト（ファイルシステムイベント経由）。
///
/// リローダ側のテストは監視を挟まず同期的に叩いているので、「保存が実際に届くか」は
/// ここでしか見ていない。時間に依存するため待ちは寛容に取る。
@Suite("Shader/FileWatcher")
@MainActor
struct ShaderFileWatcherTests {

    /// 通知を溜める箱（クロージャから触るので参照型）。
    @MainActor
    private final class Inbox {
        var paths: [String] = []
    }

    private func makeTemporaryFile() throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("watched.metal")
        try "// initial\n".write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    /// `inbox` の通知が `count` 件に達するまで最大 15 秒待ちます。
    ///
    /// 待ちを長く取るのは、通っているときは即座に抜けるうえ、CI の並列実行下では
    /// ファイルシステムイベントの配送が数秒ずれることがあるため（ローカルの
    /// 全テスト同時実行で実測 9 秒台）。短い上限は偽陰性しか生まない。
    private func waitForNotifications(_ inbox: Inbox, count: Int) async -> Bool {
        for _ in 0..<300 {
            if inbox.paths.count >= count { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @Test("連続した保存が毎回通知される（atomically = 一時ファイル + rename 経由）")
    func notifiesOnRepeatedAtomicWrites() async throws {
        let path = try makeTemporaryFile()
        let inbox = Inbox()
        let watcher = ShaderFileWatcher(debounce: 0.05) { changed in
            inbox.paths.append(contentsOf: changed)
        }
        defer { watcher.stop() }
        watcher.watch(path: path)

        // エディタの保存と同じ「別ファイルへ書いて置き換える」経路。
        //
        // **2 回保存するのが肝**。ファイル自体の fd に監視を張っていても 1 回目は
        // 拾えてしまう（元 inode の delete/rename もイベントなので）。fd が
        // 外れた inode を指したまま死ぬのは 2 回目以降で、そこを見ないと
        // ディレクトリ監視である必然性を検証できない。
        for index in 1...2 {
            try await Task.sleep(nanoseconds: 150_000_000)
            try "// edit \(index)\n".write(toFile: path, atomically: true, encoding: .utf8)
            #expect(await waitForNotifications(inbox, count: index))
        }
        #expect(inbox.paths == [path, path])
    }

    @Test("その場で書き換える保存も通知される")
    func notifiesOnInPlaceWrite() async throws {
        let path = try makeTemporaryFile()
        let inbox = Inbox()
        let watcher = ShaderFileWatcher(debounce: 0.05) { changed in
            inbox.paths.append(contentsOf: changed)
        }
        defer { watcher.stop() }
        watcher.watch(path: path)

        // `>` のリダイレクトや一部のエディタはファイルを置き換えず中身だけ書き換える。
        // このときディレクトリのエントリは変わらないので、**ディレクトリ監視は無反応**。
        // ファイル側の監視が要る（実装中に実際に取りこぼした経路）。
        for index in 1...2 {
            try await Task.sleep(nanoseconds: 150_000_000)
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data("// in-place \(index)\n".utf8))
            try handle.close()
            #expect(await waitForNotifications(inbox, count: index))
        }
        #expect(inbox.paths == [path, path])
    }

    @Test("変更が無ければ通知しない")
    func staysQuietWithoutChanges() async throws {
        let path = try makeTemporaryFile()
        let inbox = Inbox()
        let watcher = ShaderFileWatcher(debounce: 0.05) { changed in
            inbox.paths.append(contentsOf: changed)
        }
        defer { watcher.stop() }
        watcher.watch(path: path)

        // 同じディレクトリの別ファイルを触ってもイベントは起きるが、
        // 登録パスの指紋は変わらないので通知はされない。
        let sibling = (path as NSString).deletingLastPathComponent + "/other.txt"
        try "noise".write(toFile: sibling, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(inbox.paths.isEmpty)
    }
}
