import Testing
import Foundation
@testable import Apus

// MARK: - Test Helpers

/// Returns a font that should be available on the current platform
func getTestFont() throws -> Font {
    // Try common fonts in order of cross-platform availability
    let families = ["Arial", "DejaVu Sans", "Liberation Sans", "FreeSans", "Helvetica"]

    for family in families {
        if let match = try? FontRepository.matchForFont(family: family, style: nil) {
            return try Font(data: match.data)
        }
    }

    throw TestError.noFontAvailable
}

/// Returns font data for testing
func getTestFontData() throws -> Data {
    let families = ["Arial", "DejaVu Sans", "Liberation Sans", "FreeSans", "Helvetica"]

    for family in families {
        if let match = try? FontRepository.matchForFont(family: family, style: nil) {
            return match.data
        }
    }

    throw TestError.noFontAvailable
}

/// Creates a temporary font file for path-based tests
func withTemporaryFontFile<T>(_ body: (String) throws -> T) throws -> T {
    let data = try getTestFontData()
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("test-font-\(UUID().uuidString).ttf")

    try data.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    return try body(tempFile.path)
}

enum TestError: Error {
    case noFontAvailable
}

// MARK: - Font Loading Tests

@Test func loadFontFromPath() throws {
    try withTemporaryFontFile { path in
        let font = try Font(path: path)
        #expect(!font.familyName.isEmpty)
    }
}

@Test func loadFontFromData() throws {
    let data = try getTestFontData()
    let font = try Font(data: data)
    #expect(!font.familyName.isEmpty)
}

@Test func loadFontByFamily() throws {
    let font = try getTestFont()
    let glyphs = font.glyphs(for: "Test")

    #expect(glyphs.count == 4)
    for glyph in glyphs {
        #expect(!glyph.path.isEmpty)
    }
}

@Test func systemFontLookupIsAvailable() {
    #expect(Font.isSystemFontLookupAvailable)
}

// MARK: - Text Shaping Tests

@Test func shapeSimpleText() throws {
    let font = try getTestFont()
    let glyphs = font.glyphs(for: "Hello")

    // "Hello" should produce 5 glyphs
    #expect(glyphs.count == 5)

    // Each glyph should have a non-empty path
    for glyph in glyphs {
        #expect(!glyph.path.isEmpty)
    }

    // Positions should be increasing (for LTR text)
    for i in 1..<glyphs.count {
        #expect(glyphs[i].position.x > glyphs[i-1].position.x)
    }
}

@Test func glyphPathElements() throws {
    let font = try getTestFont()
    let glyphs = font.glyphs(for: "O")

    #expect(glyphs.count == 1)

    let path = glyphs[0].path
    #expect(!path.isEmpty)

    // The letter "O" should have moveTo, curves, and close
    var hasMoveTo = false
    var hasClose = false

    for element in path.elements {
        switch element {
        case .moveTo: hasMoveTo = true
        case .close: hasClose = true
        default: break
        }
    }

    #expect(hasMoveTo)
    #expect(hasClose)
}

@Test func positionedPath() throws {
    let font = try getTestFont()
    let glyphs = font.glyphs(for: "AB")

    #expect(glyphs.count == 2)

    // Second glyph's positioned path should have different coordinates than its raw path
    let secondGlyph = glyphs[1]
    #expect(secondGlyph.position.x > 0)

    let rawPath = secondGlyph.path
    let positionedPath = secondGlyph.positionedPath

    // The positioned path should be translated
    if case .moveTo(let rawPoint) = rawPath.elements.first,
       case .moveTo(let posPoint) = positionedPath.elements.first {
        #expect(posPoint.x > rawPoint.x)
    }
}

// MARK: - Font Metrics Tests

@Test func fontMetrics() throws {
    let font = try getTestFont()

    // Font metrics should have sensible values
    #expect(font.metrics.ascender > 0)
    #expect(font.metrics.descender < 0) // Descender is negative
    #expect(font.metrics.lineHeight > 0)
    #expect(font.metrics.unitsPerEM > 0)

    // Line extent should be ascender - descender
    #expect(font.metrics.lineExtent > font.metrics.ascender)
}

@Test func fontFamilyAndStyleNames() throws {
    let font = try getTestFont()

    #expect(!font.familyName.isEmpty)
    #expect(!font.styleName.isEmpty)
}

// MARK: - Face Enumeration Tests

@Test func enumerateFacesFromData() throws {
    let data = try getTestFontData()
    let faces = try Font.faces(in: data)

    // Should have at least one face
    #expect(faces.count >= 1)
    #expect(!faces[0].familyName.isEmpty)
}

@Test func enumerateFacesFromPath() throws {
    try withTemporaryFontFile { path in
        let faces = try Font.faces(atPath: path)

        #expect(faces.count >= 1)
        #expect(!faces[0].familyName.isEmpty)
    }
}

@Test func loadFaceByFamilyFromData() throws {
    let data = try getTestFontData()
    let faces = try Font.faces(in: data)

    // Load the font using the discovered family name
    let font = try Font(data: data, family: faces[0].familyName)

    #expect(font.familyName == faces[0].familyName)
}
