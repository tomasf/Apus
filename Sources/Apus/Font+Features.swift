internal import harfbuzz

extension Font {
    // MARK: - OpenType Feature Enumeration

    /// Returns the OpenType features available in this font.
    ///
    /// This includes features from both the GSUB (substitution) and GPOS (positioning) tables.
    /// Common features include ligatures, small caps, numerals styles, and kerning.
    ///
    /// - Returns: An array of 4-character feature tag strings (e.g., "liga", "smcp", "kern").
    public var availableFeatures: [String] {
        let face = hb_font_get_face(hbFont)

        var allTags = Set<hb_tag_t>()

        // Get features from GSUB table (substitutions like ligatures, small caps)
        let gsubTag = makeTag(UInt8(ascii: "G"), UInt8(ascii: "S"), UInt8(ascii: "U"), UInt8(ascii: "B"))
        allTags.formUnion(getFeatureTags(face: face, tableTag: gsubTag))

        // Get features from GPOS table (positioning like kerning)
        let gposTag = makeTag(UInt8(ascii: "G"), UInt8(ascii: "P"), UInt8(ascii: "O"), UInt8(ascii: "S"))
        allTags.formUnion(getFeatureTags(face: face, tableTag: gposTag))

        // Convert tags to strings
        return allTags.map { tagToString($0) }.sorted()
    }

    /// Get feature tags from a specific OpenType table
    private func getFeatureTags(face: OpaquePointer!, tableTag: hb_tag_t) -> [hb_tag_t] {
        // First call to get the count
        var count: UInt32 = 0
        let total = hb_ot_layout_table_get_feature_tags(face, tableTag, 0, &count, nil)

        guard total > 0 else { return [] }

        // Allocate buffer and get tags
        var tags = [hb_tag_t](repeating: 0, count: Int(total))
        count = total
        _ = hb_ot_layout_table_get_feature_tags(face, tableTag, 0, &count, &tags)

        return Array(tags.prefix(Int(count)))
    }
}
