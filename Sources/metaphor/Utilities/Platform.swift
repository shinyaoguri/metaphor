#if os(macOS)
import AppKit
public typealias PlatformView = NSView
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
public typealias PlatformView = UIView
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif
