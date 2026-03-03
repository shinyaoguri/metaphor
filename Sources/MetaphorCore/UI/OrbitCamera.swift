import simd
import Foundation

/// Control a 3D camera orbit interactively via mouse drag and scroll.
///
/// Manages camera position in spherical coordinates. Mouse drag rotates the camera
/// around the target, and scroll input adjusts the zoom distance.
///
/// ```swift
/// func draw() {
///     orbitControl()  // automatically maps mouse drag to camera rotation
///     box(100)
/// }
/// ```
@MainActor
public final class OrbitCamera {

    // MARK: - Camera Parameters

    /// The point the camera looks at.
    public var target: SIMD3<Float> = .zero

    /// The distance from the camera to the target.
    public var distance: Float = 500

    /// The horizontal angle in radians (rotation around the Y axis).
    public var azimuth: Float = 0

    /// The vertical angle in radians (rotation above/below the horizon).
    public var elevation: Float = 0.3

    // MARK: - Sensitivity

    /// The sensitivity of mouse drag rotation.
    public var sensitivity: Float = 0.005

    /// The sensitivity of scroll wheel zoom.
    public var zoomSensitivity: Float = 0.1

    // MARK: - Limits

    /// The minimum allowed distance from the target.
    public var minDistance: Float = 1.0

    /// The maximum allowed distance from the target.
    public var maxDistance: Float = 10000.0

    /// The minimum elevation angle in radians.
    public var minElevation: Float = -Float.pi / 2 + 0.01

    /// The maximum elevation angle in radians.
    public var maxElevation: Float = Float.pi / 2 - 0.01

    // MARK: - Damping

    /// The damping coefficient (0 = no damping, closer to 1 = stronger inertia).
    public var damping: Float = 0

    /// The current rotational velocity around the Y axis.
    private var velocityAzimuth: Float = 0
    /// The current rotational velocity around the horizontal axis.
    private var velocityElevation: Float = 0

    // MARK: - Computed Properties

    /// Compute the camera position by converting spherical coordinates to Cartesian.
    public var eye: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    /// Return the camera up vector.
    public var up: SIMD3<Float> {
        SIMD3(0, 1, 0)
    }

    /// Create a new OrbitCamera with default parameters.
    public init() {}

    /// Create a new OrbitCamera with custom initial settings.
    /// - Parameters:
    ///   - distance: The initial distance from the target.
    ///   - azimuth: The initial horizontal angle in radians (default: 0).
    ///   - elevation: The initial vertical angle in radians (default: 0.3).
    public init(distance: Float, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
    }

    // MARK: - Input Handling

    /// Apply mouse drag deltas to rotate the camera.
    /// - Parameters:
    ///   - dx: The horizontal drag amount in pixels.
    ///   - dy: The vertical drag amount in pixels.
    public func handleMouseDrag(dx: Float, dy: Float) {
        let dAzimuth = -dx * sensitivity
        let dElevation = dy * sensitivity

        if damping > 0 {
            velocityAzimuth += dAzimuth
            velocityElevation += dElevation
        } else {
            azimuth += dAzimuth
            elevation += dElevation
            elevation = max(minElevation, min(maxElevation, elevation))
        }
    }

    /// Apply scroll input to adjust the zoom distance.
    /// - Parameter delta: The scroll delta value.
    public func handleScroll(delta: Float) {
        distance -= delta * zoomSensitivity * distance * 0.01
        distance = max(minDistance, min(maxDistance, distance))
    }

    /// Apply damping to velocities and update angles (call every frame).
    public func update() {
        guard damping > 0 else { return }

        azimuth += velocityAzimuth
        elevation += velocityElevation
        elevation = max(minElevation, min(maxElevation, elevation))

        velocityAzimuth *= damping
        velocityElevation *= damping

        // Zero out negligible velocities
        if abs(velocityAzimuth) < 0.0001 { velocityAzimuth = 0 }
        if abs(velocityElevation) < 0.0001 { velocityElevation = 0 }
    }

    /// Reset the camera to the specified state.
    /// - Parameters:
    ///   - distance: The distance to reset to (default: 500).
    ///   - azimuth: The azimuth angle to reset to (default: 0).
    ///   - elevation: The elevation angle to reset to (default: 0.3).
    public func reset(distance: Float = 500, azimuth: Float = 0, elevation: Float = 0.3) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.velocityAzimuth = 0
        self.velocityElevation = 0
    }
}
