import MetaphorCore
import MetaphorCoreImage

// MARK: - CoreImage フィルタブリッジ

@MainActor
private var _ciWrapperStorage: [ObjectIdentifier: CIFilterWrapper] = [:]

extension SketchContext {
    /// 遅延初期化される CoreImage フィルタラッパー（外部ストレージ）。
    var _ciFilterWrapper: CIFilterWrapper? {
        get { _ciWrapperStorage[ObjectIdentifier(self)] }
        set {
            if let newValue {
                _ciWrapperStorage[ObjectIdentifier(self)] = newValue
            } else {
                _ciWrapperStorage.removeValue(forKey: ObjectIdentifier(self))
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
