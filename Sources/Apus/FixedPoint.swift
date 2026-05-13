internal import freetype

internal extension Double {
    /// Converts a 26.6 fixed-point integer (FreeType/HarfBuzz convention: 6 fractional bits)
    /// to a Double in pixel units.
    init<T: BinaryInteger>(fixed26_6 value: T) {
        self = Double(value) / 64.0
    }
}

internal extension Point {
    /// Initializes a Point from a FreeType vector. The x and y components are interpreted as
    /// 26.6 fixed point, matching how FreeType reports outline coordinates and metrics.
    init(_ vector: FT_Vector) {
        self.init(x: Double(fixed26_6: vector.x), y: Double(fixed26_6: vector.y))
    }
}
