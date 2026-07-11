import Foundation
import MetaphorCore
import MetaphorCoreImage

// MARK: - CoreImage フィルタブリッジ

/// SketchContext → CIFilterWrapper マッピング用のストレージ。
///
/// キーは SketchContext への weak 参照（ポインタ同一性）。context がクリーンアップ
/// ハンドラを経ずに解放されても（SketchRunner 主経路は `performCleanup()` を呼ばない）
/// エントリは自動 purge され、CIContext とテクスチャプールを持つ wrapper をプロセス
/// 終了まで抱え込んだり、アドレス再利用で新しい context が他人の stale wrapper を
/// 拾ったりしない（ObjectIdentifier キーの辞書はその両方が起きる）。
/// `Sketch.swift` の `_sketchContextStorage` と同じ理由・同じパターン。
@MainActor
private let _ciWrapperStorage = NSMapTable<AnyObject, CIFilterWrapper>(
    keyOptions: [.weakMemory, .objectPointerPersonality],
    valueOptions: .strongMemory
)

extension SketchContext {
    /// 遅延初期化される CoreImage フィルタラッパー（外部ストレージ）。
    var _ciFilterWrapper: CIFilterWrapper? {
        get { _ciWrapperStorage.object(forKey: self) }
        set {
            if let newValue {
                _ciWrapperStorage.setObject(newValue, forKey: self)
            } else {
                _ciWrapperStorage.removeObject(forKey: self)
            }
        }
    }

    /// 共有の CIFilterWrapper を返し、必要に応じて作成します。
    func ensureCIFilterWrapper() -> CIFilterWrapper {
        if let wrapper = _ciFilterWrapper { return wrapper }
        let wrapper = CIFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
        _ciFilterWrapper = wrapper
        addCleanupHandler { [weak self] in
            self?._ciFilterWrapper = nil
        }
        return wrapper
    }
}

extension Sketch {
    /// CoreImage フィルタプリセットを画像に適用します。
    ///
    /// - Parameters:
    ///   - image: フィルタを適用する画像。
    ///   - preset: 適用するフィルタプリセット。
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        context.ensureCIFilterWrapper().apply(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(
                width: CGFloat(image.width), height: CGFloat(image.height)
            )),
            to: image
        )
    }

    /// 名前とカスタムパラメータを指定して CoreImage フィルタを画像に適用します。
    ///
    /// - Parameters:
    ///   - image: フィルタを適用する画像。
    ///   - name: CIFilter 名。
    ///   - parameters: フィルタパラメータ。
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        context.ensureCIFilterWrapper().apply(filterName: name, parameters: parameters, to: image)
    }

    /// CoreImage ジェネレーターフィルタを使用して画像を生成します。
    ///
    /// - Parameters:
    ///   - preset: ジェネレーターフィルタプリセット。
    ///   - width: 出力画像の幅（ピクセル単位）。
    ///   - height: 出力画像の高さ（ピクセル単位）。
    /// - Returns: 生成された画像。生成に失敗した場合は `nil`。
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        guard let tex = context.ensureCIFilterWrapper().generate(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(width: width, height: height)),
            width: width,
            height: height
        ) else { return nil }
        return MImage(texture: tex)
    }
}
