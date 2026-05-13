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
        allTags.formUnion(featureTags(face: face, tableTag: hb_tag_t(openTypeTag: "GSUB")))

        // Get features from GPOS table (positioning like kerning)
        allTags.formUnion(featureTags(face: face, tableTag: hb_tag_t(openTypeTag: "GPOS")))

        return allTags.map(\.openTypeTag).sorted()
    }

    /// Returns the feature tags declared in a specific OpenType layout table.
    private func featureTags(face: OpaquePointer?, tableTag: hb_tag_t) -> [hb_tag_t] {
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
