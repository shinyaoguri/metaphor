# Input

Mouse and keyboard input handling.

## Mouse Properties

Access mouse state through the `input` property:

| Property | Type | Description |
|----------|------|-------------|
| `input.mouseX` | `Float` | Current X position (texture coordinates) |
| `input.mouseY` | `Float` | Current Y position (texture coordinates) |
| `input.pmouseX` | `Float` | Previous frame X position |
| `input.pmouseY` | `Float` | Previous frame Y position |
| `input.isMouseDown` | `Bool` | Whether any mouse button is pressed |
| `input.mouseButton` | `Int` | Button index: 0=left, 1=right, 2=middle |

```swift
func draw() {
    background(0.1)
    fill(Color.white)
    circle(input.mouseX, input.mouseY, 20)
}
```

## Mouse Events

Override these methods to respond to mouse events:

### `mousePressed()`

Called when a mouse button is pressed.

```swift
func mousePressed() {
    let x = input.mouseX
    let y = input.mouseY
    // Handle click at (x, y)
}
```

### `mouseReleased()`

Called when a mouse button is released.

### `mouseMoved()`

Called when the mouse moves (no button pressed).

### `mouseDragged()`

Called when the mouse moves while a button is held down.

```swift
func mouseDragged() {
    // Draw a trail while dragging
    stroke(Color.white)
    strokeWeight(3)
    line(input.pmouseX, input.pmouseY, input.mouseX, input.mouseY)
}
```

## Keyboard Properties

| Property | Type | Description |
|----------|------|-------------|
| `input.isKeyPressed` | `Bool` | Whether any key is currently held |
| `input.lastKey` | `Character?` | Last key character pressed |
| `input.lastKeyCode` | `UInt16?` | Last key code pressed |

## Keyboard Events

### `keyPressed()`

Called when a key is pressed.

```swift
func keyPressed() {
    if let key = input.lastKey {
        switch key {
        case " ":
            paused.toggle()
        case "r":
            reset()
        case "s":
            save()
        default:
            break
        }
    }
}
```

### `keyReleased()`

Called when a key is released.

### `isKeyDown(_ keyCode: UInt16) -> Bool`

Check if a specific key is currently held down by its key code.

```swift
func draw() {
    if input.isKeyDown(0x00) { // 'a' key
        translate(-5, 0)
    }
    if input.isKeyDown(0x02) { // 'd' key
        translate(5, 0)
    }
}
```

## Example: Interactive Drawing

```swift
@main
final class DrawingApp: Sketch {
    var color = Color.white

    func draw() {
        // Don't clear - accumulate strokes
        if input.isMouseDown {
            fill(color)
            noStroke()
            circle(input.mouseX, input.mouseY, 10)
        }
    }

    func keyPressed() {
        if let key = input.lastKey {
            switch key {
            case "1": color = Color.red
            case "2": color = Color.green
            case "3": color = Color.blue
            case "c": background(0.1)  // Clear
            default: break
            }
        }
    }
}
```

## See Also

- [Sketch](sketch.md) - Lifecycle and event methods
