internal import freetype
internal import harfbuzz

extension Font {
    // MARK: - Text Shaping

    /// Shape text and return positioned glyphs.
    ///
    /// - Parameters:
    ///   - text: The text string to shape.
    ///   - features: Optional OpenType features to enable or disable during shaping.
    /// - Returns: An array of positioned glyphs with their paths and positions.
    ///
    /// Example:
    /// ```swift
    /// // Shape with small caps and old-style numerals
    /// let glyphs = font.glyphs(for: "Hello 123", features: [.smallCaps, .oldStyleNumerals])
    /// ```
    public func glyphs(for text: String, features: [OpenTypeFeature] = []) -> [PositionedGlyph] {
        // Create HarfBuzz buffer
        let buffer = hb_buffer_create()
        defer { hb_buffer_destroy(buffer) }

        // Add text to buffer
        text.withCString { cStr in
            hb_buffer_add_utf8(buffer, cStr, Int32(text.utf8.count), 0, Int32(text.utf8.count))
        }

        // Let HarfBuzz auto-detect direction, script, and language from text content
        hb_buffer_guess_segment_properties(buffer)

        // Convert OpenType features to HarfBuzz format and shape
        if features.isEmpty {
            hb_shape(hbFont, buffer, nil, 0)
        } else {
            var hbFeatures = features.map { feature -> hb_feature_t in
                let bytes = Array(feature.tag.utf8)
                let tag = makeTag(bytes[0], bytes[1], bytes[2], bytes[3])
                return hb_feature_t(
                    tag: tag,
                    value: feature.value,
                    start: 0,
                    end: UInt32.max // HB_FEATURE_GLOBAL_END
                )
            }
            hb_shape(hbFont, buffer, &hbFeatures, UInt32(hbFeatures.count))
        }

        // Get glyph info and positions
        var glyphCount: UInt32 = 0
        let glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount)
        let glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount)

        var result: [PositionedGlyph] = []
        var cursorX: Double = 0
        var cursorY: Double = 0

        for i in 0..<Int(glyphCount) {
            let info = glyphInfos![i]
            let pos = glyphPositions![i]

            let glyphID = info.codepoint
            let xOffset = Double(pos.x_offset) / 64.0
            let yOffset = Double(pos.y_offset) / 64.0
            let xAdvance = Double(pos.x_advance) / 64.0
            let yAdvance = Double(pos.y_advance) / 64.0

            let position = Point(x: cursorX + xOffset, y: cursorY + yOffset)
            let advance = Point(x: xAdvance, y: yAdvance)

            if let path = extractGlyphPath(glyphID: glyphID) {
                result.append(PositionedGlyph(path: path, position: position, advance: advance, cluster: info.cluster))
            }

            cursorX += xAdvance
            cursorY += yAdvance
        }

        return result
    }

    /// Extract the outline path for a specific glyph
    private func extractGlyphPath(glyphID: UInt32) -> Path? {
        // Load glyph
        let error = FT_Load_Glyph(ftFace, FT_UInt(glyphID), FT_Int32(FT_LOAD_NO_BITMAP))
        guard error == 0 else { return nil }

        let glyph = ftFace.pointee.glyph
        guard glyph?.pointee.format == FT_GLYPH_FORMAT_OUTLINE else { return nil }

        var outline = glyph!.pointee.outline
        var path = Path()

        // Define outline decomposition callbacks
        var funcs = FT_Outline_Funcs(
            move_to: { (to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                // Close previous contour if there is one
                if !path.pointee.isEmpty {
                    path.pointee.close()
                }
                let point = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.moveTo(point)
                return 0
            },
            line_to: { (to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let point = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.lineTo(point)
                return 0
            },
            conic_to: { (control, to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let ctrl = Point(
                    x: Double(control!.pointee.x) / 64.0,
                    y: Double(control!.pointee.y) / 64.0
                )
                let end = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.quadraticTo(control: ctrl, end: end)
                return 0
            },
            cubic_to: { (control1, control2, to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let c1 = Point(
                    x: Double(control1!.pointee.x) / 64.0,
                    y: Double(control1!.pointee.y) / 64.0
                )
                let c2 = Point(
                    x: Double(control2!.pointee.x) / 64.0,
                    y: Double(control2!.pointee.y) / 64.0
                )
                let end = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.cubicTo(control1: c1, control2: c2, end: end)
                return 0
            },
            shift: 0,
            delta: 0
        )

        withUnsafeMutablePointer(to: &path) { pathPtr in
            _ = FT_Outline_Decompose(&outline, &funcs, pathPtr)
        }

        // Close path if needed (FreeType doesn't always emit close)
        if !path.isEmpty {
            path.close()
        }

        return path
    }
}
