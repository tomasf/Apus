#if canImport(CoreText)
import Foundation
import CoreText

internal extension FontRepository {
    // CTFontDescriptorCreateMatchingFontDescriptor makes a synchronous XPC call to the font
    // registry daemon. Running many concurrent lookups from the Swift cooperative thread pool
    // exhausts the pool. A serial queue serializes these calls to prevent this.
    static private let lookupQueue = DispatchQueue(label: "se.tomasf.apus.fontlookup")

    static private func internalCoreTextMatch(family name: String, style: String?) throws(LookupError) -> Match? {
        let attributes = NSMutableDictionary()
        attributes[kCTFontFamilyNameAttribute] = name
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
            throw LookupError.readingFontFailed
        }
    }

    static func coreTextMatch(family name: String, style: String?) throws(LookupError) -> Match? {
        do {
            return try lookupQueue.sync {
                try internalCoreTextMatch(family: name, style: style)
            }
        } catch let error as LookupError {
            throw error
        } catch {
            return nil
        }
    }

    static func availableCoreTextFamilies() throws(LookupError) -> [Family] {
        guard let familyNames = CTFontManagerCopyAvailableFontFamilyNames() as? [String] else {
            return []
        }

        return familyNames.sorted().compactMap { familyName in
            let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: familyName]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)

            guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor] else {
                return nil
            }

            let styles = matches.compactMap { match in
                CTFontDescriptorCopyAttribute(match, kCTFontStyleNameAttribute) as? String
            }

            guard !styles.isEmpty else { return nil }
            return Family(name: familyName, styles: styles)
        }
    }
}
#endif
