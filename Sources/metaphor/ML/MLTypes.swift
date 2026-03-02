import CoreML
import simd

/// 画像分類結果
public struct MLClassification: Sendable {
    /// ラベル（e.g., "cat", "dog"）
    public let label: String
    /// 信頼度（0.0〜1.0）
    public let confidence: Float

    public init(label: String, confidence: Float) {
        self.label = label
        self.confidence = confidence
    }
}

/// オブジェクト検出結果
public struct MLDetection: Sendable {
    /// ラベル
    public let label: String
    /// 信頼度（0.0〜1.0）
    public let confidence: Float
    /// バウンディングボックス（ピクセル座標、左上原点）
    public let x: Float
    public let y: Float
    public let w: Float
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

/// ポーズのランドマーク（1つの関節）
public struct MLLandmark: Sendable {
    /// 関節名
    public let name: String
    /// ピクセル座標
    public let x: Float
    public let y: Float
    /// 信頼度（0.0〜1.0）
    public let confidence: Float

    public init(name: String, x: Float, y: Float, confidence: Float) {
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// ボディ/ハンド/フェイスポーズ結果
public struct MLPose: Sendable {
    /// 全ランドマーク
    public let landmarks: [MLLandmark]
    /// 信頼度（全体）
    public let confidence: Float

    public init(landmarks: [MLLandmark], confidence: Float) {
        self.landmarks = landmarks
        self.confidence = confidence
    }

    /// 名前でランドマークを検索
    public func landmark(_ name: String) -> MLLandmark? {
        landmarks.first { $0.name == name }
    }
}

/// セグメンテーションマスク
public struct MLSegmentMask: Sendable {
    /// マスクの幅
    public let width: Int
    /// マスクの高さ
    public let height: Int
    /// マスクの生データ（0.0〜1.0、row-major）
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }
}

/// 顔検出結果
public struct MLFace: Sendable {
    /// バウンディングボックス（ピクセル座標）
    public let x: Float
    public let y: Float
    public let w: Float
    public let h: Float
    /// ランドマーク（目、鼻、口など）
    public let landmarks: [MLLandmark]

    public init(x: Float, y: Float, w: Float, h: Float, landmarks: [MLLandmark]) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.landmarks = landmarks
    }
}

/// テキスト認識結果
public struct MLText: Sendable {
    /// 認識テキスト
    public let text: String
    /// 信頼度
    public let confidence: Float
    /// バウンディングボックス（ピクセル座標）
    public let x: Float
    public let y: Float
    public let w: Float
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

/// サリエンシーヒートマップ
public struct MLSaliency: Sendable {
    /// ヒートマップの幅
    public let width: Int
    /// ヒートマップの高さ
    public let height: Int
    /// ヒートマップデータ（0.0〜1.0、row-major）
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }
}

/// バーコード/QR検出結果
public struct MLBarcode: Sendable {
    /// デコードされた文字列
    public let payload: String
    /// シンボロジー（e.g., "QR", "EAN-13"）
    public let symbology: String
    /// バウンディングボックス（ピクセル座標）
    public let x: Float
    public let y: Float
    public let w: Float
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

/// 輪郭検出結果
public struct MLContour: Sendable {
    /// 輪郭点（ピクセル座標）
    public let points: [SIMD2<Float>]
    /// 子輪郭のインデックス
    public let childIndices: [Int]

    public init(points: [SIMD2<Float>], childIndices: [Int]) {
        self.points = points
        self.childIndices = childIndices
    }
}

// MARK: - 3D Pose Types

/// 3Dポーズのランドマーク（1つの関節、メートル単位の3D座標）
public struct MLLandmark3D: Sendable {
    /// 関節名（e.g., "root_joint", "left_hand_joint"）
    public let name: String
    /// X座標（メートル単位、ルートジョイント基準）
    public let x: Float
    /// Y座標（メートル単位、ルートジョイント基準）
    public let y: Float
    /// Z座標（メートル単位、ルートジョイント基準）
    public let z: Float
    /// 信頼度（0.0〜1.0）
    public let confidence: Float
    /// 親ジョイント基準のローカル位置（4x4行列、上級者向け）
    public let localPosition: simd_float4x4?

    public init(name: String, x: Float, y: Float, z: Float, confidence: Float, localPosition: simd_float4x4? = nil) {
        self.name = name
        self.x = x
        self.y = y
        self.z = z
        self.confidence = confidence
        self.localPosition = localPosition
    }

