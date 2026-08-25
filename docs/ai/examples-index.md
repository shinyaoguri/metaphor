# metaphor Examples Index For AI

This file is generated from `Examples/**/Package.swift` and adjacent
`*.json` metadata. Use it to find a nearby working sketch before
generating new metaphor content.

Example count: 283

Status: supported 267, partial 0, stub 6, obsolete 10

## How To Use

- Pick one or two examples whose tags match the user's request.
- Read the example's `App.swift` before inventing a new structure.
- Prefer adapting existing metaphor idioms over translating p5.js code
  literally.
- Avoid `[stub]` (placeholder, blocked on a planned API) and `[obsolete]`
  (Processing/OpenGL-specific, won't be added) examples as references.
- `shader` is assigned from the code: the sketch calls metaphor's shader /
  post-process API (`addPostEffect`, `createPostEffect`, `createMaterial`,
  `createEffectPass`, ...) or ships its own `.metal` source.
  `cpu-approximation` marks the opposite case — a port of a Processing
  sample whose original was GLSL, redone with CPU pixel loops. Every
  example under `Examples/Topics/Shaders/` except `CustomShader2D` is
  `cpu-approximation`: read those for the effect, never as shader
  references. For 2D custom shaders (`loadShader()` / `createShader()` /
  `shader()` / `resetShader()`), `CustomShader2D` is the reference.

## Machine-Readable Access

This index ships in two formats: this `.md` (human-oriented browsing)
and `examples-index.json` in the same directory (machine-oriented —
prefer it when filtering by tag, level, or status programmatically).

JSON top-level keys: `count`, `statusCounts`, `examples`. Each entry in
`examples` has: `title`, `path` (repo-relative), `group`, `subcategory`,
`level` (`Beginner` / `Intermediate` / `Advanced` / empty), `status`
(`supported` / `partial` / `stub` / `obsolete`), `description`,
`featured` (APIs/concepts the original Processing sample features —
Processing vocabulary such as `PVector` or `pushMatrix_`; empty for
metaphor-original samples), `tags`.

Query examples (jq):

```sh
# Paths of all supported 3D examples
jq -r '.examples[] | select(.status == "supported")
       | select(.tags | index("3d")) | .path' docs/ai/examples-index.json

# Examples whose original Processing sample features PVector
jq -r '.examples[] | select(.featured | index("PVector"))
       | .path' docs/ai/examples-index.json
```

## Basics

- [Array](../../Examples/Basics/Arrays/Array) [Beginner] (Arrays) -- An array is a list of data. Each piece of data in an array is identified by an index number representing its position in the array. Arrays are zero based, which means that the first element in the array is [0], the seco... Tags: array, arrays, basics.
- [Array 2D](../../Examples/Basics/Arrays/Array2D) [Intermediate] (Arrays) -- Demonstrates the syntax for creating a two-dimensional (2D) array. Values in a 2D array are accessed through two index values. 2D arrays are useful for storing images. In this example, each dot is colored in relation to... Tags: array2d, arrays, basics, image.
- [Array Objects](../../Examples/Basics/Arrays/ArrayObjects) [Advanced] (Arrays) -- Demonstrates the syntax for creating an array of custom objects. Tags: arrayobjects, arrays, basics.
- [Brightness](../../Examples/Basics/Color/Brightness) [Intermediate] (Color) -- Moving the cursor vertically over each bar sets that bar's brightness. HSB color mode maps the bar's horizontal position to hue and the cursor's height to brightness. Tags: basics, brightness, color.
- [Color Variables (Homage to Albers)](../../Examples/Basics/Color/ColorVariables) [Beginner] (Color) -- This example creates variables for colors that may be referred to in the program by a name, rather than a number. Tags: basics, color, colorvariables.
- [Hue](../../Examples/Basics/Color/Hue) [Beginner] (Color) -- Hue is the color reflected from or transmitted through an object and is typically referred to as the name of the color such as red, blue, or yellow. In this example, move the cursor vertically over each bar to alter its... Tags: basics, color, hue.
- [Simple Linear Gradient](../../Examples/Basics/Color/LinearGradient) [Intermediate] (Color) -- The lerpColor() function is useful for interpolating between two colors. Tags: basics, color, lineargradient.
- [Radial Gradient](../../Examples/Basics/Color/RadialGradient) [Intermediate] (Color) -- Draws a series of concentric circles to create a gradient from one color to another. Tags: basics, color, radialgradient.
- [Relativity](../../Examples/Basics/Color/Relativity) [Intermediate] (Color) -- Each color is perceived in relation to other colors. The top and bottom bars each contain the same component colors, but a different display order causes individual colors to appear differently. Tags: basics, color, relativity.
- [Saturation](../../Examples/Basics/Color/Saturation) [Beginner] (Color) -- Saturation is the strength or purity of the color and represents the amount of gray in proportion to the hue. A "saturated" color is pure and an "unsaturated" color has a large percentage of gray. Move the cursor vertic... Tags: basics, color, saturation.
- [WaveGradient](../../Examples/Basics/Color/WaveGradient) (Color) Tags: basics, color, wavegradient.
- [Move Eye](../../Examples/Basics/Control/Camera/MoveEye) [Intermediate] (Control) -- The camera's eye lifts as the cursor moves down the window while it keeps looking at the same point. A lit box and three axis lines make the shift in viewpoint visible. Tags: 3d, basics, camera, control, moveeye.
- [Perspective vs Ortho](../../Examples/Basics/Control/Camera/Orthographic) [Intermediate] (Control) -- Move the mouse left to right to change the "far" parameter for the perspective() and ortho() functions. This parameter sets the maximum distance from the origin away from the viewer and will clip the geometry. Click a m... Tags: 3d, basics, camera, control, interaction, orthographic.
- [Perspective](../../Examples/Basics/Control/Camera/Perspective) [Intermediate] (Control) -- Move the mouse left and right to change the field of view (fov). Click to modify the aspect ratio. The perspective() function sets a perspective projection applying foreshortening, making distant objects appear smaller... Tags: 3d, basics, camera, control, interaction, perspective.
- [Conditionals 1](../../Examples/Basics/Control/Conditionals1) [Beginner] (Control) -- Conditions are like questions. They allow a program to decide to take one action if the answer to a question is "true" or to do another action if the answer to the question is "false."<br /> The questions asked within a... Tags: basics, conditionals1, control.
- [Conditionals 2](../../Examples/Basics/Control/Conditionals2) [Beginner] (Control) -- We extend the language of conditionals from the previous example by adding the keyword "else". This allows conditionals to ask two or more sequential questions, each with a different action. Tags: basics, conditionals2, control.
- [Embedding Iteration](../../Examples/Basics/Control/EmbeddedIteration) [Beginner] (Control) -- Embedding "for" structures allows repetition in two dimensions. Tags: basics, control, embeddediteration.
- [Iteration](../../Examples/Basics/Control/Iteration) [Beginner] (Control) -- Iteration with a "for" structure to construct repetitive forms. Tags: basics, control, iteration.
- [Logical Operators](../../Examples/Basics/Control/LogicalOperators) [Beginner] (Control) -- The logical operators for AND (&&) and OR (||) are used to combine simple relational statements into more complex expressions. The NOT (!) operator is used to negate a boolean statement. Tags: basics, control, logicaloperators.
- [Characters Strings](../../Examples/Basics/Data/CharactersStrings) [Beginner] (Data) -- The character datatype, abbreviated as char, stores letters and symbols in the Unicode format, a coding system developed to support a variety of world languages. Characters are distinguished from other symbols by puttin... Tags: basics, charactersstrings, data, image, interaction, typography.
- [Datatype Conversion](../../Examples/Basics/Data/DatatypeConversion) [Intermediate] (Data) -- It is sometimes beneficial to convert a value from one type of data to another. Each of the conversion functions converts its parameter to an equivalent representation within its datatype. The conversion functions inclu... Tags: basics, data, datatypeconversion.
- [Integers Floats](../../Examples/Basics/Data/IntegersFloats) [Beginner] (Data) -- Integers and floats are two different kinds of numerical data. An integer (more commonly called an int) is a number without a decimal point. A float is a floating-point number, which means it is a number that has a deci... Tags: basics, data, integersfloats.
- [True/False](../../Examples/Basics/Data/TrueFalse) [Beginner] (Data) -- A Boolean variable has only two possible values: true or false. It is common to use Booleans with control statements to determine the flow of a program. In this example, when the boolean value "x" is true, vertical blac... Tags: basics, data, truefalse.
- [Variable Scope](../../Examples/Basics/Data/VariableScope) [Intermediate] (Data) -- Variables have a global or local "scope". For example, variables declared within either the setup() or draw() functions may be only used in these functions. Global variables, variables declared outside of setup() and dr... Tags: basics, data, variablescope.
- [Variables](../../Examples/Basics/Data/Variables) [Beginner] (Data) -- Variables are used for storing values. In this example, change the values of variables to affect the composition. Tags: basics, data, variables.
- [Bezier](../../Examples/Basics/Form/Bezier) [Intermediate] (Form) -- The first two parameters for the bezier() function specify the first point in the curve and the last two parameters specify the last point. The middle parameters set the control points that define the shape of the curve. Tags: basics, bezier, form.
- [Pie Chart](../../Examples/Basics/Form/PieChart) [Beginner] (Form) -- Uses the arc() function to generate a pie chart from the data stored in an array. Tags: basics, form, piechart.
- [Points and Lines](../../Examples/Basics/Form/PointsLines) [Beginner] (Form) -- Points and lines can be used to draw basic geometry. Change the value of the variable 'd' to scale the form. The four variables set the positions based on the value of 'd'. Tags: basics, form, pointslines.
- [Primitives 3D](../../Examples/Basics/Form/Primitives3D) (Form) -- Placing mathematically 3D objects in synthetic space. The lights() method reveals their imagined dimension. The box() and sphere() functions each have one parameter which is used to specify their size. These shapes are... Tags: 3d, basics, form, primitives3d.
- [Regular Polygon](../../Examples/Basics/Form/RegularPolygon) [Beginner] (Form) -- What is your favorite? Pentagon? Hexagon? Heptagon? No? What about the icosagon? The polygon() function created for this example is capable of drawing any regular polygon. Try placing different numbers into the polygon(... Tags: basics, form, regularpolygon.
- [Shape Primitives](../../Examples/Basics/Form/ShapePrimitives) [Beginner] (Form) -- The basic shape primitive functions are triangle(), rect(), quad(), ellipse(), and arc(). Squares are made with rect() and circles are made with ellipse(). Each of these functions requires a number of parameters to dete... Tags: basics, form, shapeprimitives.
- [Star](../../Examples/Basics/Form/Star) [Intermediate] (Form) -- The star() function created for this example is capable of drawing a wide range of different forms. Try placing different numbers into the star() function calls within draw() to explore. Tags: basics, form, star.
- [Triangle Strip](../../Examples/Basics/Form/TriangleStrip) [Intermediate] (Form) -- Builds a closed ring from a triangle strip whose vertices alternate between an outer and an inner radius. The cursor's horizontal position sets how many segments the ring is divided into. Tags: basics, form, trianglestrip.
- [Alpha Mask](../../Examples/Basics/Image/Alphamask) [Intermediate] (Image) -- Loads a "mask" for an image to specify the transparency in different parts of the image. The two images are blended together using the mask() method of PImage. Tags: alphamask, basics, image.
- [Background Image](../../Examples/Basics/Image/BackgroundImage) [Beginner] (Image) -- This example presents the fastest way to load a background image into Processing. To load an image as the background, it must be the same width and height as the program. Tags: backgroundimage, basics, image.
- [Create Image](../../Examples/Basics/Image/CreateImage) [Intermediate] (Image) -- The createImage() function provides a fresh buffer of pixels to play with. This example creates an image gradient. Tags: basics, createimage, image.
- [Load and Display Image](../../Examples/Basics/Image/LoadDisplayImage) [Beginner] (Image) -- Images can be loaded and displayed to the screen at their actual size or any other size. Tags: basics, image, loaddisplayimage.
- [Pointillism](../../Examples/Basics/Image/Pointillism) [Intermediate] (Image) -- Redraws a generated image as a field of dots. Each frame samples random pixels and paints ellipses in the sampled color, and the cursor's horizontal position sets the dot size. Tags: basics, image, pointillism.
- [Request Image](../../Examples/Basics/Image/RequestImage) [Intermediate] (Image) -- Loads a sequence of images and shows a spinning loading indicator until every frame has arrived, then draws them in a grid. Tags: basics, image, requestimage.
- [Transparency](../../Examples/Basics/Image/Transparency) [Intermediate] (Image) -- Move the pointer left and right across the image to change its position. This program overlays one image over another by modifying the alpha value of the image with the tint() function. Tags: basics, image, transparency.
- [Clock](../../Examples/Basics/Input/Clock) [Intermediate] (Input) -- The current time can be read with the second(), minute(), and hour() functions. In this example, sin() and cos() values are used to set the position of the hands. Tags: basics, clock, input, interaction.
- [Constrain](../../Examples/Basics/Input/Constrain) [Beginner] (Input) -- Move the mouse across the screen to move the circle. The program constrains the circle to its box. Tags: basics, constrain, input, interaction.
- [Easing](../../Examples/Basics/Input/Easing) [Beginner] (Input) -- Move the mouse across the screen and the symbol will follow. Between drawing each frame of the animation, the program calculates the difference between the position of the symbol and the cursor. If the distance is large... Tags: basics, easing, image, input, interaction.
- [Keyboard](../../Examples/Basics/Input/Keyboard) [Beginner] (Input) -- Click on the image to give it focus and press the letter keys to create forms in time and space. Each key has a unique identifying number. These numbers can be used to position shapes in space. Tags: basics, image, input, interaction, keyboard, typography.
- [Keyboard Functions](../../Examples/Basics/Input/KeyboardFunctions) [Intermediate] (Input) -- Pressing a letter key draws a colored bar for that character, wrapping across the window. Each of the 26 letters gets its own hue from HSB color mode. Tags: basics, input, interaction, keyboardfunctions, typography.
- [Milliseconds](../../Examples/Basics/Input/Milliseconds) [Beginner] (Input) -- A millisecond is 1/1000 of a second. Processing keeps track of the number of milliseconds a program has run. By modifying this number with the modulo(%) operator, different patterns in time are created. Tags: basics, input, interaction, milliseconds.
- [Mouse 1D](../../Examples/Basics/Input/Mouse1D) [Beginner] (Input) -- Move the mouse left and right to shift the balance. The "mouseX" variable is used to control both the size and color of the rectangles. Tags: basics, input, interaction, mouse1d.
- [Mouse 2D](../../Examples/Basics/Input/Mouse2D) [Beginner] (Input) -- Moving the mouse changes the position and size of each box. Tags: basics, input, interaction, mouse2d.
- [Mouse Functions](../../Examples/Basics/Input/MouseFunctions) [Intermediate] (Input) -- Click on the box and drag it across the screen. Tags: basics, input, interaction, mousefunctions.
- [Mouse Press](../../Examples/Basics/Input/MousePress) [Beginner] (Input) -- Move the mouse to position the shape. Press the mouse button to invert the color. Tags: basics, input, interaction, mousepress.
- [Mouse Signals](../../Examples/Basics/Input/MouseSignals) [Beginner] (Input) -- Move and click the mouse to generate signals. The top row is the signal from "mouseX", the middle row is the signal from "mouseY", and the bottom row is the signal from "mousePressed". Tags: basics, input, interaction, mousesignals.
- [Storing Input](../../Examples/Basics/Input/StoringInput) [Beginner] (Input) -- Move the mouse across the screen to change the position of the circles. The positions of the mouse are recorded into an array and played back every frame. Between each frame, the newest value are added to the end of eac... Tags: basics, export, input, interaction, storinginput.
- [Directional](../../Examples/Basics/Lights/Directional) [Intermediate] (Lights) -- Move the mouse the change the direction of the light. Directional light comes from one direction and is stronger when hitting a surface squarely and weaker if it hits at a a gentle angle. After hitting a surface, a dire... Tags: 3d, basics, directional, interaction, lights.
- [Mixture](../../Examples/Basics/Lights/Mixture) [Intermediate] (Lights) -- One box lit by three kinds of light at once: a point light, a directional light and a spot light. Moving the mouse rotates the box so each light's contribution becomes visible. Tags: 3d, basics, interaction, lights, mixture.
- [Mixture Grid](../../Examples/Basics/Lights/MixtureGrid) [Intermediate] (Lights) -- The same three-light mixture applied to a grid of boxes, showing how point, directional and spot lights fall off differently across a scene. Tags: 3d, basics, lights, mixturegrid.
- [On/Off](../../Examples/Basics/Lights/OnOff) [Intermediate] (Lights) -- Uses the default lights to show a simple box. The lights() function is used to turn on the default lighting. Click the mouse to turn the lights off. Tags: 3d, basics, interaction, lights, onoff.
- [Reflection](../../Examples/Basics/Lights/Reflection) [Intermediate] (Lights) -- A sphere lit by a directional light. The cursor's horizontal position raises the specular coefficient, tightening the highlight from a broad sheen to a small bright spot. Tags: 3d, basics, lights, reflection.
- [Spot](../../Examples/Basics/Lights/Spot) [Intermediate] (Lights) -- Move the mouse to change the position of a blue spot light. Tags: 3d, basics, interaction, lights, spot.
- [Additive Wave](../../Examples/Basics/Math/AdditiveWave) [Intermediate] (Math) -- Adds four sine and cosine waves with random amplitudes and periods into a single wave, drawn as a band of translucent circles. Tags: additivewave, basics, math.
- [Arctangent](../../Examples/Basics/Math/Arctangent) [Intermediate] (Math) -- Move the mouse to change the direction of the eyes. The atan2() function computes the angle from each eye to the cursor. Tags: arctangent, basics, interaction, math.
- [Distance 1D](../../Examples/Basics/Math/Distance1D) [Beginner] (Math) -- Move the mouse left and right to control the speed and direction of the moving shapes. Tags: basics, distance1d, interaction, math.
- [Distance 2D](../../Examples/Basics/Math/Distance2D) [Beginner] (Math) -- Move the mouse across the image to obscure and reveal the matrix. Measures the distance from the mouse to each square and sets the size proportionally. Tags: basics, distance2d, image, interaction, math.
- [Double Random](../../Examples/Basics/Math/DoubleRandom) [Beginner] (Math) -- Draws a jagged line across the window by accumulating a random walk on top of a per-point random offset, so the spread widens from left to right. Tags: basics, doublerandom, math.
- [Graphing 2D Equations](../../Examples/Basics/Math/Graphing2DEquation) [Intermediate] (Math) -- Plots a two-variable equation into the pixel buffer, one gray value per pixel. The cursor's horizontal position changes a term in the equation, so the interference pattern morphs as the mouse moves. Tags: basics, graphing2dequation, image, interaction, math.
- [Increment Decrement](../../Examples/Basics/Math/IncrementDecrement) [Beginner] (Math) -- Writing "a++" is equivalent to "a = a + 1". Writing "a--" is equivalent to "a = a - 1". Tags: basics, incrementdecrement, math.
- [Linear Interpolation](../../Examples/Basics/Math/Interpolate) [Beginner] (Math) -- Move the mouse across the screen and the symbol will follow. Between drawing each frame of the animation, the ellipse moves part of the distance (0.05) from its current position toward the cursor using the lerp() functi... Tags: basics, interaction, interpolate, math.
- [Map](../../Examples/Basics/Math/Map) [Beginner] (Math) -- Use the map() function to take any number and scale it to a new number that is more useful for the project that you are working on. For example, use the numbers from the mouse position to control the size or color of a... Tags: basics, interaction, map, math.
- [Noise 1D](../../Examples/Basics/Math/Noise1D) [Beginner] (Math) -- Using 1D Perlin Noise to assign location. Tags: basics, math, noise1d.
- [Noise2D](../../Examples/Basics/Math/Noise2D) [Beginner] (Math) -- Fills the window with two-dimensional Perlin noise, writing one gray value per pixel. The cursor's horizontal position sets the noise falloff, moving the result between smooth clouds and fine grain. Tags: basics, image, math, noise2d.
- [Noise 3D](../../Examples/Basics/Math/Noise3D) [Intermediate] (Math) -- Using 3D noise to create simple animated texture. Here, the third dimension ('z') is treated as time. Tags: basics, math, noise3d.
- [Noise Wave](../../Examples/Basics/Math/NoiseWave) [Intermediate] (Math) -- A wave whose height comes from one-dimensional Perlin noise, drawn as a filled shape that drifts as the noise offset advances. Tags: basics, math, noisewave.
- [Operator Precedence](../../Examples/Basics/Math/OperatorPrecedence) [Beginner] (Math) -- If you don't direction state the order in which an expression is evaluated, it is decided by the operator precedence. For example, in the expression 4+2*8, the 2 will first be multiplied by 8 and then the result will be... Tags: basics, math, operatorprecedence.
- [PolarToCartesian](../../Examples/Basics/Math/PolarToCartesian) [Intermediate] (Math) -- Converts polar coordinates to Cartesian ones with cos() and sin(). A circle orbits the center while its angular velocity slowly accelerates. Tags: basics, math, polartocartesian.
- [Random](../../Examples/Basics/Math/Random) [Beginner] (Math) -- Random numbers create the basis of this image. Each time the program is loaded the result is different. Tags: basics, image, math, random.
- [Random Gaussian](../../Examples/Basics/Math/RandomGaussian) [Beginner] (Math) -- This sketch draws ellipses with x and y locations tied to a gaussian distribution of random numbers. Tags: basics, math, randomgaussian.
- [Sine](../../Examples/Basics/Math/Sine) [Beginner] (Math) -- Smoothly scaling size with the sin() function. Tags: basics, math, sine.
- [Sine Cosine](../../Examples/Basics/Math/SineCosine) [Beginner] (Math) -- Linear movement with sin() and cos(). Numbers between 0 and PI2 (TWO_PI which angles roughly 6.28) are put into these functions and numbers between -1 and 1 are returned. These values are then scaled to produce larger m... Tags: basics, math, sinecosine.
- [Sine Wave](../../Examples/Basics/Math/SineWave) [Beginner] (Math) -- Renders a sine wave as a row of circles, recomputing every y value from sin() each frame so the wave travels sideways. Tags: basics, math, sinewave.
- [Composite Objects](../../Examples/Basics/Objects/CompositeObjects) [Advanced] (Objects) -- An object can include several other objects. Creating such composite objects is a good way to use the principles of modularity and build higher levels of abstraction within a program. Tags: basics, compositeobjects, objects.
- [Inheritance](../../Examples/Basics/Objects/Inheritance) [Advanced] (Objects) -- A class can be defined using another class as a foundation. In object-oriented programming terminology, one class can inherit fi elds and methods from another. An object that inherits from another is called a subclass,... Tags: basics, inheritance, objects.
- [Multiple constructors](../../Examples/Basics/Objects/MultipleConstructors) [Intermediate] (Objects) -- A class can have multiple constructors that assign the fields in different ways. Sometimes it's beneficial to specify every aspect of an object's data by assigning parameters to the fields, but other times it might be a... Tags: basics, multipleconstructors, objects.
- [Objects](../../Examples/Basics/Objects/Objects) [Intermediate] (Objects) -- Four objects, each a group of lines with its own width, spacing and damping, follow the cursor at different speeds. Shows how a class keeps per-instance state. Tags: basics, objects.
- [Disable Style](../../Examples/Basics/Shape/DisableStyle) [Intermediate] (Shape) -- The same retained shape drawn twice. On the left its own fill and stroke are disabled so the sketch's current style applies; on the right it keeps the style it captured when it was built. Tags: basics, disablestyle, shape.
- [Get Child](../../Examples/Basics/Shape/GetChild) [Intermediate] (Shape) -- SVG files can be made of many individual shapes. Each of these shapes (called a "child") has its own name that can be used to extract it from the "parent" file. This example loads a map of the United States and creates... Tags: basics, getchild, shape.
- [Load and Display an OBJ Shape](../../Examples/Basics/Shape/LoadDisplayOBJ) [Intermediate] (Shape) -- The loadShape() command is used to read simple SVG (Scalable Vector Graphics) files and OBJ (Object) files into a Processing sketch. This example loads an OBJ file of a rocket and displays it to the screen. Tags: 3d, basics, loaddisplayobj, shape.
- [Load and Display a Shape](../../Examples/Basics/Shape/LoadDisplaySVG) [Beginner] [stub] (Shape) -- Placeholder for loading and displaying an SVG shape. metaphor has no loadShape() for SVG files, so the sketch draws an explanatory message instead. Tags: basics, loaddisplaysvg, shape.
- [Scale Shape](../../Examples/Basics/Shape/ScaleShape) [Beginner] (Shape) -- Scales a retained star shape by resetting and reapplying its own matrix every frame. The cursor's horizontal position sets the zoom. Tags: basics, scaleshape, shape.
- [Shape Vertices](../../Examples/Basics/Shape/ShapeVertices) [Intermediate] (Shape) -- How to iterate over the vertices of a shape. When loading an obj or SVG, getVertexCount() will typically return 0 since all the vertices are in the child shapes. You should iterate through the children and then iterate... Tags: basics, shape, shapevertices.
- [Coordinates](../../Examples/Basics/Structure/Coordinates) [Beginner] (Structure) -- All shapes drawn to the screen have a position that is specified as a coordinate. All coordinates are measured as the distance from the origin in units of pixels. The origin (0, 0) is the coordinate is in the upper left... Tags: basics, coordinates, image, structure.
- [Create Graphics](../../Examples/Basics/Structure/CreateGraphics) [Intermediate] (Structure) -- The createGraphics() function creates an object from the PGraphics class. PGraphics is the main graphics and rendering context for Processing. The beginDraw() method is necessary to prepare for drawing and endDraw() is... Tags: basics, creategraphics, structure.
- [Functions](../../Examples/Basics/Structure/Functions) [Beginner] (Structure) -- The drawTarget() function makes it easy to draw many distinct targets. Each call to drawTarget() specifies the position, size, and number of rings for each target. Tags: basics, functions, structure.
- [Loop](../../Examples/Basics/Structure/Loop) [Beginner] (Structure) -- If noLoop() is run in setup(), the code in draw() is only run once. In this example, click the mouse to run the loop() function to cause the draw() the run continuously. Tags: basics, interaction, loop, structure.
- [No Loop](../../Examples/Basics/Structure/NoLoop) [Beginner] (Structure) -- The noLoop() function causes draw() to only run once. Without calling noLoop(), the code inside draw() is run continually. Tags: basics, noloop, structure.
- [Recursion](../../Examples/Basics/Structure/Recursion) [Intermediate] (Structure) -- A demonstration of recursion, which means functions call themselves. Notice how the drawCircle() function calls itself at the end of its block. It continues to do this until the variable "level" is equal to 1. Tags: basics, recursion, structure.
- [Redraw](../../Examples/Basics/Structure/Redraw) [Beginner] (Structure) -- The redraw() function makes draw() execute once. In this example, draw() is executed once every time the mouse is clicked. Tags: basics, interaction, redraw, structure.
- [Setup and Draw](../../Examples/Basics/Structure/SetupDraw) [Beginner] (Structure) -- The code inside the draw() function runs continuously from top to bottom until the program is stopped. The code in setup() is run once when the program starts. Tags: basics, setupdraw, structure.
- [Statements and Comments](../../Examples/Basics/Structure/StatementsComments) [Beginner] (Structure) -- Statements are the elements that make up programs. The ";" (semi-colon) symbol is used to end statements. It is called the "statement terminator." Comments are used for making notes to help people better understand prog... Tags: basics, statementscomments, structure.
- [Width and Height](../../Examples/Basics/Structure/WidthHeight) [Beginner] (Structure) -- The 'width' and 'height' variables contain the width and height of the display window as defined in the size() function. Tags: basics, structure, widthheight.
- [Arm](../../Examples/Basics/Transform/Arm) [Beginner] (Transform) -- The angle of each segment is controlled with the mouseX and mouseY position. The transformations applied to the first segment are also applied to the second segment because they are inside the same pushMatrix() and popM... Tags: arm, basics, interaction, transform.
- [Rotate](../../Examples/Basics/Transform/Rotate) [Beginner] (Transform) -- Rotating a square around the Z axis. To get the results you expect, send the rotate function angle parameters that are values between 0 and PI2 (TWO_PI which is roughly 6.28). If you prefer to think about angles as degr... Tags: basics, rotate, transform.
- [Rotate Push Pop](../../Examples/Basics/Transform/RotatePushPop) [Intermediate] (Transform) -- The push() and pop() functions allow for more control over transformations. The push function saves the current coordinate system to the stack and pop() restores the prior coordinate system. Tags: 3d, basics, rotatepushpop, transform.
- [Rotate 1](../../Examples/Basics/Transform/RotateXY) [Intermediate] (Transform) -- Rotating simultaneously in the X and Y axis. Transformation functions such as rotate() are additive. Successively calling rotate(1.0) and rotate(2.0) is equivalent to calling rotate(3.0). Tags: 3d, basics, rotatexy, transform.
- [Scale](../../Examples/Basics/Transform/Scale) [Beginner] (Transform) -- Two squares scaled by a cosine that swings through zero. Shows that scale() multiplies with the current transform and that shapes scale away from the origin. Tags: basics, scale, transform.
- [Translate](../../Examples/Basics/Transform/Translate) [Beginner] (Transform) -- The translate() function allows objects to be moved to any location within the window. The first parameter sets the x-axis offset and the second parameter sets the y-axis offset. Tags: basics, transform, translate.
- [Letters](../../Examples/Basics/Typography/Letters) [Beginner] (Typography) -- Draws letters to the screen. This requires loading a font, setting the font, and then drawing the letters. Tags: basics, letters, typography.
- [Text Rotation](../../Examples/Basics/Typography/TextRotation) [Intermediate] (Typography) -- Draws letters to the screen and rotates them at different angles. Tags: basics, textrotation, typography.
- [Words](../../Examples/Basics/Typography/Words) [Beginner] (Typography) -- The text() function is used for writing words to the screen. The letters can be aligned left, center, or right with the textAlign() function. Tags: basics, typography, words.
- [Camera Switching](../../Examples/Basics/Video/CameraSwitching) [Beginner] (Video) -- Lists the connected cameras with listCaptureDevices() and switches between them with the number keys. Shows explicit device selection via createCapture(device:), the actual capture resolution chosen for the request (act... Tags: basics, cameraswitching, export, video.
- [VideoPlayback](../../Examples/Basics/Video/VideoPlayback) (Video) Tags: basics, export, video, videoplayback.
- [Loading URLs](../../Examples/Basics/Web/EmbeddedLinks) [Intermediate] (Web) -- Click on the button to open a URL in a browser. Tags: basics, embeddedlinks, web.
- [Loading Images](../../Examples/Basics/Web/LoadingImages) [Intermediate] (Web) -- Processing applications can load images from the network. Tags: basics, image, loadingimages, web.

## Demos

- [DepthSort](../../Examples/Demos/Graphics/DepthSort) (Graphics) Tags: 3d, demos, depthsort, graphics.
- [GetTessGroups](../../Examples/Demos/Graphics/GetTessGroups) [obsolete] (Graphics) -- Placeholder for reading back a shape's tessellation. metaphor has no getTessellation() API, so the sketch draws an explanatory message instead. Tags: demos, gettessgroups, graphics.
- [LowLevelGLVboInterleaved](../../Examples/Demos/Graphics/LowLevelGLVboInterleaved) [obsolete] (Graphics) -- Requires raw OpenGL access (beginPGL/endPGL). metaphor is Metal-only and deliberately exposes no OpenGL compatibility layer; non-goal. Tags: demos, graphics, lowlevelglvbointerleaved.
- [LowLevelGLVboSeparate](../../Examples/Demos/Graphics/LowLevelGLVboSeparate) [obsolete] (Graphics) -- Requires raw OpenGL access (beginPGL/endPGL). metaphor is Metal-only and deliberately exposes no OpenGL compatibility layer; non-goal. Tags: demos, graphics, lowlevelglvboseparate.
- [MeshTweening](../../Examples/Demos/Graphics/MeshTweening) [stub] (Graphics) Tags: demos, graphics, meshtweening.
- [MultipleWindows](../../Examples/Demos/Graphics/MultipleWindows) [obsolete] (Graphics) -- Placeholder for driving several windows from one sketch. metaphor runs a single window per Sketch, so the sketch draws an explanatory message instead. Tags: demos, graphics, multiplewindows.
- [Particles](../../Examples/Demos/Graphics/Particles) [stub] (Graphics) Tags: demos, graphics, particles.
- [Patch](../../Examples/Demos/Graphics/Patch) (Graphics) Tags: 3d, demos, graphics, patch.
- [Planets](../../Examples/Demos/Graphics/Planets) (Graphics) Tags: 3d, demos, graphics, planets.
- [Ribbons](../../Examples/Demos/Graphics/Ribbons) [obsolete] (Graphics) -- Placeholder for rendering a protein backbone as ribbons. metaphor has no parser for the PDB molecular data format, so the sketch draws an explanatory message instead. Tags: demos, graphics, ribbons.
- [RotatingArcs](../../Examples/Demos/Graphics/RotatingArcs) (Graphics) Tags: 3d, demos, graphics, rotatingarcs.
- [TessUpdate](../../Examples/Demos/Graphics/TessUpdate) [obsolete] (Graphics) -- Placeholder for updating vertices on an already tessellated shape. metaphor has no setVertex() for tessellated shapes, so the sketch draws an explanatory message instead. Tags: demos, graphics, tessupdate.
- [Trefoil](../../Examples/Demos/Graphics/Trefoil) (Graphics) Tags: 3d, demos, graphics, trefoil.
- [Wiggling](../../Examples/Demos/Graphics/Wiggling) (Graphics) Tags: 3d, demos, graphics, wiggling.
- [Yellowtail](../../Examples/Demos/Graphics/Yellowtail) (Graphics) Tags: demos, graphics, yellowtail.
- [CubicGridImmediate](../../Examples/Demos/Performance/CubicGridImmediate) (Performance) Tags: 3d, cubicgridimmediate, demos, performance.
- [CubicGridRetained](../../Examples/Demos/Performance/CubicGridRetained) [stub] (Performance) Tags: cubicgridretained, demos, performance.
- [DynamicParticlesImmediate](../../Examples/Demos/Performance/DynamicParticlesImmediate) (Performance) Tags: demos, dynamicparticlesimmediate, particles, performance.
- [DynamicParticlesRetained](../../Examples/Demos/Performance/DynamicParticlesRetained) [stub] (Performance) Tags: demos, dynamicparticlesretained, particles, performance.
- [Esfera](../../Examples/Demos/Performance/Esfera) (Performance) Tags: 3d, demos, esfera, performance.
- [LineRendering](../../Examples/Demos/Performance/LineRendering) (Performance) Tags: demos, linerendering, performance.
- [Massive Circles](../../Examples/Demos/Performance/MassiveCircles) [Intermediate] (Performance) -- Draws 100,000 moving circles with the explicit massive drawing API. Uses CircleInstance arrays and a single circles() call instead of thousands of circle() calls. Tags: demos, massivecircles, performance.
- [QuadRendering](../../Examples/Demos/Performance/QuadRendering) (Performance) Tags: demos, performance, quadrendering.
- [StaticParticlesImmediate](../../Examples/Demos/Performance/StaticParticlesImmediate) (Performance) Tags: 3d, demos, particles, performance, staticparticlesimmediate.
- [StaticParticlesRetained](../../Examples/Demos/Performance/StaticParticlesRetained) (Performance) Tags: 3d, demos, particles, performance, staticparticlesretained.
- [TextRendering](../../Examples/Demos/Performance/TextRendering) (Performance) Tags: demos, performance, textrendering, typography.
- [MultipleWindows](../../Examples/Demos/Tests/MultipleWindows) (Tests) Tags: 3d, demos, multiplewindows, tests.
- [NoBackgroundTest](../../Examples/Demos/Tests/NoBackgroundTest) (Tests) Tags: demos, nobackgroundtest, tests.
- [OffscreenTest](../../Examples/Demos/Tests/OffscreenTest) (Tests) Tags: demos, offscreentest, tests.
- [RedrawTest](../../Examples/Demos/Tests/RedrawTest) (Tests) Tags: demos, redrawtest, tests.
- [ResizeTest](../../Examples/Demos/Tests/ResizeTest) (Tests) Tags: demos, resizetest, tests.
- [SpecsTest](../../Examples/Demos/Tests/SpecsTest) [obsolete] (Tests) -- Requires the OpenGL specification-query API. metaphor is Metal-only and exposes no OpenGL introspection; non-goal. Tags: demos, specstest, tests.

## ML

- [FaceDetection](../../Examples/ML/FaceDetection) Tags: facedetection, ml.
- [ImageClassification](../../Examples/ML/ImageClassification) Tags: image, imageclassification, ml.
- [PersonSegmentation](../../Examples/ML/PersonSegmentation) Tags: ml, personsegmentation.
- [StyleTransfer](../../Examples/ML/StyleTransfer) Tags: ml, styletransfer.

## Plugins

- [MetaphorFPSLogger](../../Examples/Plugins/MetaphorFPSLogger) Tags: metaphorfpslogger, plugins.
- [MetaphorMouseTrail](../../Examples/Plugins/MetaphorMouseTrail) Tags: interaction, metaphormousetrail, plugins.

## Samples

- [DynamicMeshTexture](../../Examples/Samples/DynamicMeshTexture) Tags: 3d, dynamicmeshtexture, samples.
- [EnvironmentIBL](../../Examples/Samples/EnvironmentIBL) Tags: 3d, environmentibl, samples.
- [InstancedCubes](../../Examples/Samples/InstancedCubes) Tags: 3d, instancedcubes, samples.
- [OSC Loopback](../../Examples/Samples/OSCLoopback) [Intermediate] -- Sends the mouse position over OSC with OSCSender and draws whatever an OSCReceiver on the same port gets back. Change the host/port to talk to TouchDesigner, Max, or TouchOSC instead of the local loopback. Tags: interaction, live, oscloopback, samples.
- [ParameterPanel](../../Examples/Samples/ParameterPanel) Tags: parameterpanel, samples.
- [PluginFPSLogger](../../Examples/Samples/PluginFPSLogger) Tags: pluginfpslogger, samples.
- [PluginMouseTrail](../../Examples/Samples/PluginMouseTrail) Tags: interaction, pluginmousetrail, samples.
- [ProbeBenchmark](../../Examples/Samples/ProbeBenchmark) Tags: 3d, probebenchmark, samples.
- [ProbeSnapshot](../../Examples/Samples/ProbeSnapshot) Tags: probesnapshot, samples.
- [RayTracing](../../Examples/Samples/RayTracing) Tags: raytracing, samples.
- [RenderGraphCompose](../../Examples/Samples/RenderGraphCompose) Tags: rendergraphcompose, samples, shader.
- [SVG Export](../../Examples/Samples/SVGExport) [Intermediate] -- Generative line art for pen plotters (AxiDraw). Press S to save the current frame as a true vector SVG via beginSVGRecord()/endSVGRecord() — the file is generated from the same draw calls as the raster output, so what y... Tags: export, interaction, samples, svgexport.
- [SceneGraphBasics](../../Examples/Samples/SceneGraphBasics) Tags: 3d, samples, scenegraphbasics.
- [SceneGraphHybrid](../../Examples/Samples/SceneGraphHybrid) Tags: 3d, samples, scenegraphhybrid.
- [StatePreservation](../../Examples/Samples/StatePreservation) Tags: samples, statepreservation.
- [ToneMapping](../../Examples/Samples/ToneMapping) Tags: 3d, samples, tonemapping.

## Topics

- [ArrayList of objects](../../Examples/Topics/Advanced%20Data/ArrayListClass) [Advanced] (Advanced Data) -- Balls are appended to an array as they are created and removed once their life runs out, showing how to grow and shrink a collection while iterating over it. Tags: advanced-data, arraylistclass, topics.
- [CountingStrings](../../Examples/Topics/Advanced%20Data/CountingStrings) (Advanced Data) Tags: advanced-data, countingstrings, topics.
- [HashMapClass](../../Examples/Topics/Advanced%20Data/HashMapClass) (Advanced Data) Tags: advanced-data, hashmapclass, topics.
- [IntList Lottery](../../Examples/Topics/Advanced%20Data/IntListLottery) [Advanced] (Advanced Data) -- A lottery drawn from a shuffled list of integers. Numbers move from the pool into the results, and the ones matching the ticket are highlighted. Tags: advanced-data, intlistlottery, topics.
- [Loading JSON Data](../../Examples/Topics/Advanced%20Data/LoadSaveJSON) [Advanced] (Advanced Data) -- Loads bubbles from a JSON file and rebuilds them as objects. Clicking adds a bubble, writes the file back out and reloads it. Tags: advanced-data, loadsavejson, topics.
- [Loading Tabular Data](../../Examples/Topics/Advanced%20Data/LoadSaveTable) [Advanced] (Advanced Data) -- Loads bubbles from a CSV table and rebuilds them as objects. Clicking adds a row, writes the table back out and reloads it. Tags: advanced-data, loadsavetable, topics.
- [LoadSaveXML](../../Examples/Topics/Advanced%20Data/LoadSaveXML) [obsolete] (Advanced Data) -- Placeholder for reading and writing XML. metaphor has no loadXML() or saveXML(), so the sketch draws an explanatory message instead. Tags: advanced-data, loadsavexml, topics.
- [Regex](../../Examples/Topics/Advanced%20Data/Regex) (Advanced Data) Tags: advanced-data, regex, topics.
- [Threads](../../Examples/Topics/Advanced%20Data/Threads) (Advanced Data) Tags: advanced-data, threads, topics.
- [XMLYahooWeather](../../Examples/Topics/Advanced%20Data/XMLYahooWeather) [obsolete] (Advanced Data) -- Placeholder for fetching a weather feed as XML. metaphor has neither loadXML() nor the network access this needs, so the sketch draws an explanatory message instead. Tags: advanced-data, topics, xmlyahooweather.
- [Animated Sprite (Shifty + Teddy)](../../Examples/Topics/Animation/AnimatedSprite) [Intermediate] (Animation) -- Two sprite animations play at once from arrays of generated frames. One follows the cursor with drag while the other advances in place. Tags: animatedsprite, animation, image, interaction, topics.
- [Sequential](../../Examples/Topics/Animation/Sequential) [Intermediate] (Animation) -- Plays a generated twelve-frame sequence by drawing one image per frame, the simplest form of sequential animation. Tags: animation, image, sequential, topics.
- [Game of Life](../../Examples/Topics/Cellular%20Automata/GameOfLife) [Advanced] (Cellular Automata) -- Conway's Game of Life on a grid of cells. The space bar pauses so cells can be toggled with the mouse, 'r' randomizes the grid and 'c' clears it. Tags: cellular-automata, gameoflife, interaction, topics.
- [Spore1](../../Examples/Topics/Cellular%20Automata/Spore1) (Cellular Automata) Tags: cellular-automata, spore1, topics.
- [Spore2](../../Examples/Topics/Cellular%20Automata/Spore2) (Cellular Automata) Tags: cellular-automata, spore2, topics.
- [Wolfram Cellular Automata](../../Examples/Topics/Cellular%20Automata/Wolfram) [Advanced] (Cellular Automata) -- A one-dimensional Wolfram cellular automaton. Each generation is drawn as one row of pixels, and a new rule set is picked once the rows fill the window. Tags: cellular-automata, image, topics, wolfram.
- [BeginEndContour](../../Examples/Topics/Create%20Shapes/BeginEndContour) (Create Shapes) Tags: beginendcontour, create-shapes, topics.
- [GroupPShape](../../Examples/Topics/Create%20Shapes/GroupPShape) (Create Shapes) Tags: create-shapes, grouppshape, topics.
- [ParticleSystemPShape](../../Examples/Topics/Create%20Shapes/ParticleSystemPShape) [stub] (Create Shapes) Tags: create-shapes, particles, particlesystempshape, topics.
- [PathPShape](../../Examples/Topics/Create%20Shapes/PathPShape) (Create Shapes) Tags: create-shapes, pathpshape, topics.
- [PolygonPShape](../../Examples/Topics/Create%20Shapes/PolygonPShape) (Create Shapes) Tags: create-shapes, polygonpshape, topics.
- [PolygonPShapeOOP](../../Examples/Topics/Create%20Shapes/PolygonPShapeOOP) (Create Shapes) Tags: create-shapes, polygonpshapeoop, topics.
- [PolygonPShapeOOP2](../../Examples/Topics/Create%20Shapes/PolygonPShapeOOP2) (Create Shapes) Tags: create-shapes, polygonpshapeoop2, topics.
- [PolygonPShapeOOP3](../../Examples/Topics/Create%20Shapes/PolygonPShapeOOP3) (Create Shapes) Tags: create-shapes, polygonpshapeoop3, topics.
- [PrimitivePShape](../../Examples/Topics/Create%20Shapes/PrimitivePShape) (Create Shapes) Tags: create-shapes, primitivepshape, topics.
- [WigglePShape](../../Examples/Topics/Create%20Shapes/WigglePShape) (Create Shapes) Tags: create-shapes, topics, wigglepshape.
- [ArcLengthParametrization](../../Examples/Topics/Curves/ArcLengthParametrization) (Curves) Tags: arclengthparametrization, curves, topics.
- [Continuous Lines](../../Examples/Topics/Drawing/ContinuousLines) [Beginner] (Drawing) -- Click and drag the mouse to draw a line. Tags: continuouslines, drawing, interaction, topics.
- [Patterns](../../Examples/Topics/Drawing/Pattern) [Intermediate] (Drawing) -- Move the cursor over the image to draw with a software tool which responds to the speed of the mouse. Tags: drawing, image, interaction, pattern, topics.
- [Pulses](../../Examples/Topics/Drawing/Pulses) (Drawing) -- Software drawing instruments can follow a rhythm or abide by rules independent of drawn gestures. This is a form of collaborative drawing in which the draftsperson controls some aspects of the image and the software con... Tags: drawing, image, interaction, pulses, topics.
- [DirectoryList](../../Examples/Topics/File%20IO/DirectoryList) (File IO) Tags: directorylist, file-io, topics.
- [Drop Image](../../Examples/Topics/File%20IO/DropImage) [Intermediate] (File IO) -- Drag and drop an image file onto the window to display it, or click to open it with a selectInput() file dialog. Demonstrates the fileDropped() callback and the selectInput() dialog. Tags: dropimage, file-io, image, interaction, topics.
- [LoadFile 1](../../Examples/Topics/File%20IO/LoadFile1) [Intermediate] (File IO) -- Loads a text file that contains two numbers separated by a tab ('\t'). A new pair of numbers is loaded each frame and used to draw a point on the screen. Tags: file-io, loadfile1, topics, typography.
- [LoadFile 2](../../Examples/Topics/File%20IO/LoadFile2) [Intermediate] (File IO) -- This example loads a data file about cars. Each element is separated with a tab and corresponds to a different aspect of each car. The file stores the miles per gallon, cylinders, displacement, etc., for more than 400 d... Tags: file-io, interaction, loadfile2, topics, typography.
- [SaveFile1](../../Examples/Topics/File%20IO/SaveFile1) (File IO) Tags: file-io, savefile1, topics.
- [SaveFile2](../../Examples/Topics/File%20IO/SaveFile2) (File IO) Tags: file-io, savefile2, topics.
- [SaveFrames](../../Examples/Topics/File%20IO/SaveFrames) (File IO) Tags: file-io, saveframes, topics.
- [SaveOneImage](../../Examples/Topics/File%20IO/SaveOneImage) [Intermediate] (File IO) -- The save() function saves an image from the display window. Here it runs when a mouse button is pressed and writes output/line.png, relative to the launch directory. metaphor writes PNG, not Processing's TIFF. Tags: file-io, image, interaction, saveoneimage, topics.
- [TileImages](../../Examples/Topics/File%20IO/TileImages) (File IO) Tags: file-io, image, tileimages, topics.
- [Koch Curve](../../Examples/Topics/Fractals%20and%20L-Systems/Koch) [Advanced] (Fractals and L-Systems) -- Builds the Koch curve by repeatedly replacing every line segment with four shorter ones. Tags: fractals-and-l-systems, koch, topics.
- [The Mandelbrot Set](../../Examples/Topics/Fractals%20and%20L-Systems/Mandelbrot) [Intermediate] (Fractals and L-Systems) -- Renders the Mandelbrot set once into the pixel buffer, iterating each pixel's complex coordinate until it escapes. Tags: fractals-and-l-systems, image, mandelbrot, topics.
- [Penrose Snowflake](../../Examples/Topics/Fractals%20and%20L-Systems/PenroseSnowflake) [Advanced] (Fractals and L-Systems) -- Draws a Penrose snowflake from an L-system. A production string is expanded through four generations, then walked with translate() and rotate(). Tags: fractals-and-l-systems, penrosesnowflake, topics.
- [Penrose Tile L-System](../../Examples/Topics/Fractals%20and%20L-Systems/PenroseTile) [Advanced] (Fractals and L-Systems) -- A Penrose tiling grown from a four-rule L-system, drawn by walking the expanded production string with translate() and rotate(). Tags: fractals-and-l-systems, penrosetile, topics.
- [Pentigree L-System](../../Examples/Topics/Fractals%20and%20L-Systems/Pentigree) [Advanced] (Fractals and L-Systems) -- A pentigree curve grown from a single L-system rule, drawn segment by segment with translate() and rotate(). Tags: fractals-and-l-systems, pentigree, topics.
- [Recursive Tree](../../Examples/Topics/Fractals%20and%20L-Systems/Tree) [Intermediate] (Fractals and L-Systems) -- A recursive branching tree. Every branch draws a shorter pair of children on either side, and the cursor's horizontal position sets the branching angle. Tags: fractals-and-l-systems, topics, tree.
- [Button](../../Examples/Topics/GUI/Button) [Intermediate] (GUI) -- Click on one of the colored shapes in the center of the image to change the color of the background. Tags: button, gui, image, interaction, topics.
- [Handles](../../Examples/Topics/GUI/Handles) [Intermediate] (GUI) -- Click and drag the white boxes to change their position. Tags: gui, handles, interaction, topics.
- [Rollover](../../Examples/Topics/GUI/Rollover) [Intermediate] (GUI) -- Roll over the colored squares in the center of the image to change the color of the outside rectangle. Tags: gui, image, rollover, topics.
- [Scrollbar](../../Examples/Topics/GUI/Scrollbar) [Advanced] (GUI) -- Move the scrollbars left and right to change the positions of the images. Tags: gui, image, scrollbar, topics.
- [Icosahedra](../../Examples/Topics/Geometry/Icosahedra) (Geometry) Tags: 3d, geometry, icosahedra, topics.
- [NoiseSphere](../../Examples/Topics/Geometry/NoiseSphere) (Geometry) Tags: 3d, geometry, noisesphere, topics.
- [RGBCube](../../Examples/Topics/Geometry/RGBCube) (Geometry) Tags: 3d, geometry, rgbcube, topics.
- [ShapeTransform](../../Examples/Topics/Geometry/ShapeTransform) (Geometry) Tags: 3d, geometry, shapetransform, topics.
- [SpaceJunk](../../Examples/Topics/Geometry/SpaceJunk) (Geometry) Tags: 3d, geometry, spacejunk, topics.
- [Toroid](../../Examples/Topics/Geometry/Toroid) (Geometry) Tags: 3d, geometry, topics, toroid.
- [Vertices](../../Examples/Topics/Geometry/Vertices) (Geometry) Tags: 3d, geometry, topics, vertices.
- [Blending](../../Examples/Topics/Image%20Processing/Blending) (Image Processing) Tags: blending, image, image-processing, topics.
- [Blur](../../Examples/Topics/Image%20Processing/Blur) [Intermediate] (Image Processing) -- A low-pass filter blurs an image. This program analyzes every pixel in an image and blends it with the neighboring pixels to blur the image. Tags: blur, image, image-processing, topics.
- [Brightness pixels](../../Examples/Topics/Image%20Processing/BrightnessPixels) [Intermediate] (Image Processing) -- Reads a source image's pixels and redraws them, brightening each pixel by how close it is to the cursor. Tags: brightnesspixels, image, image-processing, topics.
- [Convolution](../../Examples/Topics/Image%20Processing/Convolution) [Advanced] (Image Processing) -- Applies a 3x3 convolution kernel to a square region of an image that follows the cursor. Clicking cycles through blur, sharpen, edge detection and other kernels. Tags: convolution, image, image-processing, topics.
- [Edge Detection](../../Examples/Topics/Image%20Processing/EdgeDetection) [Advanced] (Image Processing) -- A high-pass filter sharpens an image. This program analyzes every pixel in an image in relation to the neighboring pixels to sharpen the image. Tags: edgedetection, image, image-processing, topics.
- [Explode](../../Examples/Topics/Image%20Processing/Explode) (Image Processing) Tags: 3d, explode, image, image-processing, topics.
- [Extrusion](../../Examples/Topics/Image%20Processing/Extrusion) (Image Processing) Tags: 3d, extrusion, image, image-processing, topics.
- [Histogram](../../Examples/Topics/Image%20Processing/Histogram) [Intermediate] (Image Processing) -- Calculates the histogram of an image. A histogram is the frequency distribution of the gray levels with the number of pure black values displayed on the left and number of pure white values on the right. Note that this... Tags: histogram, image, image-processing, topics.
- [LinearImage](../../Examples/Topics/Image%20Processing/LinearImage) (Image Processing) Tags: image, image-processing, linearimage, topics.
- [Pixel Array](../../Examples/Topics/Image%20Processing/PixelArray) [Intermediate] (Image Processing) -- Click and drag the mouse up and down to control the signal and press and hold any key to see the current pixel being read. This program sequentially reads the color of every pixel of an image and displays this color to... Tags: image, image-processing, interaction, pixelarray, topics.
- [Sharpen](../../Examples/Topics/Image%20Processing/Sharpen) (Image Processing) Tags: image, image-processing, sharpen, topics.
- [Zoom](../../Examples/Topics/Image%20Processing/Zoom) (Image Processing) Tags: 3d, image, image-processing, topics, zoom.
- [Follow 1](../../Examples/Topics/Interaction/Follow1) [Intermediate] (Interaction) -- A single segment follows the cursor, its angle solved with atan2(). Tags: follow1, interaction, topics.
- [Follow 2](../../Examples/Topics/Interaction/Follow2) [Intermediate] (Interaction) -- Two segments follow the cursor in a chain, each one dragging the next along by its own length. Tags: follow2, interaction, topics.
- [Follow 3](../../Examples/Topics/Interaction/Follow3) [Intermediate] (Interaction) -- Twenty short segments trail the cursor, each dragged along by the one before it. Tags: follow3, interaction, topics.
- [Reach 1](../../Examples/Topics/Interaction/Reach1) [Intermediate] (Interaction) -- A two-segment arm reaches toward the cursor, with the angles solved by atan2() and the base pinned in place. Tags: interaction, reach1, topics.
- [Reach 2](../../Examples/Topics/Interaction/Reach2) [Intermediate] (Interaction) -- A ten-segment arm anchored at the bottom of the window reaches for the cursor. Tags: interaction, reach2, topics.
- [Reach 3](../../Examples/Topics/Interaction/Reach3) [Intermediate] (Interaction) -- An eight-segment arm reaches for a ball that bounces around the window on its own. Tags: interaction, physics, reach3, topics.
- [Tickle](../../Examples/Topics/Interaction/Tickle) [Intermediate] (Interaction) -- The word "tickle" jitters when the cursor hovers over. Sometimes, it can be tickled off the screen. Tags: interaction, tickle, topics, typography.
- [Bounce](../../Examples/Topics/Motion/Bounce) [Intermediate] (Motion) -- When the shape hits the edge of the window, it reverses its direction. Tags: bounce, motion, physics, topics.
- [Bouncy Bubbles](../../Examples/Topics/Motion/BouncyBubbles) [Intermediate] (Motion) -- Twelve circles fall under gravity and push each other apart with a spring force wherever they overlap. Tags: bouncybubbles, motion, physics, topics.
- [Brownian motion](../../Examples/Topics/Motion/Brownian) [Intermediate] (Motion) -- Recording random movement as a continuous line. Tags: brownian, export, motion, topics.
- [Circle Collision with Swapping Velocities](../../Examples/Topics/Motion/CircleCollision) [Advanced] (Motion) -- Circles collide elastically, swapping velocities along the axis between their centers with each circle's mass taken from its radius. Tags: circlecollision, motion, physics, topics.
- [CubesWithinCube](../../Examples/Topics/Motion/CubesWithinCube) (Motion) Tags: 3d, cubeswithincube, motion, topics.
- [Linear Motion](../../Examples/Topics/Motion/Linear) [Beginner] (Motion) -- Changing a variable to create a moving line. When the line moves off the edge of the window, the variable is set to 0, which places the line back at the bottom of the screen. Tags: linear, motion, topics.
- [Morph](../../Examples/Topics/Motion/Morph) [Advanced] (Motion) -- Changing one shape into another by interpolating vertices from one to another Tags: morph, motion, topics.
- [Moving On Curves](../../Examples/Topics/Motion/MovingOnCurves) [Intermediate] (Motion) -- In this example, the circles moves along the curve y = x^4. Click the mouse to have it move to a new position. Tags: interaction, motion, movingoncurves, topics.
- [Non-orthogonal Reflection](../../Examples/Topics/Motion/Reflection1) [Advanced] (Motion) -- A particle bounces off a single sloped ground line, reflecting its velocity around the surface normal. Tags: motion, particles, physics, reflection1, topics.
- [Non-orthogonal Collision with Multiple Ground Segments](../../Examples/Topics/Motion/Reflection2) [Advanced] (Motion) -- A particle bounces across a ground built from many sloped segments, reflecting off whichever segment it lands on. Tags: motion, particles, physics, reflection2, topics.
- [BlurFilter](../../Examples/Topics/Shaders/BlurFilter) (Shaders) Tags: blurfilter, cpu-approximation, image, shaders, topics.
- [Conway](../../Examples/Topics/Shaders/Conway) (Shaders) Tags: conway, cpu-approximation, shaders, topics.
- [CustomBlend](../../Examples/Topics/Shaders/CustomBlend) (Shaders) Tags: cpu-approximation, customblend, shaders, topics.
- [Custom Shader 2D](../../Examples/Topics/Shaders/CustomShader2D) [Intermediate] (Shaders) -- Apply a custom Metal fragment shader to 2D shapes. loadShader() reads the MSL file, shader() applies it so rect()/circle() become surfaces the shader runs on, and resetShader() goes back to the built-in shader. Built-in... Tags: customshader2d, interaction, shader, shaders, topics.
- [Deform](../../Examples/Topics/Shaders/Deform) (Shaders) Tags: cpu-approximation, deform, shaders, topics.
- [DomeProjection](../../Examples/Topics/Shaders/DomeProjection) [obsolete] (Shaders) -- Requires cubemap-based dome projection rendering, not on metaphor's roadmap; non-goal for now. Tags: domeprojection, shaders, topics.
- [EdgeDetect](../../Examples/Topics/Shaders/EdgeDetect) (Shaders) Tags: cpu-approximation, edgedetect, shaders, topics.
- [EdgeFilter](../../Examples/Topics/Shaders/EdgeFilter) (Shaders) Tags: 3d, cpu-approximation, edgefilter, image, shaders, topics.
- [GlossyFishEye](../../Examples/Topics/Shaders/GlossyFishEye) (Shaders) Tags: 3d, cpu-approximation, glossyfisheye, shaders, topics.
- [ImageMask](../../Examples/Topics/Shaders/ImageMask) (Shaders) Tags: cpu-approximation, image, imagemask, shaders, topics.
- [InfiniteTiles](../../Examples/Topics/Shaders/InfiniteTiles) (Shaders) Tags: cpu-approximation, infinitetiles, shaders, topics.
- [Landscape](../../Examples/Topics/Shaders/Landscape) (Shaders) Tags: cpu-approximation, landscape, shaders, topics.
- [Monjori](../../Examples/Topics/Shaders/Monjori) (Shaders) Tags: cpu-approximation, monjori, shaders, topics.
- [Nebula](../../Examples/Topics/Shaders/Nebula) (Shaders) Tags: cpu-approximation, nebula, shaders, topics.
- [SepBlur](../../Examples/Topics/Shaders/SepBlur) (Shaders) Tags: cpu-approximation, sepblur, shaders, topics.
- [ToonShading](../../Examples/Topics/Shaders/ToonShading) (Shaders) Tags: 3d, shader, shaders, toonshading, topics.
- [Flocking](../../Examples/Topics/Simulate/Flocking) [Advanced] (Simulate) -- 150 boids steer by three rules at once, separation, alignment and cohesion, which together produce flocking motion. Tags: flocking, simulate, topics.
- [Forces (Gravity and Fluid Resistence) with Vectors](../../Examples/Topics/Simulate/ForcesWithVectors) [Advanced] (Simulate) -- Movers fall under gravity and slow down when they enter the liquid at the bottom, where fluid resistance grows with the square of their speed. Tags: forceswithvectors, physics, simulate, topics.
- [GravitationalAttraction3D](../../Examples/Topics/Simulate/GravitationalAttraction3D) (Simulate) Tags: 3d, gravitationalattraction3d, simulate, topics.
- [Multiple Particle Systems](../../Examples/Topics/Simulate/MultipleParticleSystems) [Advanced] (Simulate) -- Clicking spawns another particle system. Each one emits its own particles, some of which wander off along a noisy path. Tags: multipleparticlesystems, particles, simulate, topics.
- [Simple Particle System](../../Examples/Topics/Simulate/SimpleParticleSystem) [Intermediate] (Simulate) -- One emitter releases particles that fall under gravity and fade out as their lifespan runs down. Tags: particles, physics, simpleparticlesystem, simulate, topics.
- [Smoke Particle System](../../Examples/Topics/Simulate/SmokeParticleSystem) [Advanced] (Simulate) -- Textured particles rise like smoke, blown sideways by a wind force that the cursor's horizontal position controls. Tags: image, particles, simulate, smokeparticlesystem, topics.
- [SoftBody](../../Examples/Topics/Simulate/SoftBody) (Simulate) Tags: simulate, softbody, topics.
- [Auto Subsystems (lifecycle)](../../Examples/Topics/Subsystems/AutoSubsystems) [Intermediate] (Subsystems) -- Registers a Physics2D world as a SketchSubsystem with AutoSubsystemManager so its per-frame step() is driven automatically — draw() only renders. Demonstrates the opt-in subsystem lifecycle (audio/video/physics also con... Tags: audio, autosubsystems, export, physics, subsystems, topics, video.
- [TextureCube](../../Examples/Topics/Textures/TextureCube) (Textures) Tags: 3d, texturecube, textures, topics.
- [TextureCylinder](../../Examples/Topics/Textures/TextureCylinder) (Textures) Tags: 3d, texturecylinder, textures, topics.
- [TextureQuad](../../Examples/Topics/Textures/TextureQuad) (Textures) Tags: 3d, texturequad, textures, topics.
- [TextureSphere](../../Examples/Topics/Textures/TextureSphere) (Textures) Tags: 3d, textures, texturesphere, topics.
- [TextureTriangle](../../Examples/Topics/Textures/TextureTriangle) (Textures) Tags: 3d, textures, texturetriangle, topics.
- [Text Particles](../../Examples/Topics/Typography/TextParticles) [Intermediate] (Typography) -- Generative typography with textToPoints(). Glyph outlines become a point cloud that particles fly into; textToContours() draws the same outlines as strokes behind them. Move the mouse to push the particles away and watc... Tags: interaction, particles, textparticles, topics, typography.
- [Acceleration with Vectors](../../Examples/Topics/Vectors/AccelerationWithVectors) [Advanced] (Vectors) -- A circle accelerates toward the cursor. The vector from its position to the mouse is rescaled with setMag(), and the resulting velocity is capped with limit(). Tags: accelerationwithvectors, interaction, topics, vectors.
- [Bouncing Ball with Vectors](../../Examples/Topics/Vectors/BouncingBall) [Intermediate] (Vectors) -- A ball bounces inside the window with its position, velocity and gravity each held as a vector. Tags: bouncingball, physics, topics, vectors.
- [Vector](../../Examples/Topics/Vectors/VectorMath) [Intermediate] (Vectors) -- Draws a vector from the center of the window toward the cursor, rescaled to a fixed length with setMag(). Tags: topics, vectormath, vectors.
