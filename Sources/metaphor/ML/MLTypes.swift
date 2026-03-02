import CoreML
import simd

/// Represent an image classification result.
public struct MLClassification: Sendable {
    /// The classification label (e.g., "cat", "dog").
    public let label: String
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float

    public init(label: String, confidence: Float) {
        self.label = label
        self.confidence = confidence
    }
}

/// Represent an object detection result.
public struct MLDetection: Sendable {
    /// The detected object label.
    public let label: String
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float
    /// The bounding box x position in pixel coordinates (top-left origin).
    public let x: Float
    /// The bounding box y position in pixel coordinates (top-left origin).
    public let y: Float
    /// The bounding box width in pixels.
    public let w: Float
    /// The bounding box height in pixels.
    public let h: Float

    public init(label: String, confidence: Float, x: Float, y: Float, w: Float, h: Float) {
        self.label = label
        self.confidence = confidence
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Represent a single pose landmark (one joint).
public struct MLLandmark: Sendable {
    /// The joint name.
    public let name: String
    /// The x position in pixel coordinates.
    public let x: Float
    /// The y position in pixel coordinates.
    public let y: Float
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float

    public init(name: String, x: Float, y: Float, confidence: Float) {
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// Represent a body, hand, or face pose estimation result.
public struct MLPose: Sendable {
    /// The list of all detected landmarks.
    public let landmarks: [MLLandmark]
    /// The overall confidence score.
    public let confidence: Float

    public init(landmarks: [MLLandmark], confidence: Float) {
        self.landmarks = landmarks
        self.confidence = confidence
    }

    /// Find a landmark by name.
    /// - Parameter name: The landmark name to search for.
    /// - Returns: The matching landmark, or nil if not found.
    public func landmark(_ name: String) -> MLLandmark? {
        landmarks.first { $0.name == name }
    }
}

/// Represent a segmentation mask.
public struct MLSegmentMask: Sendable {
    /// The mask width in pixels.
    public let width: Int
    /// The mask height in pixels.
    public let height: Int
    /// The raw mask data (0.0 to 1.0, row-major order).
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }
}

/// Represent a face detection result.
public struct MLFace: Sendable {
    /// The bounding box x position in pixel coordinates.
    public let x: Float
    /// The bounding box y position in pixel coordinates.
    public let y: Float
    /// The bounding box width in pixels.
    public let w: Float
    /// The bounding box height in pixels.
    public let h: Float
    /// The facial landmarks (eyes, nose, mouth, etc.).
    public let landmarks: [MLLandmark]

    public init(x: Float, y: Float, w: Float, h: Float, landmarks: [MLLandmark]) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.landmarks = landmarks
    }
}

/// Represent a text recognition result.
public struct MLText: Sendable {
    /// The recognized text string.
    public let text: String
    /// The confidence score.
    public let confidence: Float
    /// The bounding box x position in pixel coordinates.
    public let x: Float
    /// The bounding box y position in pixel coordinates.
    public let y: Float
    /// The bounding box width in pixels.
    public let w: Float
    /// The bounding box height in pixels.
    public let h: Float

    public init(text: String, confidence: Float, x: Float, y: Float, w: Float, h: Float) {
        self.text = text
        self.confidence = confidence
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Represent a saliency heatmap.
public struct MLSaliency: Sendable {
    /// The heatmap width in pixels.
    public let width: Int
    /// The heatmap height in pixels.
    public let height: Int
    /// The heatmap data (0.0 to 1.0, row-major order).
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }
}

/// Represent a barcode or QR code detection result.
public struct MLBarcode: Sendable {
    /// The decoded payload string.
    public let payload: String
    /// The symbology type (e.g., "QR", "EAN-13").
    public let symbology: String
    /// The bounding box x position in pixel coordinates.
    public let x: Float
    /// The bounding box y position in pixel coordinates.
    public let y: Float
    /// The bounding box width in pixels.
    public let w: Float
    /// The bounding box height in pixels.
    public let h: Float

    public init(payload: String, symbology: String, x: Float, y: Float, w: Float, h: Float) {
        self.payload = payload
        self.symbology = symbology
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Represent a contour detection result.
public struct MLContour: Sendable {
    /// The contour points in pixel coordinates.
    public let points: [SIMD2<Float>]
    /// The indices of child contours.
    public let childIndices: [Int]

    public init(points: [SIMD2<Float>], childIndices: [Int]) {
        self.points = points
        self.childIndices = childIndices
    }
}

// MARK: - 3D Pose Types

/// Represent a single 3D pose landmark (one joint in meter-scale 3D coordinates).
public struct MLLandmark3D: Sendable {
    /// The joint name (e.g., "root_joint", "left_hand_joint").
    public let name: String
    /// The x coordinate in meters (relative to the root joint).
    public let x: Float
    /// The y coordinate in meters (relative to the root joint).
    public let y: Float
    /// The z coordinate in meters (relative to the root joint).
    public let z: Float
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float
    /// The local position relative to the parent joint as a 4x4 matrix (advanced use).
    public let localPosition: simd_float4x4?

    public init(name: String, x: Float, y: Float, z: Float, confidence: Float, localPosition: simd_float4x4? = nil) {
        self.name = name
        self.x = x
        self.y = y
        self.z = z
        self.confidence = confidence
        self.localPosition = localPosition
    }

    /// Return the position as a SIMD3 vector.
    public var position: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

/// Represent a 3D body pose estimation result.
public struct MLPose3D: Sendable {
    /// The list of all 3D landmarks.
    public let landmarks: [MLLandmark3D]
    /// The overall confidence score.
    public let confidence: Float
    /// The estimated body height in meters.
    public let bodyHeight: Float

    public init(landmarks: [MLLandmark3D], confidence: Float, bodyHeight: Float = 0) {
        self.landmarks = landmarks
        self.confidence = confidence
        self.bodyHeight = bodyHeight
    }

    /// Find a 3D landmark by name.
    /// - Parameter name: The landmark name to search for.
    /// - Returns: The matching 3D landmark, or nil if not found.
    public func landmark(_ name: String) -> MLLandmark3D? {
        landmarks.first { $0.name == name }
    }
}

// MARK: - Rectangle Detection

/// Represent a detected rectangle with four corner points.
public struct MLRectangle: Sendable {
    /// The top-left corner in pixel coordinates.
    public let topLeft: SIMD2<Float>
    /// The top-right corner in pixel coordinates.
    public let topRight: SIMD2<Float>
    /// The bottom-right corner in pixel coordinates.
    public let bottomRight: SIMD2<Float>
    /// The bottom-left corner in pixel coordinates.
    public let bottomLeft: SIMD2<Float>
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float

    public init(topLeft: SIMD2<Float>, topRight: SIMD2<Float>, bottomRight: SIMD2<Float>, bottomLeft: SIMD2<Float>, confidence: Float) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }

    /// Return the center point of the bounding box.
    public var center: SIMD2<Float> {
        (topLeft + topRight + bottomRight + bottomLeft) / 4
    }
}

// MARK: - Image Feature Print

/// Represent an image feature vector for similarity comparison.
public struct MLFeaturePrint: Sendable {
    /// The feature vector data.
    public let data: [Float]
    /// The element type ("float" or "double").
    public let elementType: String
    /// Return the number of elements in the feature vector.
    public var count: Int { data.count }

    public init(data: [Float], elementType: String = "float") {
        self.data = data
        self.elementType = elementType
    }

    /// Compute the cosine distance to another feature print (0.0 = identical, 2.0 = opposite).
    /// - Parameter other: The other feature print to compare against.
    /// - Returns: The cosine distance between the two feature vectors.
    public func distance(to other: MLFeaturePrint) -> Float {
        guard data.count == other.data.count, !data.isEmpty else { return Float.infinity }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<data.count {
            dotProduct += data[i] * other.data[i]
            normA += data[i] * data[i]
            normB += other.data[i] * other.data[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return Float.infinity }
        return 1.0 - (dotProduct / denom)
    }
}

// MARK: - Instance Mask

/// Represent an instance mask result for foreground or person segmentation.
public struct MLInstanceMask: Sendable {
    /// The mask width in pixels.
    public let width: Int
    /// The mask height in pixels.
    public let height: Int
    /// The number of detected instances.
    public let instanceCount: Int
    /// The per-instance mask data (0.0 to 1.0, row-major order).
    public let instanceMasks: [[Float]]
    /// The combined mask of all instances (0.0 to 1.0, row-major order).
    public let combinedMask: [Float]

    public init(width: Int, height: Int, instanceCount: Int, instanceMasks: [[Float]], combinedMask: [Float]) {
        self.width = width
        self.height = height
        self.instanceCount = instanceCount
        self.instanceMasks = instanceMasks
        self.combinedMask = combinedMask
    }

    /// Return the mask data for a specific instance.
    /// - Parameter index: The zero-based instance index.
    /// - Returns: The mask data array for the instance, or nil if the index is out of range.
    public func mask(forInstance index: Int) -> [Float]? {
        guard index >= 0, index < instanceMasks.count else { return nil }
        return instanceMasks[index]
    }
}

// MARK: - Object Tracking

/// Represent an object tracking result.
public struct MLTrackedObject: Sendable {
    /// The bounding box x position in pixel coordinates (top-left origin).
    public let x: Float
    /// The bounding box y position in pixel coordinates.
    public let y: Float
    /// The bounding box width in pixels.
    public let w: Float
    /// The bounding box height in pixels.
    public let h: Float
    /// The confidence score (0.0 to 1.0).
    public let confidence: Float
    /// Indicate whether tracking is still active.
    public let isTracking: Bool

    public init(x: Float, y: Float, w: Float, h: Float, confidence: Float, isTracking: Bool) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.confidence = confidence
        self.isTracking = isTracking
    }
}

// MARK: - Optical Flow

/// Represent an optical flow result with per-pixel motion vectors.
public struct MLOpticalFlow: Sendable {
    /// The flow field width in pixels.
    public let width: Int
    /// The flow field height in pixels.
    public let height: Int
    /// The flow vector data (dx, dy pairs in row-major order).
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }

    /// Return the flow vector at the given pixel position.
    /// - Parameters:
    ///   - x: The pixel x coordinate.
    ///   - y: The pixel y coordinate.
    /// - Returns: The flow vector as a SIMD2, or nil if the coordinates are out of bounds.
    public func flow(at x: Int, y: Int) -> SIMD2<Float>? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let idx = (y * width + x) * 2
        guard idx + 1 < data.count else { return nil }
        return SIMD2<Float>(data[idx], data[idx + 1])
    }

    /// Return the average magnitude of all flow vectors.
    public var averageMagnitude: Float {
        guard !data.isEmpty else { return 0 }
        var total: Float = 0
        let count = width * height
        for i in 0..<count {
            let dx = data[i * 2]
            let dy = data[i * 2 + 1]
            total += sqrt(dx * dx + dy * dy)
        }
        return total / Float(count)
    }
}

// MARK: - Compute Unit

/// Represent the compute unit preference for CoreML inference.
public enum MLComputeUnit: Sendable {
    case cpuOnly
    case cpuAndGPU
    case cpuAndNeuralEngine
    case all

    var coreMLUnit: MLComputeUnits {
        switch self {
        case .cpuOnly: return .cpuOnly
        case .cpuAndGPU: return .cpuAndGPU
        case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
        case .all: return .all
        }
    }
}
