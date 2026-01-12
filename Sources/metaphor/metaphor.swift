// metaphor - Swift + Metal Creative Coding Library
// https://github.com/user/metaphor

@_exported import Metal
@_exported import MetalKit
@_exported import simd
@_exported import Syphon

// MARK: - Re-exports for Processing-like API

// Core types are automatically available as they're public
// No need for explicit re-exports in Swift modules

// Graphics API:
// - Graphics: Main drawing context with Processing-like methods
// - Color: RGBA color type
// - RenderState, RectMode, EllipseMode, ShapeKind, CloseMode: Drawing state types

// Sketch API:
// - Sketch: Protocol for class-based sketches
// - SketchView: SwiftUI view for Sketch protocol
// - SketchRunner: Sketch execution manager

// QuickSketch API:
// - QuickSketchConfig: Configuration for closure-based sketches
// - QuickSketchView: SwiftUI view for quick sketches
// - sketch(width:height:fps:draw:): Convenience function

// Input API:
// - InputState: Mouse and keyboard state manager
// - InputSnapshot: Immutable snapshot of input state
// - MouseButton: Mouse button enum
