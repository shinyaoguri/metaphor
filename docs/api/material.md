# Material & Texture

Functions for controlling surface appearance of 3D objects.

## Specular Highlights

### `specular(_ color: Color)` / `specular(_ gray: Float)`

Sets the specular (shiny highlight) color.

```swift
specular(Color.white)
specular(0.8)
```

### `shininess(_ value: Float)`

Controls the size of specular highlights. Higher values produce smaller, sharper highlights.

```swift
shininess(32)   // Default-ish
shininess(128)  // Very shiny, tight highlight
shininess(4)    // Broad, diffuse highlight
```

## Emissive

### `emissive(_ color: Color)` / `emissive(_ gray: Float)`

Sets the emissive (self-illumination) color. Emissive surfaces appear to glow regardless of lighting.

```swift
emissive(Color(r: 0.2, g: 0.0, b: 0.0))  // Subtle red glow
emissive(0.0)  // No emission (default)
```

## Metallic

### `metallic(_ value: Float)`

Controls the metallic appearance. Range: 0.0 (dielectric) to 1.0 (metallic).

```swift
metallic(0.0)  // Plastic-like (default)
metallic(1.0)  // Metallic (reflections tinted by fill color)
```

## Texture

### `texture(_ img: MImage)`

Applies an image texture to subsequent 3D shapes. All 3D primitives support UV mapping.

```swift
var tex: MImage!

func setup() {
    tex = try! loadImage("/path/to/texture.png")
}

func draw() {
    background(0.1)
    camera(eye: SIMD3(0, 0, 300), center: SIMD3(0, 0, 0))
    perspective()
    lights()

    texture(tex)
    sphere(100)
}
```

### `noTexture()`

Removes the current texture. Shapes will use fill colors.

```swift
noTexture()
```

## Example: Material Showcase

```swift
func draw() {
    background(0.05)
    camera(eye: SIMD3(0, 100, 400), center: SIMD3(0, 0, 0))
    perspective()
    directionalLight(-1, -1, -1)
    ambientLight(0.15)

    // Plastic sphere
    fill(Color.red)
    specular(0.5)
    shininess(32)
    metallic(0.0)
    pushMatrix()
    translate(-150, 0, 0)
    sphere(50)
    popMatrix()

    // Metallic sphere
    fill(Color(r: 0.8, g: 0.7, b: 0.3))  // Gold
    specular(1.0)
    shininess(64)
    metallic(1.0)
    pushMatrix()
    translate(0, 0, 0)
    sphere(50)
    popMatrix()

    // Glowing sphere
    fill(Color.blue)
    specular(0.0)
    metallic(0.0)
    emissive(Color(r: 0.0, g: 0.1, b: 0.4))
    pushMatrix()
    translate(150, 0, 0)
    sphere(50)
    popMatrix()
    emissive(0.0)  // Reset
}
```

## See Also

- [Lighting](lighting.md) - Light sources
- [Image](image.md) - Loading images
- [Color & Style](color.md) - Fill colors
