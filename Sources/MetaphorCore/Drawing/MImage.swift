import Metal
import MetalKit
import AppKit

/// `MTLTexture` をラップして画像を表現します。
@MainActor
public final class MImage {
    /// この画像の基盤となる Metal テクスチャ。
    public private(set) var texture: MTLTexture

    /// 画像の幅（ピクセル単位）。
    public private(set) var width: Float

    /// 画像の高さ（ピクセル単位）。
    public private(set) var height: Float

    /// ファイルパスからテクスチャを読み込んで画像を作成します。
    ///
    /// - Parameters:
    ///   - path: 画像への絶対ファイルパス。
    ///   - device: テクスチャ作成に使用する Metal デバイス。
    /// - Throws: 指定されたパスからテクスチャを読み込めない場合にエラーをスロー。
    public init(path: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let url = URL(fileURLWithPath: path)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(URL: url, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// アプリバンドルから名前付きリソースを読み込んで画像を作成します。
    ///
    /// - Parameters:
    ///   - name: バンドル内の画像リソース名。
    ///   - device: テクスチャ作成に使用する Metal デバイス。
    /// - Throws: 名前付きリソースが見つからないか読み込めない場合にエラーをスロー。
    public init(named name: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// `NSImage` から画像を作成します。
    ///
    /// - Parameters:
    ///   - nsImage: Metal テクスチャに変換する `NSImage`。
    ///   - device: テクスチャ作成に使用する Metal デバイス。
    /// - Throws: `NSImage` を `CGImage` に変換できない場合に ``MetaphorError/image(_:)`` をスロー。
    public init(nsImage: NSImage, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MetaphorError.image(.invalidImage)
        }
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(cgImage: cgImage, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// 既存の `MTLTexture` から画像を作成します。
    ///
    /// - Parameter texture: ラップする Metal テクスチャ。
    public init(texture: MTLTexture) {
        self.texture = texture
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    // MARK: - Pixel Access

    /// ``loadPixels()`` 呼び出し後に格納される生の RGBA ピクセルデータ。
    public var pixels: [UInt8] = []

    /// 最後の ``loadPixels()`` 呼び出し以降に GPU テクスチャが変更された可能性があるかどうか。
    /// true の場合、次の ``loadPixels()`` は GPU から読み取ります。それ以外の場合は
    /// 既存の CPU 配列を再利用します（割り当て、リードバック、変換を回避）。
    private var needsGPUReadback: Bool = true

    /// GPU テクスチャから CPU 上の ``pixels`` 配列にピクセルデータを読み込みます。
    ///
    /// プライベートストレージモードのテクスチャの場合、マネージドストレージの
    /// ステージングテクスチャを作成し、読み取り前にブリットコピーを実行します。
    /// 結果データは BGRA から RGBA の順序に変換されます。
    ///
    /// CPU 配列が既に設定済みで GPU テクスチャが変更されていない場合
    /// （前回呼び出し以降に ``replaceTexture(_:)`` や GPU フィルタがない場合）、
    /// このメソッドは即座に返ります — 割り当て、リードバック、変換のオーバーヘッドを回避します。
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        let count = bytesPerRow * h

        // テクスチャが変更されていない場合、既存の CPU データを再利用。
        if !needsGPUReadback && pixels.count == count {
            return
        }

        if pixels.count != count {
            pixels = [UInt8](repeating: 0, count: count)
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            // プライベートテクスチャ: 共有ステージングテクスチャにブリットしてリードバック
            let device = texture.device
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                pixels = [UInt8](repeating: 0, count: count)
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .shared
            desc.usage = .shaderRead
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                pixels = [UInt8](repeating: 0, count: count)
                return
            }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: staging, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            staging.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        } else {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }

        // BGRA から RGBA に変換
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }

        needsGPUReadback = false
    }

    /// CPU の ``pixels`` 配列を GPU テクスチャに書き戻します。
    ///
    /// アップロード前にピクセルデータは RGBA から BGRA に変換されます。
    /// 現在のテクスチャがプライベートストレージモードの場合、CPU から書き込めないため
    /// 新しいマネージドテクスチャが作成されて置き換えられます。
    public func updatePixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        let count = bytesPerRow * h
        guard pixels.count == count else { return }

        // unsafe ポインタを使用して境界チェックなしで RGBA を BGRA にインプレース変換
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .shared
            desc.usage = [.shaderRead]
            guard let newTexture = texture.device.makeTexture(descriptor: desc) else {
                // 失敗時にスワップを戻す
                pixels.withUnsafeMutableBufferPointer { buf in
                    let ptr = buf.baseAddress!
                    for i in stride(from: 0, to: count, by: 4) {
                        let tmp = ptr[i]
                        ptr[i] = ptr[i + 2]
                        ptr[i + 2] = tmp
                    }
                }
                return
            }
            newTexture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
            self.texture = newTexture
        } else {
            texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        }

        // pixels 配列がユーザー向けフォーマットを維持するよう RGBA に戻す
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }
    }

    /// 指定された座標のピクセルの色を返します。
    ///
    /// ``pixels`` 配列が設定されていることを確認するため、このメソッドの前に
    /// ``loadPixels()`` を呼び出してください。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。
    ///   - y: 垂直方向のピクセル座標。
    /// - Returns: 指定位置の ``Color``。範囲外またはピクセルが未読み込みの場合は黒。
    public func get(_ x: Int, _ y: Int) -> Color {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return .black }
        guard !pixels.isEmpty else { return .black }
        let i = (y * w + x) * 4
        return Color(
            r: Float(pixels[i]) / 255.0,
            g: Float(pixels[i + 1]) / 255.0,
            b: Float(pixels[i + 2]) / 255.0,
            a: Float(pixels[i + 3]) / 255.0
        )
    }

    /// 指定された座標のピクセルの色を設定します。
    ///
    /// 変更は ``pixels`` 配列に保存され、``updatePixels()`` が呼び出されるまで
    /// GPU に反映されません。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。
    ///   - y: 垂直方向のピクセル座標。
    ///   - color: 指定位置に書き込む ``Color``。
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return }
        let bytesPerRow = w * 4
        if pixels.isEmpty {
            pixels = [UInt8](repeating: 0, count: bytesPerRow * Int(height))
        }
        let i = (y * w + x) * 4
        pixels[i] = UInt8(max(0, min(255, color.r * 255)))
        pixels[i + 1] = UInt8(max(0, min(255, color.g * 255)))
        pixels[i + 2] = UInt8(max(0, min(255, color.b * 255)))
        pixels[i + 3] = UInt8(max(0, min(255, color.a * 255)))
    }

    /// バッキングテクスチャを新しいものに置き換えます（通常は GPU フィルタ適用後）。
    ///
    /// CPU データが同期されなくなるため、``pixels`` 配列をリセットします。
    ///
    /// - Parameter newTexture: 使用する新しい Metal テクスチャ。
    public func replaceTexture(_ newTexture: MTLTexture) {
        self.texture = newTexture
        self.width = Float(newTexture.width)
        self.height = Float(newTexture.height)
        self.pixels = []
        self.needsGPUReadback = true
    }

    /// ``loadPixels()``、処理、``updatePixels()`` を一括で実行して画像フィルタを適用します。
    ///
    /// - Parameter type: 適用するフィルタを指定する ``FilterType``。
    public func filter(_ type: FilterType) {
        ImageFilter.apply(type, to: self)
    }

    /// ピクセル操作に適した空の画像を作成します。
    ///
    /// 返される画像はシェーダー読み取りと書き込みの両方の用途を持つ
    /// マネージドストレージモードで、``pixels`` 配列はゼロで事前確保されています。
    ///
    /// - Parameters:
    ///   - width: 画像の幅（ピクセル単位）。
    ///   - height: 画像の高さ（ピクセル単位）。
    ///   - device: テクスチャ作成に使用する Metal デバイス。
    /// - Returns: 新しい ``MImage`` インスタンス。テクスチャを作成できない場合は `nil`。
    public static func createImage(_ width: Int, _ height: Int, device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let img = MImage(texture: texture)
        img.pixels = [UInt8](repeating: 0, count: width * height * 4)
        return img
    }
}