    /// SIMD3 としての位置
    public var position: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

/// 3Dボディポーズ結果
public struct MLPose3D: Sendable {
    /// 全3Dランドマーク
    public let landmarks: [MLLandmark3D]
    /// 信頼度（全体）
    public let confidence: Float
    /// ボディの高さ（メートル単位）
    public let bodyHeight: Float

    public init(landmarks: [MLLandmark3D], confidence: Float, bodyHeight: Float = 0) {
        self.landmarks = landmarks
        self.confidence = confidence
        self.bodyHeight = bodyHeight
    }

    /// 名前でランドマークを検索
    public func landmark(_ name: String) -> MLLandmark3D? {
        landmarks.first { $0.name == name }
    }
}

// MARK: - Rectangle Detection

/// 矩形検出結果（4コーナーポイント）
public struct MLRectangle: Sendable {
    /// 左上（ピクセル座標）
    public let topLeft: SIMD2<Float>
    /// 右上（ピクセル座標）
    public let topRight: SIMD2<Float>
    /// 右下（ピクセル座標）
    public let bottomRight: SIMD2<Float>
    /// 左下（ピクセル座標）
    public let bottomLeft: SIMD2<Float>
    /// 信頼度（0.0〜1.0）
    public let confidence: Float

    public init(topLeft: SIMD2<Float>, topRight: SIMD2<Float>, bottomRight: SIMD2<Float>, bottomLeft: SIMD2<Float>, confidence: Float) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }

    /// バウンディングボックスの中心点
    public var center: SIMD2<Float> {
        (topLeft + topRight + bottomRight + bottomLeft) / 4
    }
}

// MARK: - Image Feature Print

/// 画像特徴ベクトル（類似度比較用）
public struct MLFeaturePrint: Sendable {
    /// 特徴ベクトルデータ
    public let data: [Float]
    /// 要素タイプ（"float" or "double"）
    public let elementType: String
    /// 要素数
    public var count: Int { data.count }

    public init(data: [Float], elementType: String = "float") {
        self.data = data
        self.elementType = elementType
    }

    /// 2つの特徴ベクトル間のコサイン距離（0.0 = 同一、2.0 = 正反対）
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

/// インスタンスマスク結果（前景/人物の個別セグメンテーション）
public struct MLInstanceMask: Sendable {
    /// マスクの幅
    public let width: Int
    /// マスクの高さ
    public let height: Int
    /// インスタンス数
    public let instanceCount: Int
    /// 各インスタンスのマスクデータ（0.0〜1.0、row-major）
    public let instanceMasks: [[Float]]
    /// 全インスタンス統合マスク（0.0〜1.0、row-major）
    public let combinedMask: [Float]

    public init(width: Int, height: Int, instanceCount: Int, instanceMasks: [[Float]], combinedMask: [Float]) {
        self.width = width
        self.height = height
        self.instanceCount = instanceCount
        self.instanceMasks = instanceMasks
        self.combinedMask = combinedMask
    }

    /// 指定インスタンスのマスクデータを取得
    public func mask(forInstance index: Int) -> [Float]? {
        guard index >= 0, index < instanceMasks.count else { return nil }
        return instanceMasks[index]
    }
}

// MARK: - Object Tracking

/// オブジェクトトラッキング結果
public struct MLTrackedObject: Sendable {
    /// バウンディングボックス x（ピクセル座標、左上原点）
    public let x: Float
    /// バウンディングボックス y
    public let y: Float
    /// バウンディングボックス幅
    public let w: Float
    /// バウンディングボックス高さ
    public let h: Float
    /// 信頼度（0.0〜1.0）
    public let confidence: Float
    /// トラッキングが有効かどうか
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

/// オプティカルフロー結果（ピクセル単位の動きベクトル）
public struct MLOpticalFlow: Sendable {
    /// フローフィールドの幅
    public let width: Int
    /// フローフィールドの高さ
    public let height: Int
    /// フローベクトルデータ（dx,dy pairs、row-major）
    public let data: [Float]

    public init(width: Int, height: Int, data: [Float]) {
        self.width = width
        self.height = height
        self.data = data
    }

    /// 指定ピクセルのフローベクトルを取得
    public func flow(at x: Int, y: Int) -> SIMD2<Float>? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let idx = (y * width + x) * 2
        guard idx + 1 < data.count else { return nil }
        return SIMD2<Float>(data[idx], data[idx + 1])
    }

    /// フローの大きさ（マグニチュード）の平均
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

/// コンピュートユニットの設定
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
