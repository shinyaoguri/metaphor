import Testing
import simd

// MARK: - Approximate Equality

/// Assert that two `Float` values are approximately equal within an epsilon.
public func expectApproxEqual(
    _ a: Float,
    _ b: Float,
    epsilon: Float = 1e-4,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(a - b) < epsilon,
        "Expected \(a) ≈ \(b) (epsilon: \(epsilon), delta: \(abs(a - b)))",
        sourceLocation: sourceLocation
    )
}

/// Assert that two `Double` values are approximately equal within an epsilon.
public func expectApproxEqual(
    _ a: Double,
    _ b: Double,
    epsilon: Double = 1e-6,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(a - b) < epsilon,
        "Expected \(a) ≈ \(b) (epsilon: \(epsilon), delta: \(abs(a - b)))",
        sourceLocation: sourceLocation
    )
}

/// Assert that two `SIMD2<Float>` values are approximately equal per-component.
public func expectApproxEqual(
    _ a: SIMD2<Float>,
    _ b: SIMD2<Float>,
    epsilon: Float = 1e-4,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for i in 0..<2 {
        #expect(
            abs(a[i] - b[i]) < epsilon,
            "SIMD2 component [\(i)]: \(a[i]) ≈ \(b[i]) (epsilon: \(epsilon))",
            sourceLocation: sourceLocation
        )
    }
}

/// Assert that two `SIMD3<Float>` values are approximately equal per-component.
public func expectApproxEqual(
    _ a: SIMD3<Float>,
    _ b: SIMD3<Float>,
    epsilon: Float = 1e-4,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for i in 0..<3 {
        #expect(
            abs(a[i] - b[i]) < epsilon,
            "SIMD3 component [\(i)]: \(a[i]) ≈ \(b[i]) (epsilon: \(epsilon))",
            sourceLocation: sourceLocation
        )
    }
}

/// Assert that two `SIMD4<Float>` values are approximately equal per-component.
public func expectApproxEqual(
    _ a: SIMD4<Float>,
    _ b: SIMD4<Float>,
    epsilon: Float = 1e-4,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for i in 0..<4 {
        #expect(
            abs(a[i] - b[i]) < epsilon,
            "SIMD4 component [\(i)]: \(a[i]) ≈ \(b[i]) (epsilon: \(epsilon))",
            sourceLocation: sourceLocation
        )
    }
}

/// Assert that two `float4x4` matrices are approximately equal per-element.
public func expectApproxEqual(
    _ a: float4x4,
    _ b: float4x4,
    epsilon: Float = 1e-4,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for col in 0..<4 {
        for row in 0..<4 {
            #expect(
                abs(a[col][row] - b[col][row]) < epsilon,
                "float4x4[\(col)][\(row)]: \(a[col][row]) ≈ \(b[col][row]) (epsilon: \(epsilon))",
                sourceLocation: sourceLocation
            )
        }
    }
}

// MARK: - Range Checks

/// Assert that a value is within a closed range.
public func expectInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        range.contains(value),
        "Expected \(value) to be in \(range)",
        sourceLocation: sourceLocation
    )
}
