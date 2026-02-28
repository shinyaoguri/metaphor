# Syphon Output

Stream your sketch to VJ software (Resolume, VDMX, MadMapper, etc.) using [Syphon](http://syphon.v002.info/).

## Setup

Enable Syphon by setting `syphonName` in your `SketchConfig`:

```swift
var config: SketchConfig {
    SketchConfig(
        width: 1920,
        height: 1080,
        title: "My Visual",
        syphonName: "metaphor"  // This name appears in VJ software
    )
}
```

That's it. The Syphon server starts automatically when the sketch launches.

## Receiving in VJ Software

### Resolume Arena / Avenue

1. Add a source to a clip slot
2. Select **Syphon** from the source list
3. Choose **"metaphor"** (or your custom `syphonName`)

### VDMX

1. Add a **Movie** source
2. Switch to **Syphon** input
3. Select the server name

### MadMapper

1. In **Inputs**, click **+**
2. Select **Syphon**
3. Choose the server

## Resolution

The Syphon output uses the texture resolution defined in `SketchConfig` (`width` x `height`), independent of the window size. This means:

- Window scale (`windowScale: 0.5`) only affects the preview window
- VJ software receives the full resolution texture (e.g., 1920x1080)

```swift
var config: SketchConfig {
    SketchConfig(
        width: 3840,
        height: 2160,       // 4K output to VJ software
        windowScale: 0.25   // Small preview window
    )
}
```

## Framework Requirements

Syphon requires the `Syphon.xcframework` binary. It's handled automatically:

- **Development**: Run `make setup` to build from the Syphon submodule
- **SPM users**: The pre-built framework is downloaded from GitHub Releases

## Example

```swift
@main
final class VJVisual: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1920,
            height: 1080,
            title: "VJ Output",
            syphonName: "metaphor"
        )
    }

    func draw() {
        background(0.0)
        blendMode(.additive)

        for i in 0..<50 {
            let t = Float(i) / 50.0
            let hue = (t + time * 0.1).truncatingRemainder(dividingBy: 1.0)
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.3))
            let x = width / 2 + cos(time + t * Float.pi * 2) * 300 * t
            let y = height / 2 + sin(time * 1.3 + t * Float.pi * 2) * 200 * t
            circle(x, y, 50 * (1 - t))
        }
    }
}
```

## See Also

- [Sketch](../api/sketch.md) - SketchConfig reference
- [Color & Style](../api/color.md) - Blend modes for visual effects
