# Apus

A Swift library for text shaping and font handling, wrapping [FreeType](https://freetype.org) and [HarfBuzz](https://harfbuzz.github.io).

Apus provides cross-platform font loading, advanced text shaping with OpenType feature support, and glyph path extraction for rendering text as vector graphics.

## Features

- **Font loading** from files, binary data, or system fonts (by family name)
- **Text shaping** with HarfBuzz for proper glyph positioning, ligatures, and kerning
- **RTL and complex script support** with automatic direction detection
- **OpenType features** like small caps, stylistic sets, and numeral styles
- **Glyph path extraction** as vector paths for custom rendering
- **Font metrics** for text layout (ascender, descender, line height)
- **Font collection support** for `.ttc` files with multiple faces

## Supported Platforms

- macOS / iOS (CoreText for system font lookup)
- Linux (Fontconfig for system font lookup, optional)
- Windows (GDI for system font lookup)

## Installation

Add Apus to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tomasf/Apus.git", branch: "master")
]
```

Then add it as a dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Apus"]
)
```

### Linux

On Linux, Fontconfig support is enabled by default for system font lookup. Install the development package:

```bash
# Debian/Ubuntu
sudo apt install libfontconfig1-dev
```

To disable Fontconfig, use the trait system:

```swift
.package(url: "https://github.com/tomasf/Apus.git", branch: "master", traits: [])
```

## Usage

### Loading Fonts

```swift
import Apus

// From system fonts (by family name)
let font = try Font(family: "Helvetica", style: "Bold")

// From a file
let font = try Font(path: "/path/to/font.ttf")

// From data
let font = try Font(data: fontData)

// Check if system font lookup is available
if Font.isSystemFontLookupAvailable {
    // ...
}
```

### Shaping Text

```swift
let font = try Font(family: "Arial")
let glyphs = font.glyphs(for: "Hello, World!")

for glyph in glyphs {
    // glyph.path - Vector path for the glyph outline
    // glyph.position - Where to place this glyph
    // glyph.advance - Distance to next glyph
    // glyph.cluster - Groups glyphs from the same source character(s)

    // Get the path already translated to its position
    let finalPath = glyph.positionedPath
}
```

### OpenType Features

```swift
// Shape with specific OpenType features
let glyphs = font.glyphs(for: "Hello 123", features: [
    .smallCaps,           // smcp
    .oldStyleNumerals,    // onum
    .noStandardLigatures  // liga=0
])

// List available features in a font
let features = font.availableFeatures  // ["calt", "kern", "liga", "smcp", ...]

// Create custom features
let feature = OpenTypeFeature(tag: "ss01")  // Stylistic Set 1
let disabled = OpenTypeFeature.disabled("liga")
```

Available feature presets include:
- **Ligatures**: `.standardLigatures`, `.discretionaryLigatures`, `.contextualAlternates`
- **Case**: `.smallCaps`, `.capsToSmallCaps`, `.petiteCaps`
- **Numerals**: `.oldStyleNumerals`, `.liningNumerals`, `.tabularNumerals`, `.proportionalNumerals`, `.slashedZero`
- **Position**: `.superscript`, `.subscript`, `.ordinals`, `.fractions`
- **Stylistic**: `.swash`, `.titling`, `.stylisticSet(1...20)`, `.characterVariant(1...99)`
- **Kerning**: `.kerning`, `.noKerning`

### Font Metrics

```swift
let metrics = font.metrics

metrics.ascender    // Height above baseline
metrics.descender   // Depth below baseline (negative)
metrics.lineHeight  // Recommended line spacing
metrics.lineExtent  // Total vertical extent (ascender - descender)
metrics.unitsPerEM  // Font design units per em
```

### Font Collections

For `.ttc` files containing multiple font faces:

```swift
// List all faces in a font file
let faces = try Font.faces(atPath: "/path/to/fonts.ttc")
for face in faces {
    print("\(face.familyName) - \(face.styleName)")
}

// Load a specific face by family/style
let font = try Font(data: fontData, family: "Helvetica", style: "Bold")
```

### Cluster Information

Glyphs include cluster values for proper text handling:

```swift
let glyphs = font.glyphs(for: "café")

// Glyphs from the same source character share the same cluster value
// Useful for:
// - Applying tracking without separating combining marks from base letters
// - Mapping glyph positions back to text for selection/cursor placement

var lastCluster: UInt32? = nil
for glyph in glyphs {
    if glyph.cluster != lastCluster {
        // New character cluster started
    }
    lastCluster = glyph.cluster
}
```

## License

MIT
