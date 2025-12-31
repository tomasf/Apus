#if canImport(CoreText)
import Foundation
import CoreText

internal extension FontRepository {
    static func matchForCoreTextFont(family name: String, style: String?) throws(LookupError) -> Match? {
        let attributes = NSMutableDictionary()
        attributes[kCTFontNameAttribute] = name
        if let style = style {
            attributes[kCTFontStyleNameAttribute] = style
        }

        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)

        guard let match = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil),
              let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL,
              let matchedFamily = CTFontDescriptorCopyAttribute(match, kCTFontFamilyNameAttribute) as? String,
              let matchedStyle = CTFontDescriptorCopyAttribute(match, kCTFontStyleNameAttribute) as? String
        else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return Match(data: data, familyName: matchedFamily, style: matchedStyle)
        } catch {
            throw .readingFontFailed
        }
    }
}
#endif
