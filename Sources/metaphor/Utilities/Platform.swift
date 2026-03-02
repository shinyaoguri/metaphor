/// Cross-platform type aliases for macOS and iOS.
///
/// Maps platform-specific UI types to unified names used throughout the library.
#if os(macOS)
import AppKit
/// Platform-native view type (NSView on macOS).
public typealias PlatformView = NSView
/// Platform-native font type (NSFont on macOS).
public typealias PlatformFont = NSFont
/// Platform-native image type (NSImage on macOS).
public typealias PlatformImage = NSImage
/// Platform-native color type (NSColor on macOS).
public typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
/// Platform-native view type (UIView on iOS).
public typealias PlatformView = UIView
/// Platform-native font type (UIFont on iOS).
public typealias PlatformFont = UIFont
/// Platform-native image type (UIImage on iOS).
public typealias PlatformImage = UIImage
/// Platform-native color type (UIColor on iOS).
public typealias PlatformColor = UIColor
#endif
