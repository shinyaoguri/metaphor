import Metal
import Syphon
import Foundation

/// Publish Metal textures to other applications via a Syphon server.
///
/// ``SyphonOutput`` wraps a `SyphonMetalServer` and provides a simple
/// interface for sharing rendered frames with Syphon-compatible client
/// applications (e.g. MadMapper, VDMX, Resolume).
///
/// ```swift
/// let syphon = SyphonOutput(device: device, name: "MyApp")
/// syphon.publish(texture: outputTexture, commandBuffer: commandBuffer)
/// ```
public final class SyphonOutput {
    /// The underlying Syphon Metal server instance.
    private var server: SyphonMetalServer?

    /// The Metal device used for server creation.
    private let device: MTLDevice

    /// The name of the Syphon server as seen by client applications.
    public var serverName: String? {
        server?.name
    }

    /// Indicate whether the Syphon server is currently active.
    public var isActive: Bool {
        server != nil
    }

    /// Create a new Syphon output server.
    ///
    /// - Parameters:
    ///   - device: The Metal device used by the server.
    ///   - name: The server name visible to Syphon client applications.
    public init(device: MTLDevice, name: String) {
        self.device = device
        self.server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    /// Publish a texture frame to all connected Syphon clients.
    ///
    /// - Parameters:
    ///   - texture: The Metal texture to publish.
    ///   - commandBuffer: The command buffer associated with this frame.
    ///   - region: The sub-region of the texture to publish, or `nil` to publish the entire texture.
    ///   - flipped: Whether to flip the image along the Y axis.
    public func publish(
        texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        region: NSRect? = nil,
        flipped: Bool = false
    ) {
        guard let server = server else { return }

        let imageRegion = region ?? NSRect(
            x: 0,
            y: 0,
            width: texture.width,
            height: texture.height
        )

        server.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: imageRegion,
            flipped: flipped
        )
    }

    /// Rename the Syphon server by stopping the current one and creating a new one.
    ///
    /// - Parameter name: The new server name.
    public func rename(_ name: String) {
        server?.stop()
        server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    /// Stop and release the Syphon server.
    public func stop() {
        server?.stop()
        server = nil
    }

    deinit {
        stop()
    }
}
