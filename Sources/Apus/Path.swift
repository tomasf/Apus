public enum PathElement: Hashable, Sendable {
    case moveTo(Point)
    case lineTo(Point)
    case quadraticTo(control: Point, end: Point)
    case cubicTo(control1: Point, control2: Point, end: Point)
    case close
}

public struct Path: Hashable, Sendable {
    public var elements: [PathElement]

    public init(_ elements: [PathElement] = []) {
        self.elements = elements
    }

    public var isEmpty: Bool {
        elements.isEmpty
    }

    public mutating func moveTo(_ point: Point) {
        elements.append(.moveTo(point))
    }

    public mutating func lineTo(_ point: Point) {
        elements.append(.lineTo(point))
    }

    public mutating func quadraticTo(control: Point, end: Point) {
        elements.append(.quadraticTo(control: control, end: end))
    }

    public mutating func cubicTo(control1: Point, control2: Point, end: Point) {
        elements.append(.cubicTo(control1: control1, control2: control2, end: end))
    }

    public mutating func close() {
        elements.append(.close)
    }

    /// Returns a new path with all points translated by the given offset
    public func translated(by offset: Point) -> Path {
        Path(elements.map { element in
            switch element {
            case .moveTo(let p):
                .moveTo(p + offset)
            case .lineTo(let p):
                .lineTo(p + offset)
            case .quadraticTo(let control, let end):
                .quadraticTo(control: control + offset, end: end + offset)
            case .cubicTo(let c1, let c2, let end):
                .cubicTo(control1: c1 + offset, control2: c2 + offset, end: end + offset)
            case .close:
                .close
            }
        })
    }
}
