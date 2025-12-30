import Testing
@testable import Apus

@Test func harfbuzzVersion() {
    let version = Apus.harfbuzzVersion()
    #expect(version == "12.3.0")
}

@Test func freetypeVersion() {
    let version = Apus.freetypeVersion()
    #expect(version.major == 2)
    #expect(version.minor >= 13)
}

@Test func verify() {
    #expect(Apus.verify())
}

@Test func loadFont() throws {
    // Use Helvetica which should be available on macOS
    let font = try Font(path: "/System/Library/Fonts/Helvetica.ttc")
    _ = font // Just verify it loads
}

@Test func shapeSimpleText() throws {
    let font = try Font(path: "/System/Library/Fonts/Helvetica.ttc")
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
    let font = try Font(path: "/System/Library/Fonts/Helvetica.ttc")
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
    let font = try Font(path: "/System/Library/Fonts/Helvetica.ttc")
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
