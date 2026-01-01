internal import harfbuzz

extension Font {
    // MARK: - Variable Font Support

    /// Whether this font is a variable font with variation axes.
    public var isVariable: Bool {
        let face = hb_font_get_face(hbFont)
        return hb_ot_var_has_data(face) != 0
    }

    /// The variation axes available in this font.
    ///
    /// Returns an empty array for non-variable fonts.
    public var variationAxes: [VariationAxis] {
        let face = hb_font_get_face(hbFont)

        var axisCount: UInt32 = 0
        let total = hb_ot_var_get_axis_infos(face, 0, &axisCount, nil)
        guard total > 0 else { return [] }

        var axisInfos = [hb_ot_var_axis_info_t](repeating: hb_ot_var_axis_info_t(), count: Int(total))
        axisCount = total
        _ = hb_ot_var_get_axis_infos(face, 0, &axisCount, &axisInfos)

        return axisInfos.prefix(Int(axisCount)).map { info in
            let tag = tagToString(info.tag)
            let name = getNameString(face: face, nameID: info.name_id) ?? Self.registeredAxisName(for: tag)
            return VariationAxis(
                tag: tag,
                name: name ?? tag,
                minValue: Double(info.min_value),
                defaultValue: Double(info.default_value),
                maxValue: Double(info.max_value)
            )
        }
    }

    /// Well-known names for variation axes.
    private static func registeredAxisName(for tag: String) -> String? {
        switch tag {
        case FontVariation.weightTag: return "Weight"
        case FontVariation.widthTag: return "Width"
        case FontVariation.slantTag: return "Slant"
        case FontVariation.italicTag: return "Italic"
        case FontVariation.opticalSizeTag: return "Optical Size"
        case FontVariation.yAxisTag: return "Y Axis"
        default: return nil
        }
    }

    /// The named instances (predefined axis combinations) available in this font.
    ///
    /// Named instances represent common variations like "Bold" or "Light Condensed".
    /// Returns an empty array for non-variable fonts.
    public var namedInstances: [NamedInstance] {
        let face = hb_font_get_face(hbFont)
        let count = hb_ot_var_get_named_instance_count(face)
        guard count > 0 else { return [] }

        let axisCount = hb_ot_var_get_axis_count(face)

        return (0..<count).compactMap { index in
            let nameID = hb_ot_var_named_instance_get_subfamily_name_id(face, index)
            let name = getNameString(face: face, nameID: nameID)

            var coordCount = axisCount
            var coords = [Float](repeating: 0, count: Int(axisCount))
            _ = hb_ot_var_named_instance_get_design_coords(face, index, &coordCount, &coords)

            return NamedInstance(
                index: Int(index),
                name: name ?? "Instance \(index)",
                coordinates: coords.prefix(Int(coordCount)).map { Double($0) }
            )
        }
    }
}
