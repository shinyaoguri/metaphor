# Image

Functions for loading and drawing images.

## Loading Images

### `loadImage(_ path: String) throws -> MImage`

Loads an image from a file path and returns an `MImage`. Call this in `setup()` to avoid loading every frame.

```swift
var img: MImage!

func setup() {
    img = try! loadImage("/path/to/image.png")
}
```

> Supports PNG, JPEG, and other formats supported by NSImage.

## Drawing Images

### `image(_ img: MImage, _ x: Float, _ y: Float)`

Draws an image at its original size.

```swift
image(img, 100, 100)
```

### `image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float)`

Draws an image scaled to the specified size.

```swift
image(img, 0, 0, width, height)  // Full screen
image(img, 100, 100, 200, 150)   // Custom size
```

## MImage Properties

| Property | Type | Description |
|----------|------|-------------|
| `texture` | `MTLTexture` | Underlying Metal texture |
| `width` | `Float` | Image width in pixels |
| `height` | `Float` | Image height in pixels |

## Screenshots

### `save(_ path: String)`

Saves the current frame as a PNG image to the specified path.

```swift
func keyPressed() {
    if input.lastKey == "s" {
        save("/Users/me/Desktop/screenshot.png")
    }
}
```

### `save()`

Saves the current frame to the Desktop with a timestamp filename.

```swift
func keyPressed() {
    if input.lastKey == "s" {
        save()  // ~/Desktop/metaphor_2024-01-15_14-30-00.png
    }
}
```

## Example

```swift
@main
final class ImageExample: Sketch {
    var photo: MImage!

    func setup() {
        photo = try! loadImage("/path/to/photo.jpg")
    }

    func draw() {
        background(0.0)
        image(photo, 0, 0, width, height)

        // Draw on top of the image
        fill(Color(gray: 1.0, alpha: 0.8))
        textSize(24)
        text("Overlay text", 20, 40)
    }
}
```

## See Also

- [Material & Texture](material.md) - Using images as 3D textures
- [Typography](typography.md) - Text rendering
